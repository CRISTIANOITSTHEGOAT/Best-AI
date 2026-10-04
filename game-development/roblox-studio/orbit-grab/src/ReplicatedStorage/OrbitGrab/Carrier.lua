--!nolint
--[=[
	ORBIT GRAB  —  Carrier.lua
	====================================================================
	The engine. Owns the list of parts you're carrying, moves them every
	frame, and exposes one method per action (grab / throw / burst /
	explode / drop / undo / park / vacuum / cycle formation / tune).

	How parts are moved
	-------------------
	While carried, a part is Anchored and driven purely by CFrame on the
	client. That means zero physics jitter, zero flinging, zero fighting
	with the server, and perfectly smooth formation morphing — parts glide
	to new slots when the formation changes or when one is removed.

	On release the original Anchored / CanCollide / CanQuery state is
	restored, so a part always goes back to behaving exactly as it did
	before you touched it (except where you threw it, obviously).

	Multiplayer
	-----------
	The client asks the server for network ownership of what it grabs
	(OrbitGrabServer.server.lua). Without that server script everything
	still works, but only you will see the parts move — so ship the
	server script too if other players are in the game.
--]=]

local Players          = game:GetService("Players")

local Config = require(script.Parent.Config)
local Orbit  = require(script.Parent.Orbit)
local FX     = require(script.Parent.FX)
local UI     = require(script.Parent.UI)

local TAU = Orbit.TAU
local LocalPlayer = Players.LocalPlayer

local Carrier = {}
Carrier.__index = Carrier

