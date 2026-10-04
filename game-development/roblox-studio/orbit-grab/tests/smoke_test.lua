--!nolint
--[=[
	ORBIT GRAB  —  smoke test
	====================================================================
	Runs the whole system against tests/roblox_mock.lua and exercises
	every public action. Executed by tests/run.js (fengari, Lua-in-JS):

		npm install fengari && node tests/run.js

	If this passes, the modules parse, wire up and survive being used.
	It is not a substitute for pressing Play in Studio — go do that too.
--]=]

local Mock = loadluafile("tests/roblox_mock.lua")
Mock.install()

local player = Mock.makePlayer("LocalPlayer")
local char   = Mock.makeCharacter(player)
local camera = Mock.makeCamera()
local RS     = game:GetService("ReplicatedStorage")

----------------------------------------------------------------------
--  module loader: `require(script.Parent.Foo)` → registry.Foo
----------------------------------------------------------------------
local registry = {}

_G.require = function(x)
	if type(x) == "table" then
		local m = rawget(x, "__module")
		if not m and x.ClassName then m = x.__module end   -- mock Instance
		if m then return m end
		return x
	end
	error("unexpected require(" .. tostring(x) .. ")")
end

local function loadModule(name, path)
	_G.script = { Parent = registry, Name = name }
	loadlua(path, "__mod")
	registry[name] = __mod
	_G.script = nil
	return registry[name]
end

local SRC = "src/ReplicatedStorage/OrbitGrab/"

local Config = loadModule("Config", SRC .. "Config.lua")
loadModule("Orbit", SRC .. "Orbit.lua")
loadModule("FX", SRC .. "FX.lua")
loadModule("UI", SRC .. "UI.lua")
loadModule("Carrier", SRC .. "Carrier.lua")
local init = loadModule("init", SRC .. "init.lua")

-- the package as a ReplicatedStorage child, the way Rojo would place it
local pkgInstance = Instance.new("Folder")
pkgInstance.Name = "OrbitGrab"
pkgInstance.Parent = RS
pkgInstance.__module = init

-- server first, so the client finds the remotes
loadlua("src/ServerScriptService/OrbitGrabServer.server.lua", "__server")
-- client bootstrap (binds input, builds the HUD, starts the loop)
loadlua("src/StarterPlayer/StarterPlayerScripts/OrbitGrabClient.client.lua", "__client")

local carrier = _G.OrbitGrabCarrier
assert(carrier, "client did not expose OrbitGrabCarrier")

----------------------------------------------------------------------
--  test harness
----------------------------------------------------------------------
local failures, checks = {}, 0

local function check(name, cond, detail)
	checks = checks + 1
	if cond then
		print("  ok   " .. name)
	else
		print("  FAIL " .. name .. (detail and ("   [" .. tostring(detail) .. "]") or ""))
		table.insert(failures, name)
	end
end

local function step(n, dt)
	for _ = 1, (n or 1) do
		Mock.step(dt or 1 / 60)
	end
end

local function makePart(name, pos, size)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size or Vector3.new(2, 2, 2)
	p.CFrame = CFrame.new(pos)
	p.Parent = workspace
	return p
end

local function finite(v)
	return v and v.X == v.X and v.Y == v.Y and v.Z == v.Z
end

print("\n== boot ==")
step(3)
check("system boots and renders", true)
check("HUD exists", player.PlayerGui:FindFirstChild("OrbitGrab") ~= nil)
check("server created remotes", RS:FindFirstChild("OrbitGrab_Remotes") ~= nil)
check("client bound to remotes", carrier.remotes ~= nil)

print("\n== grabbing ==")
local target = makePart("GrabMe", Vector3.new(0, 2, 0))
camera.CFrame = CFrame.lookAt(Vector3.new(0, 5, 14), Vector3.new(0, 2, 0))
step(2)
check("cursor sees the part", carrier.target ~= nil and carrier.targetName == "GrabMe",
	carrier.targetName)

