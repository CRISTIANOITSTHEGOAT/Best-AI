--!nolint
--[=[
	ORBIT GRAB  —  all-in-one bundle test
	====================================================================
	Loads dist/OrbitGrab_AllInOne.client.lua (the single-file build people
	paste into Studio) and checks that it wires up and behaves the same
	way the Rojo module tree does.

		node tests/run.js tests/bundle_test.lua
--]=]

local Mock = loadluafile("tests/roblox_mock.lua")
Mock.install()

local player = Mock.makePlayer("LocalPlayer")
local char   = Mock.makeCharacter(player)
local camera = Mock.makeCamera()
local RS     = game:GetService("ReplicatedStorage")

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
local function step(n)
	for _ = 1, n do Mock.step(1 / 60) end
end

-- the bundle needs no ReplicatedStorage package: it carries its own modules
loadlua("src/ServerScriptService/OrbitGrabServer.server.lua", "__server")
local okLoad, err = pcall(loadlua, "dist/OrbitGrab_AllInOne.client.lua", "__bundle")
check("all-in-one file loads", okLoad, err)

if okLoad then
	local carrier = _G.OrbitGrabCarrier
	check("carrier created", carrier ~= nil)
	check("HUD built", player.PlayerGui:FindFirstChild("OrbitGrab") ~= nil)

	step(3)

	local part = Instance.new("Part")
	part.Name = "BundlePart"
	part.Size = Vector3.new(2, 2, 2)
	part.CFrame = CFrame.new(Vector3.new(0, 2, 0))
	part.Parent = workspace
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 5, 14), Vector3.new(0, 2, 0))

	step(2)
	check("aim finds the part", carrier.targetName == "BundlePart", carrier.targetName)
	check("grab works", carrier:GrabAtCursor() == true and #carrier.items == 1)
	step(120)
	local d = (part.CFrame.Position - char.HumanoidRootPart.CFrame.Position) * Vector3.new(1, 0, 1)
	check("orbits at the configured radius", math.abs(d.Magnitude - 7) < 1.5, d.Magnitude)
	check("config is reachable", _G.OrbitGrab.Config.Orbit.Radius == 7)

	carrier:Burst()
	check("burst works", #carrier.items == 0)
	carrier:Destroy()
	check("teardown", true)
end

print("\n------------------------------------------------------------")
if #failures == 0 then
	print(string.format("BUNDLE: ALL %d CHECKS PASSED", checks))
else
	print(string.format("BUNDLE: %d / %d CHECKS FAILED", #failures, checks))
	for _, f in ipairs(failures) do print("   - " .. f) end
end
print("------------------------------------------------------------\n")

return #failures