----------------------------------------------------------------------
--  construction
----------------------------------------------------------------------
function Carrier.new()
	local self = setmetatable({}, Carrier)

	self.items        = {}     -- array of carried objects
	self.carriedSet   = {}     -- [BasePart] = true, for O(1) "already carrying?" checks
	self.time         = 0      -- orbital clock (respects pause + slow-mo)
	self.timeScale    = 1
	self.paused       = false
	self.slowmo       = false
	self.glow         = Config.Visuals.Glow
	self.vacuuming    = false
	self._vacuumAccum = 0
	self.selected     = nil
	self.charging     = false
	self.chargePower  = 0
	self.target       = nil
	self.history      = {}
	self.historySpan  = 2.0
	self._histPtr     = nil
	self.remotes      = nil
	self.connections  = {}
	self.centerCF     = CFrame.new()
	self.centerVel    = Vector3.new()

	-- snapshot of the default tuning so `/orb reset` and ` have something to go back to
	self.defaults = {}
	for k, v in pairs(Config.Orbit) do
		if type(v) == "number" then
			self.defaults[k] = v
		end
	end

	FX.Init(Config)

	UI.Init(Config, {
		onGrab       = function() self:GrabAtCursor() end,
		onThrowStart = function() self:BeginCharge() end,
		onThrowEnd   = function() self:ReleaseCharge() end,
		onMode       = function() self:CycleFormation(1) end,
		onDrop       = function() self:DropAll() end,
	})

	self:BindRemotes()
	self:BindCharacter(LocalPlayer.Character)
	table.insert(self.connections, LocalPlayer.CharacterAdded:Connect(function(char)
		self:BindCharacter(char)
	end))

	return self
end

----------------------------------------------------------------------
--  plumbing
----------------------------------------------------------------------
function Carrier:BindRemotes()
	task.spawn(function()
		local rs = game:GetService("ReplicatedStorage")
		local folder = rs:WaitForChild("OrbitGrab_Remotes", 6)
		if folder then
			self.remotes = {
				Request = folder:FindFirstChild("RequestOwnership"),
				Release = folder:FindFirstChild("ReleaseOwnership"),
			}
		elseif Config.Debug then
			warn("[OrbitGrab] no server remotes found — running in local-only mode")
		end
	end)
end

function Carrier:BindCharacter(char)
	if not char then return end
	if self.diedConn then self.diedConn:Disconnect() end
	local humanoid = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 5)
	if humanoid then
		self.diedConn = humanoid.Died:Connect(function()
			if Config.General.UndoOnDeath then
				self:UndoAll()
			elseif Config.General.DropOnDeath then
				self:DropAll()
			end
		end)
	end
end

function Carrier:GetRootPart()
	local char = LocalPlayer.Character
	if not char then return nil end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then
		root = char.PrimaryPart
	end
	return root
end

----------------------------------------------------------------------
--  aiming & validation
----------------------------------------------------------------------
function Carrier:AimRay()
	local cam = workspace.CurrentCamera
	if Config.General.AimMode == "Center" then
		return cam.CFrame.Position, cam.CFrame.LookVector
	end
	local mouse = LocalPlayer:GetMouse()
	local unit = cam:ScreenPointToRay(mouse.X, mouse.Y)
	return unit.Origin, unit.Direction
end

function Carrier:RayParams()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = {}
	if LocalPlayer.Character then table.insert(ignore, LocalPlayer.Character) end
	if FX.GetCarryFolder() then table.insert(ignore, FX.GetCarryFolder()) end
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true
	return params
end

function Carrier:Raycast()
	local origin, dir = self:AimRay()
	return workspace:Raycast(origin, dir * Config.General.Reach, self:RayParams())
end

--[[ Carrier:IsGrabbable(part) -> boolean, reason ]]
function Carrier:IsGrabbable(part)
	local gen = Config.General
	if not part or not part:IsA("BasePart") then return false, "not a part" end
	if part:IsA("Terrain") then return false, "terrain" end
	for _, n in ipairs(gen.IgnoreNames) do
		if part.Name == n then return false, "blacklisted" end
	end
	if part:GetAttribute(gen.IgnoreAttribute) then return false, "marked ignore" end
	if not gen.AllowLocked and part.Locked then return false, "locked" end
	if not gen.AllowAnchored and part.Anchored then return false, "anchored" end
	if self.carriedSet[part] then return false, "already carrying" end

	local char = LocalPlayer.Character
	if char and part:IsDescendantOf(char) then return false, "that's you" end

	local size = part.Size
	if math.max(size.X, size.Y, size.Z) > gen.MaxPartSize then return false, "too big" end
	if part.AssemblyMass > gen.MaxMass then return false, "too heavy" end

	if gen.OnlyInFolder then
		local folder = workspace:FindFirstChild(gen.OnlyInFolder)
		if not folder or not part:IsDescendantOf(folder) then
			return false, "outside the allowed area"
		end
	end
	return true, nil
end

--[[ Resolve what actually gets picked up: a single part, or its whole Model ]]
function Carrier:ResolveTarget(part)
	local gen = Config.General
	local model = part:FindFirstAncestorOfClass("Model")

	if gen.GrabWholeModel and model and model.PrimaryPart and model ~= LocalPlayer.Character then
		local npc = model:FindFirstChildOfClass("Humanoid") ~= nil
		if (not npc) or gen.AllowNPCs then
			local parts = {}
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") and not self.carriedSet[d] then
					table.insert(parts, d)
				end
			end
			if #parts > 0 and #parts <= gen.MaxModelParts then
				return model.PrimaryPart, parts, model
			end
		end
	end
	return part, { part }, part
end

function Carrier:TargetLabel(result)
	local instance = result.Instance
	local model = instance:FindFirstAncestorOfClass("Model")
	if Config.General.GrabWholeModel and model and model.PrimaryPart
		and model ~= LocalPlayer.Character
		and (Config.General.AllowNPCs or not model:FindFirstChildOfClass("Humanoid")) then
		return model.Name
	end
	return instance.Name
end

----------------------------------------------------------------------
--  grabbing
----------------------------------------------------------------------
function Carrier:Grab(part, quiet)
	local gen = Config.General
	if not gen.Enabled then return false end

	if #self.items >= gen.MaxCarried then
		if not quiet then UI.Toast("Carry limit reached (" .. gen.MaxCarried .. ")", UI.Colors.BAD) end
		FX.Sound("Error")
		return false
	end

	local ok, why = self:IsGrabbable(part)
	if not ok then
		if not quiet then UI.Toast("Can't grab — " .. tostring(why), UI.Colors.BAD) end
		return false
	end

	local root, parts, container = self:ResolveTarget(part)

	local item = {
		root        = root,
		parts       = parts,
		container   = container,
		offsets     = {},
		saved       = {},
		seed        = math.random(),
		blend       = 0,
		grabTime    = os.clock(),
		current     = root.CFrame,
		originalRot = root.CFrame - root.CFrame.Position,
		freezeOffset= nil,
		highlight   = nil,
		light       = nil,
		welded      = false,
	}

	-- is the target a single rigid assembly (welds) or a bag of loose parts?
	local scope = container
	if scope:IsA("Model") then
		for _, d in ipairs(scope:GetDescendants()) do
			if d:IsA("WeldConstraint") or d:IsA("Weld") or d:IsA("Motor6D") or d:IsA("Snap") then
				item.welded = true
				break
			end
		end
	end

	local rootCF = root.CFrame
	for _, p in ipairs(parts) do
		item.offsets[p] = rootCF:Inverse() * p.CFrame
		item.saved[p] = {
			CFrame     = p.CFrame,
			Anchored   = p.Anchored,
			CanCollide = p.CanCollide,
			CanQuery   = p.CanQuery,
		}
		self.carriedSet[p] = true
		p.Anchored   = true      -- carried parts are kinematic: no physics, no jitter
		p.CanCollide = false     -- don't shove the player around
		p.CanQuery   = false     -- don't let the cursor hit them while carried
	end

	table.insert(self.items, item)
	self.selected = item

	FX.AttachCarryFX(item)
	if Config.Visuals.GrabBurst then
		FX.Burst(root.Position, Config.Visuals.BurstColor, 10)
	end
	if not quiet then FX.Sound("Grab") end
	self:RequestOwnership(item)
	FX.StartLoop()

	return true, item
end

function Carrier:GrabAtCursor()
	local result = self:Raycast()
	if not result then
		UI.Toast("Nothing in reach", UI.Colors.DIM)
		return false
	end
	return self:Grab(result.Instance)
end

----------------------------------------------------------------------
--  releasing
----------------------------------------------------------------------
--[[
	Carrier:Release(item, { mode = drop|throw|park|home, direction, power })
]]
function Carrier:Release(item, opts)
	if not item then return end
	opts = opts or {}
	local mode = opts.mode or "drop"

	local idx = table.find(self.items, item)
	if idx then table.remove(self.items, idx) end

	-- restore what we changed (a part may have been deleted while we held it)
	for _, p in ipairs(item.parts) do
		local s = item.saved[p]
		if s and p.Parent then
			p.CanQuery = s.CanQuery
			if mode == "park" then
				p.Anchored   = true
				p.CanCollide = true
			else
				p.Anchored   = s.Anchored
				p.CanCollide = s.CanCollide
			end
			self.carriedSet[p] = nil
		end
	end

	if mode == "home" then
		for _, p in ipairs(item.parts) do
			local s = item.saved[p]
			if s and p.Parent then
				p.CFrame = s.CFrame
				p.AssemblyLinearVelocity  = Vector3.new()
				p.AssemblyAngularVelocity = Vector3.new()
			end
		end
	elseif mode == "throw" then
		local dir = opts.direction
		if dir and dir.Magnitude > 0 then dir = dir.Unit end
		local power = opts.power or Config.Throw.Power

		for _, p in ipairs(item.parts) do
			if p.Parent then
				p.Anchored = false  -- a thrown part is always loose, even if it was anchored before
			end
		end

		-- welded models are one rigid assembly (push the root), loose parts
		-- get their own push so they fly together
		local targets = item.welded and { item.root } or item.parts
		for _, p in ipairs(targets) do
			if not p.Parent then
				-- deleted while we were holding it — nothing to throw
			elseif Config.Throw.UseImpulse then
				local mass = math.max(p.AssemblyMass, 0.05)
				local impulse = (dir or Vector3.new(0, 1, 0)) * power * mass
				impulse = impulse + Vector3.new(0, power * Config.Throw.UpBias * mass, 0)
				pcall(function() p:ApplyImpulse(impulse) end)
			else
				p.AssemblyLinearVelocity = (dir or Vector3.new(0, 1, 0)) * power
			end
		end

		if item.root.Parent then
			item.root.AssemblyAngularVelocity = Vector3.new(
				math.random() - 0.5, math.random() - 0.5, math.random() - 0.5
			).Unit * Config.Throw.RandomSpin
			FX.Trail(item.root)
			if Config.Visuals.ThrowBurst then
				FX.Burst(item.root.Position, Config.Visuals.BurstColor, 12)
			end
		end
		FX.Sound("Throw")
	end

	FX.DetachCarryFX(item)
	self:ReleaseOwnership(item)
	if self.selected == item then self.selected = nil end
	if #self.items == 0 then FX.StopLoop() end

	item.saved = {}
	item.offsets = {}
	item.parts = {}
end

function Carrier:ThrowDirection()
	local cam = workspace.CurrentCamera
	return cam.CFrame.LookVector
end

function Carrier:ThrowSelected(power)
	local item = self.selected or self.items[#self.items]
	if not item then
		UI.Toast("Nothing selected to throw", UI.Colors.DIM)
		return
	end
	self:Release(item, { mode = "throw", direction = self:ThrowDirection(), power = power or Config.Throw.Power })
end

function Carrier:Burst(power)
	if #self.items == 0 then return end
	local dir = self:ThrowDirection()
	local list = {}
	for i = 1, #self.items do table.insert(list, self.items[i]) end
	for i, item in ipairs(list) do
		local d = dir
		local spread = Config.Throw.Spread * ((i % 5) - 2)
		d = (CFrame.new(Vector3.new()) * CFrame.Angles(0, spread, 0)):VectorToWorldSpace(d)
		self:Release(item, { mode = "throw", direction = d, power = power or Config.Throw.Burst })
	end
	UI.Toast("Burst — " .. #list .. " parts", UI.Colors.ACCENT)
end

function Carrier:Explode(power)
	if #self.items == 0 then return end
	local center = self.centerCF.Position
	local list = {}
	for i = 1, #self.items do table.insert(list, self.items[i]) end
	for _, item in ipairs(list) do
		local dir = (item.root.Position - center)
		if dir.Magnitude < 0.001 then dir = Vector3.new(0, 1, 0) end
		self:Release(item, { mode = "throw", direction = dir.Unit, power = power or Config.Throw.Explode })
	end
	UI.Toast("Explode — " .. #list .. " parts", UI.Colors.ACCENT)
end

function Carrier:DropAll()
	local n = #self.items
	if n == 0 then return end
	local list = {}
	for i = 1, #self.items do table.insert(list, self.items[i]) end
	for _, item in ipairs(list) do
		self:Release(item, { mode = "drop" })
	end
	FX.Sound("Drop")
	UI.Toast("Dropped " .. n .. " part" .. (n == 1 and "" or "s"), UI.Colors.DIM)
end

function Carrier:UndoAll()
	local n = #self.items
	if n == 0 then return end
	local list = {}
	for i = 1, #self.items do table.insert(list, self.items[i]) end
	for _, item in ipairs(list) do
		self:Release(item, { mode = "home" })
	end
	UI.Toast("Sent " .. n .. " part" .. (n == 1 and "" or "s") .. " home", UI.Colors.GOOD)
end

function Carrier:ParkSelected()
	local item = self.selected or self.items[#self.items]
	if not item then return end
	self:Release(item, { mode = "park" })
	UI.Toast("Parked in mid-air", UI.Colors.ACCENT2)
end

----------------------------------------------------------------------
--  charge (hold right mouse / R)
----------------------------------------------------------------------
function Carrier:BeginCharge()
	if #self.items == 0 then return end
	self.charging = true
	self.chargePower = 0
end

function Carrier:ReleaseCharge()
	if not self.charging then
		-- quick tap = instant throw at base power
		if #self.items > 0 then self:ThrowSelected(Config.Throw.Power) end
		return
	end
	self.charging = false
	local power = math.min(self.chargePower, Config.Throw.MaxPower)
	if power < Config.Throw.Power then power = Config.Throw.Power end
	self.chargePower = 0
	self:ThrowSelected(power)
end

----------------------------------------------------------------------
--  vacuum
----------------------------------------------------------------------
function Carrier:VacuumScan()
	local root = self:GetRootPart()
	if not root then return 0 end
	local r = Config.Vacuum.Radius

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { LocalPlayer.Character }
	params.MaxParts = 250

	local found = workspace:GetPartBoundsInBox(CFrame.new(root.Position), Vector3.new(r * 2, r * 2, r * 2), params)
	local center = root.Position
	table.sort(found, function(a, b)
		return (a.CFrame.Position - center).Magnitude < (b.CFrame.Position - center).Magnitude
	end)

	local got = 0
	for _, p in ipairs(found) do
		if got >= Config.Vacuum.PerTick then break end
		if #self.items >= Config.General.MaxCarried then break end
		if self:IsGrabbable(p) then
			local ok = self:Grab(p, true)
			if ok then got = got + 1 end
		end
	end
	return got
end

----------------------------------------------------------------------
--  formations & tuning
----------------------------------------------------------------------
function Carrier:CycleFormation(dir)
	local list = Config.Orbit.Formations
	local current = table.find(list, Config.Orbit.Formation) or 1
	local next = ((current - 1 + (dir or 1)) % #list) + 1
	Config.Orbit.Formation = list[next]
	for _, item in ipairs(self.items) do
		item.freezeOffset = nil
	end
	UI.Toast("Formation: " .. list[next], UI.Colors.ACCENT2)
	FX.Sound("Grab")
	return list[next]
end

function Carrier:SetFormation(name)
	for i, v in ipairs(Config.Orbit.Formations) do
		if v:lower() == tostring(name):lower() then
			Config.Orbit.Formation = v
			for _, item in ipairs(self.items) do item.freezeOffset = nil end
			UI.Toast("Formation: " .. v, UI.Colors.ACCENT2)
			return true
		end
	end
	return false
end

function Carrier:Tune(key, delta)
	local cfg = Config.Orbit
	if type(cfg[key]) ~= "number" then return end
	local adj = Config.Adjust
	local minKey, maxKey, stepKey = "Min" .. key, "Max" .. key, key .. "Step"
	local min = adj[minKey]
	local max = adj[maxKey]
	local new = cfg[key] + delta
	if min then new = math.max(min, new) end
	if max then new = math.min(max, new) end
	cfg[key] = new
	UI.FlashStat(key)
	return new
end

function Carrier:SetTuning(key, value)
	local cfg = Config.Orbit
	if type(cfg[key]) ~= "number" then return end
	local adj = Config.Adjust
	local min, max = adj["Min" .. key], adj["Max" .. key]
	if min then value = math.max(min, value) end
	if max then value = math.min(max, value) end
	cfg[key] = value
	UI.FlashStat(key)
	return value
end

function Carrier:ResetTuning()
	for k, v in pairs(self.defaults) do
		Config.Orbit[k] = v
	end
	for _, def in ipairs({ "Radius", "Height", "Speed", "Spin", "Tilt" }) do
		UI.FlashStat(def)
	end
	UI.Toast("Tuning reset", UI.Colors.GOOD)
end

function Carrier:SetPaused(on)
	if on == nil then
		self.paused = not self.paused     -- toggle
	else
		self.paused = on and true or false
	end
	UI.Toast(self.paused and "Orbit paused" or "Orbit resumed", UI.Colors.ACCENT2)
end

function Carrier:SetSlowMo(on)
	self.slowmo = on
end

function Carrier:ToggleGlow()
	self.glow = not self.glow
	Config.Visuals.Glow = self.glow
	for _, item in ipairs(self.items) do
		FX.SetGlow(item, self.glow)
	end
	UI.Toast(self.glow and "Glow on" or "Glow off", UI.Colors.ACCENT2)
end

----------------------------------------------------------------------
--  ownership (talks to OrbitGrabServer; silently ignored if absent)
----------------------------------------------------------------------
function Carrier:RequestOwnership(item)
	if not self.remotes or not self.remotes.Request then return end
	pcall(function() self.remotes.Request:FireServer(item.root, item.parts) end)
end

function Carrier:ReleaseOwnership(item)
	if not self.remotes or not self.remotes.Release then return end
	pcall(function() self.remotes.Release:FireServer(item.root, item.parts) end)
end

----------------------------------------------------------------------
--  per-frame
----------------------------------------------------------------------
function Carrier:HistoryAt(t)
	local h = self.history
	if #h == 0 then return nil end
	local p = self._histPtr or #h
	while p > 1 and h[p].t > t do
		p = p - 1
	end
	self._histPtr = p
	return h[p].cf
end

function Carrier:SlotCFrame(item, i, count)
	local cfg = Config.Orbit
	local center = self.centerCF
	local t = self.time + (i - 1) * cfg.Stagger
	local worldPos

	if cfg.Formation == "Follow" then
		local delay = math.min(i * cfg.FollowSpacing, self.historySpan * 0.9)
		local cf = self:HistoryAt(self.time - delay) or center
		local a = (i - 1) / math.max(count, 1) * TAU + self.time * cfg.Speed
		local r = cfg.Radius * 0.35
		worldPos = (cf * CFrame.new(math.cos(a) * r, cfg.Height * 0.5, -math.sin(a) * r - 1.5)).Position

	elseif cfg.Formation == "Freeze" then
		if not item.freezeOffset then
			item.freezeOffset = center:Inverse() * item.current
		end
		return center * item.freezeOffset

	else
		item.freezeOffset = nil
		local pos = Orbit.LocalPosition(cfg.Formation, i, count, t, cfg, item.seed)
		-- Tilt rotates the whole orbital plane around your right axis
		worldPos = (center * CFrame.Angles(cfg.Tilt, 0, 0) * CFrame.new(pos)).Position
	end

	local bob = math.sin(self.time * cfg.BobSpeed + item.seed * TAU) * cfg.Bob
	worldPos = worldPos + Vector3.new(0, bob, 0)

	return Orbit.Orientation(cfg.FaceMode, worldPos, center, cfg, self.time, item)
end

function Carrier:Update(dt)
	local root = self:GetRootPart()
	if not root then return end

	self.timeScale = self.paused and 0 or (self.slowmo and Config.Adjust.SlowMoScale or 1)
	self.time = self.time + dt * self.timeScale

	self.centerCF = root.CFrame
	self.centerVel = root.AssemblyLinearVelocity

	-- trail of where you've been (used by the Follow formation)
	table.insert(self.history, { t = self.time, cf = self.centerCF })
	if #self.history > 600 then
		for _ = 1, 100 do table.remove(self.history, 1) end
	end
	self._histPtr = #self.history

	-- charging
	if self.charging then
		self.chargePower = math.min(Config.Throw.MaxPower, self.chargePower + dt * Config.Throw.ChargeRate)
	end

	-- vacuum
	if self.vacuuming then
		self._vacuumAccum = self._vacuumAccum + dt
		if self._vacuumAccum >= Config.Vacuum.TickRate then
			self._vacuumAccum = 0
			self:VacuumScan()
		end
	end

	-- move everything
	local count = #self.items
	for i, item in ipairs(self.items) do
		item.centerVelocity = self.centerVel
		local target = self:SlotCFrame(item, i, count)
		item.blend = math.min(1, item.blend + dt / math.max(0.0001, Config.Orbit.GrabEase))
		local smoothing = Config.Orbit.Smoothing * (0.5 + 0.9 * item.blend)
		item.current = item.current:Lerp(target, 1 - math.exp(-smoothing * dt))
		for _, p in ipairs(item.parts) do
			if p.Parent then
				p.CFrame = item.current * item.offsets[p]
			end
		end
	end

	-- what are we aiming at?
	local result = self:Raycast()
	self.target = result
	if result then
		local ok = self:IsGrabbable(result.Instance)
		self.targetOk = ok
		self.targetName = ok and self:TargetLabel(result) or nil
		self.targetDistance = (result.Position - self.centerCF.Position).Magnitude
		FX.HighlightTarget(ok and result.Instance or nil)
	else
		self.targetOk = false
		self.targetName = nil
		self.targetDistance = 0
		FX.ClearTarget()
	end
end

function Carrier:Render(dt)
	UI.Update({
		count      = #self.items,
		max        = Config.General.MaxCarried,
		formation  = Config.Orbit.Formation,
		paused     = self.paused,
		slowmo     = self.slowmo,
		vacuum     = self.vacuuming,
		glow       = self.glow,
		charge     = (self.charging and (self.chargePower / Config.Throw.MaxPower)) or 0,
		power      = self.chargePower,
		targetName = self.targetName,
		distance   = self.targetDistance or 0,
		values = {
			Radius = Config.Orbit.Radius,
			Height = Config.Orbit.Height,
			Speed  = Config.Orbit.Speed,
			Spin   = Config.Orbit.Spin,
			Tilt   = Config.Orbit.Tilt,
			Reach  = Config.General.Reach,
		},
	})
end

function Carrier:GetState()
	return {
		count = #self.items,
		formation = Config.Orbit.Formation,
	}
end

----------------------------------------------------------------------
--  teardown
----------------------------------------------------------------------
function Carrier:Destroy()
	self:UndoAll()
	for _, c in ipairs(self.connections) do
		if c then c:Disconnect() end
	end
	if self.diedConn then self.diedConn:Disconnect() end
	self.connections = {}
	FX.ClearTarget()
	FX.StopLoop()
	UI.Destroy()
end

return Carrier