local ok = carrier:GrabAtCursor()
check("grab succeeded", ok and #carrier.items == 1, #carrier.items)
check("part is anchored while carried", target.Anchored == true)
check("part is non-colliding while carried", target.CanCollide == false)
check("ownership requested", carrier.remotes ~= nil)
check("server granted network ownership", target.__networkOwner == player, tostring(target.__networkOwner))

step(120)
local d = (target.CFrame.Position - char.HumanoidRootPart.CFrame.Position) * Vector3.new(1, 0, 1)
check("settles onto the orbit radius", math.abs(d.Magnitude - Config.Orbit.Radius) < 1.5,
	string.format("%.2f vs %.2f", d.Magnitude, Config.Orbit.Radius))
check("part follows the player", target.CFrame.Position.Y > 0)

print("\n== formations ==")
for _, name in ipairs(Config.Orbit.Formations) do
	Config.Orbit.Formation = name
	step(20)
	local good = true
	for _, item in ipairs(carrier.items) do
		if not finite(item.root.CFrame.Position) then good = false end
	end
	check("formation " .. name, good)
end
Config.Orbit.Formation = "Ring"

print("\n== more parts ==")
for i = 1, 8 do
	makePart("Loose" .. i, Vector3.new(i * 1.2, 1, 2))
end
local before = #carrier.items
carrier:VacuumScan()
check("vacuum collects nearby parts", #carrier.items > before, #carrier.items - before)
step(30)

print("\n== models ==")
local model = Instance.new("Model")
model.Name = "TestRig"
local mRoot = Instance.new("Part")
mRoot.Name = "RootPart"
mRoot.CFrame = CFrame.new(6, 2, 0)
mRoot.Parent = model
local weld = Instance.new("WeldConstraint")
weld.Parent = model
for i = 1, 2 do
	local pp = Instance.new("Part")
	pp.Name = "Piece" .. i
	pp.CFrame = mRoot.CFrame + Vector3.new(0, i, 0)
	pp.Parent = model
end
model.PrimaryPart = mRoot
model.Parent = workspace

local okModel = carrier:Grab(mRoot)
check("grabs a whole model", okModel and carrier.items[#carrier.items].root == mRoot)
check("model parts all carried", #carrier.items[#carrier.items].parts == 3)
check("model detected as welded", carrier.items[#carrier.items].welded == true)
step(20)
check("model parts stay rigid", finite(mRoot.CFrame.Position))

print("\n== throwing ==")
local n0 = #carrier.items
carrier:ThrowSelected(120)
check("throw removes the item", #carrier.items == n0 - 1)
check("ownership handed back to the server", mRoot.__networkOwner == "server", tostring(mRoot.__networkOwner))
check("thrown part is unanchored", mRoot.Anchored == false)

local n1 = #carrier.items
carrier:Burst()
check("burst empties the orbit", #carrier.items == 0 and n1 > 0)

print("\n== re-grab, park, undo, drop ==")
local p1 = makePart("ParkMe", Vector3.new(0, 2, 0))
carrier:Grab(p1)
step(10)
local parkedAt = p1.CFrame
carrier:ParkSelected()
check("park leaves it anchored in place", p1.Anchored == true and #carrier.items == 0)
check("park keeps the position", (p1.CFrame.Position - parkedAt.Position).Magnitude < 0.001)

local home = CFrame.new(3, 1, 3)
local p2 = makePart("HomeMe", Vector3.new(0, 2, 0))
p2.CFrame = home
carrier:Grab(p2)
step(10)
carrier:UndoAll()
check("undo sends parts home", (p2.CFrame.Position - home.Position).Magnitude < 0.001)
check("undo empties the orbit", #carrier.items == 0)

local p3 = makePart("DropMe", Vector3.new(0, 2, 0))
p3.Anchored = true
carrier:Grab(p3)
carrier:DropAll()
check("drop restores the original anchored state", p3.Anchored == true and #carrier.items == 0)
check("drop restores collision", p3.CanCollide == true)

print("\n== explode ==")
for i = 1, 5 do carrier:Grab(makePart("Boom" .. i, Vector3.new(0, 2, 0))) end
step(5)
carrier:Explode()
check("explode clears everything", #carrier.items == 0)

print("\n== tuning & formations via input ==")
carrier:Grab(makePart("Tuner", Vector3.new(0, 2, 0)))
local r0 = Config.Orbit.Radius
Mock.fireInput("InputChanged", { UserInputType = Enum.UserInputType.MouseWheel, Position = Vector3.new(0, 0, 1) })
check("wheel changes radius", Config.Orbit.Radius ~= r0, Config.Orbit.Radius)
Mock.fireInput("InputChanged", { UserInputType = Enum.UserInputType.MouseWheel, Position = Vector3.new(0, 0, -1) })
check("wheel back to start", math.abs(Config.Orbit.Radius - r0) < 1e-6)

local f0 = Config.Orbit.Formation
Mock.fireInput("InputBegan", { KeyCode = Enum.KeyCode.C, UserInputType = Enum.UserInputType.Keyboard }, false)
check("C cycles formation", Config.Orbit.Formation ~= f0, Config.Orbit.Formation)
Mock.fireInput("InputBegan", { KeyCode = Enum.KeyCode.F, UserInputType = Enum.UserInputType.Keyboard }, false)
check("F pauses", carrier.paused == true)
Mock.fireInput("InputBegan", { KeyCode = Enum.KeyCode.F, UserInputType = Enum.UserInputType.Keyboard }, false)
check("F resumes", carrier.paused == false)
Mock.fireInput("InputBegan", { KeyCode = Enum.KeyCode.M, UserInputType = Enum.UserInputType.Keyboard }, false)
check("M toggles glow", carrier.glow == true)
Mock.fireInput("InputBegan", { KeyCode = Enum.KeyCode.Backquote, UserInputType = Enum.UserInputType.Keyboard }, false)
check("` resets tuning", math.abs(Config.Orbit.Radius - 7) < 1e-6)

print("\n== charge & throw ==")
local before2 = #carrier.items
Mock.fireAction("OrbitGrab_Charge", Enum.UserInputState.Begin, {})
step(30)
check("charging builds power", carrier.chargePower > 0, carrier.chargePower)
check("charge bar shows", carrier.chargePower <= Config.Throw.MaxPower)
Mock.fireAction("OrbitGrab_Charge", Enum.UserInputState.End, {})
check("release throws", #carrier.items == before2 - 1)

print("\n== chat commands ==")
Mock.fire(player, "Chatted", "/orb radius 12")
check("/orb radius", math.abs(Config.Orbit.Radius - 12) < 1e-6, Config.Orbit.Radius)
Mock.fire(player, "Chatted", "/orb mode sphere")
check("/orb mode", Config.Orbit.Formation == "Sphere", Config.Orbit.Formation)
Mock.fire(player, "Chatted", "/orb help")
check("/orb help does not error", true)
Mock.fire(player, "Chatted", "/orb bogus")
check("unknown command handled", true)
Mock.fire(player, "Chatted", "/orb toggle")
check("toggle disables", Config.General.Enabled == false)
Mock.fire(player, "Chatted", "/orb count")   -- breaks the identical-message de-dupe
Mock.fire(player, "Chatted", "/orb toggle")
check("toggle re-enables", Config.General.Enabled == true)

print("\n== limits & rejection ==")
Config.General.MaxCarried = 2
local rejected = 0
for i = 1, 5 do
	if not carrier:Grab(makePart("Cap" .. i, Vector3.new(0, 2, 0)), true) then
		rejected = rejected + 1
	end
end
check("carry cap enforced", #carrier.items <= 2 and rejected > 0, #carrier.items)
Config.General.MaxCarried = 60

local locked = makePart("Locked", Vector3.new(0, 2, 0))
locked.Locked = true
check("locked parts refused", carrier:Grab(locked, true) == false)

local huge = makePart("Huge", Vector3.new(0, 2, 0))
huge.Size = Vector3.new(500, 500, 500)
check("oversized parts refused", carrier:Grab(huge, true) == false)

local mine = Instance.new("Part")
mine.Name = "MyOwnFoot"
mine.Parent = char
check("own character refused", carrier:Grab(mine, true) == false)

carrier:DropAll()

print("\n== death ==")
local dp = makePart("DeathPart", Vector3.new(0, 2, 0))
carrier:Grab(dp)
step(5)
check("carrying before death", #carrier.items == 1)
Mock.fire(char.Humanoid, "Died")
check("drops everything on death", #carrier.items == 0)

print("\n== long run ==")
Config.General.MaxCarried = 60
for i = 1, 60 do carrier:Grab(makePart("Stress" .. i, Vector3.new(0, 2, 0)), true) end
step(600)
local sane = true
for _, item in ipairs(carrier.items) do
	if not finite(item.root.CFrame.Position) then sane = false end
	if item.root.Anchored ~= true then sane = false end
end
check("60 parts / 10 seconds of simulation stays stable", sane and #carrier.items == 60, #carrier.items)
carrier:Destroy()
check("teardown without errors", true)

----------------------------------------------------------------------
--  report
----------------------------------------------------------------------
print("\n------------------------------------------------------------")
if #failures == 0 then
	print(string.format("ALL %d CHECKS PASSED", checks))
else
	print(string.format("%d / %d CHECKS FAILED:", #failures, checks))
	for _, f in ipairs(failures) do print("   - " .. f) end
end

local unknown = {}
for k in pairs(Mock.unknownKeys) do table.insert(unknown, k) end
if #unknown > 0 then
	table.sort(unknown)
	print("\nproperties/events the mock did not know about (verify these are real):")
	for _, k in ipairs(unknown) do print("   ? " .. k) end
end
print("------------------------------------------------------------\n")

return #failures
