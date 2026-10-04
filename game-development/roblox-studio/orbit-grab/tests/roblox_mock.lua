--!nolint
--[=[
	ORBIT GRAB  —  tests/roblox_mock.lua
	====================================================================
	A miniature, deliberately incomplete stand-in for the Roblox engine.
	It exists so the system can be executed and smoke-tested outside of
	Studio (see tests/run.js — uses fengari, a Lua VM in JavaScript).

	It is NOT a Roblox emulator. It implements just enough of Vector3,
	CFrame, Instance, the services and the event model for the Orbit Grab
	code paths to run and for mistakes (nil indexes, bad arguments,
	typos) to surface as Lua errors.
--]=]

local Mock = {}

Mock.unknownKeys = {}   -- { "Instance.Whatever" = count } — review after a run
Mock.events      = {}   -- fired-event log
local unknowns   = Mock.unknownKeys

local function note(key)
	unknowns[key] = (unknowns[key] or 0) + 1
end

----------------------------------------------------------------------
--  math extras Roblox provides
----------------------------------------------------------------------
math.clamp = function(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

if not math.atan2 then
	math.atan2 = function(y, x) return math.atan(y, x) end
end

if not table.find then
	table.find = function(t, v)
		for i, x in ipairs(t) do
			if x == v then return i end
		end
		return nil
	end
end

----------------------------------------------------------------------
--  Vector3
----------------------------------------------------------------------
local Vector3 = {}
Vector3.__index = Vector3
Vector3.__name  = "Vector3"

function Vector3.new(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, Vector3)
end

function Vector3.__add(a, b)
	return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
function Vector3.__sub(a, b)
	return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
function Vector3.__mul(a, b)
	if type(a) == "number" then return Vector3.new(a * b.X, a * b.Y, a * b.Z) end
	if type(b) == "number" then return Vector3.new(a.X * b, a.Y * b, a.Z * b) end
	return Vector3.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
function Vector3.__div(a, b)
	if type(b) == "number" then return Vector3.new(a.X / b, a.Y / b, a.Z / b) end
	return Vector3.new(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
function Vector3.__unm(a)
	return Vector3.new(-a.X, -a.Y, -a.Z)
end
function Vector3.__eq(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
function Vector3.__tostring(a)
	return string.format("(%g, %g, %g)", a.X, a.Y, a.Z)
end

function Vector3.__index(t, k)
	if k == "Magnitude" then
		return math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z)
	elseif k == "Unit" then
		local m = math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z)
		if m < 1e-8 then return Vector3.new() end
		return Vector3.new(t.X / m, t.Y / m, t.Z / m)
	elseif k == "zero" then
		return Vector3.new()
	end
	return Vector3[k]
end

----------------------------------------------------------------------
--  CFrame  (position + 3x3 rotation matrix — good enough to catch bugs)
----------------------------------------------------------------------
local CFrame = {}
CFrame.__name = "CFrame"

local function ident()
	return { 1, 0, 0, 0, 1, 0, 0, 0, 1 }
end

local function matmul(a, b)
	local o = {}
	for r = 0, 2 do
		for c = 0, 2 do
			o[r * 3 + c + 1] = a[r * 3 + 1] * b[c + 1]
				+ a[r * 3 + 2] * b[3 + c + 1]
				+ a[r * 3 + 3] * b[6 + c + 1]
		end
	end
	return o
end

local function matvec(m, v)
	return Vector3.new(
		m[1] * v.X + m[2] * v.Y + m[3] * v.Z,
		m[4] * v.X + m[5] * v.Y + m[6] * v.Z,
		m[7] * v.X + m[8] * v.Y + m[9] * v.Z
	)
end

local function transpose(m)
	return { m[1], m[4], m[7], m[2], m[5], m[8], m[3], m[6], m[9] }
end

local function cfMake(p, m)
	local o = { _p = p or Vector3.new(), _m = m or ident() }
	return setmetatable(o, CFrame)
end

function CFrame.new(x, y, z)
	if type(x) == "table" and x.X ~= nil then
		return cfMake(Vector3.new(x.X, x.Y, x.Z), ident())
	end
	return cfMake(Vector3.new(x or 0, y or 0, z or 0), ident())
end

function CFrame.Angles(rx, ry, rz)
	rx, ry, rz = rx or 0, ry or 0, rz or 0
	local cx, sx = math.cos(rx), math.sin(rx)
	local cy, sy = math.cos(ry), math.sin(ry)
	local cz, sz = math.cos(rz), math.sin(rz)
	local rxM = { 1, 0, 0, 0, cx, -sx, 0, sx, cx }
	local ryM = { cy, 0, sy, 0, 1, 0, -sy, 0, cy }
	local rzM = { cz, -sz, 0, sz, cz, 0, 0, 0, 1 }
	return cfMake(Vector3.new(), matmul(matmul(rxM, ryM), rzM))
end

function CFrame.lookAt(eye, target)
	local fwd = (target - eye)
	if fwd.Magnitude < 1e-6 then fwd = Vector3.new(0, 0, -1) end
	fwd = fwd.Unit
	local up = Vector3.new(0, 1, 0)
	local right = Vector3.new(
		fwd.Y * up.Z - fwd.Z * up.Y,
		fwd.Z * up.X - fwd.X * up.Z,
		fwd.X * up.Y - fwd.Y * up.X
	)
	if right.Magnitude < 1e-6 then right = Vector3.new(1, 0, 0) end
	right = right.Unit
	local trueUp = Vector3.new(
		right.Y * fwd.Z - right.Z * fwd.Y,
		right.Z * fwd.X - right.X * fwd.Z,
		right.X * fwd.Y - right.Y * fwd.X
	)
	-- Roblox basis: column0 = right, column1 = up, column2 = -look
	return cfMake(eye, {
		right.X, trueUp.X, -fwd.X,
		right.Y, trueUp.Y, -fwd.Y,
		right.Z, trueUp.Z, -fwd.Z,
	})
end

function CFrame.__index(t, k)
	if k == "Position"   then return t._p end
	if k == "X"          then return t._p.X end
	if k == "Y"          then return t._p.Y end
	if k == "Z"          then return t._p.Z end
	if k == "LookVector" then return matvec(t._m, Vector3.new(0, 0, -1)) end
	if k == "RightVector"then return matvec(t._m, Vector3.new(1, 0, 0)) end
	if k == "UpVector"   then return matvec(t._m, Vector3.new(0, 1, 0)) end
	return CFrame[k]
end

function CFrame.__newindex(t, k, v)
	rawset(t, k, v)
end

function CFrame.__mul(a, b)
	if type(b) == "table" and b._m then
		return cfMake(a._p + matvec(a._m, b._p), matmul(a._m, b._m))
	end
	return a._p + matvec(a._m, b)
end

function CFrame.__add(a, b)
	-- CFrame + Vector3 == translated CFrame
	if type(b) == "table" and b._m then
		return cfMake(a._p + b._p, matmul(a._m, b._m))
	end
	return cfMake(a._p + b, a._m)
end

function CFrame.__sub(a, b)
	if type(b) == "table" and b._m then
		return cfMake(a._p - b._p, a._m)
	end
	return cfMake(a._p - b, a._m)
end

function CFrame.__eq(a, b)
	return a._p == b._p
end

function CFrame.__tostring(a)
	return string.format("CFrame(%s)", tostring(a._p))
end

function CFrame:Inverse()
	local mt = transpose(self._m)
	return cfMake(matvec(mt, -self._p), mt)
end

function CFrame:Lerp(other, alpha)
	local p = self._p + (other._p - self._p) * alpha
	local m = {}
	for i = 1, 9 do
		m[i] = self._m[i] + (other._m[i] - self._m[i]) * alpha
	end
	return cfMake(p, m)
end

function CFrame:VectorToWorldSpace(v)
	return matvec(self._m, v)
end

function CFrame:PointToWorldSpace(v)
	return self._p + matvec(self._m, v)
end

function CFrame:VectorToObjectSpace(v)
	return matvec(transpose(self._m), v)
end

function CFrame:ToObjectSpace(other)
	return cfMake(matvec(transpose(self._m), other._p - self._p), matmul(transpose(self._m), other._m))
end

function CFrame:ToWorldSpace(other)
	return cfMake(self._p + matvec(self._m, other._p), matmul(self._m, other._m))
end

----------------------------------------------------------------------
--  other value types
----------------------------------------------------------------------
local function struct(name, fields)
	local T = {}
	T.__name = name
	T.__index = T
	function T.new(...)
		local args = { ... }
		local o = {}
		for i, f in ipairs(fields) do o[f] = args[i] or 0 end
		if name == "UDim2" then
			o.X = { Scale = args[1] or 0, Offset = args[2] or 0 }
			o.Y = { Scale = args[3] or 0, Offset = args[4] or 0 }
		end
		return setmetatable(o, T)
	end
	setmetatable(T, { __call = function(_, ...) return T.new(...) end })
	return T
end

local Vector2 = struct("Vector2", { "X", "Y" })
local UDim    = struct("UDim", { "Scale", "Offset" })
local UDim2   = struct("UDim2", {})

local Color3 = {}
Color3.__name = "Color3"
function Color3.new(r, g, b) return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, Color3) end
function Color3.fromRGB(r, g, b) return Color3.new((r or 0) / 255, (g or 0) / 255, (b or 0) / 255) end
function Color3.fromHSV(h, s, v) return Color3.new(h or 0, s or 0, v or 0) end
setmetatable(Color3, { __call = function(_, r, g, b) return Color3.new(r, g, b) end })

local function seq(name)
	local T = {}
	T.__name = name
	function T.new(a, b)
		return setmetatable({ Keypoints = { a, b } }, T)
	end
	setmetatable(T, { __call = function(_, a, b) return T.new(a, b) end })
	return T
end
local ColorSequence  = seq("ColorSequence")
local NumberSequence = seq("NumberSequence")

local NumberSequenceKeypoint = {}
function NumberSequenceKeypoint.new(t, v, _) return { Time = t, Value = v } end

local NumberRange = {}
function NumberRange.new(a, b) return { Min = a, Max = b } end

local Ray = {}
function Ray.new(origin, dir) return setmetatable({ Origin = origin, Direction = dir }, Ray) end

----------------------------------------------------------------------
--  Enum  (cached so `==` comparisons behave)
----------------------------------------------------------------------
local Enum = {}
local enumCache = {}
local enumCounter = 0
setmetatable(Enum, {
	__index = function(t, enumType)
		local bucket = enumCache[enumType]
		if bucket then return bucket end
		bucket = setmetatable({}, {
			__index = function(b, item)
				local key = enumType .. "." .. item
				local existing = rawget(b, item)
				if existing then return existing end
				enumCounter = enumCounter + 1
				local obj = { Name = item, EnumType = enumType, Value = enumCounter }
				rawset(b, item, obj)
				return obj
			end,
		})
		enumCache[enumType] = bucket
		return bucket
	end,
})

----------------------------------------------------------------------
--  Instance
----------------------------------------------------------------------
local Inst = {}
Inst.__name = "Instance"

local CLASS_DEFAULTS = {
	BasePart = function(o)
		o.Anchored = false
		o.CanCollide = true
		o.CanQuery = true
		o.CanTouch = true
		o.Locked = false
		o.Size = Vector3.new(4, 1, 2)
		o.CFrame = CFrame.new()
		o.Transparency = 0
		o.Massless = false
		o.AssemblyLinearVelocity = Vector3.new()
		o.AssemblyAngularVelocity = Vector3.new()
		o.AssemblyMass = 1
	end,
	Camera = function(o)
		o.CFrame = CFrame.new(0, 5, 10)
		o.FieldOfView = 70
	end,
	Humanoid = function(o)
		o.Health = 100
		o.MaxHealth = 100
		o.WalkSpeed = 16
	end,
	ScreenGui = function(o)
		o.Enabled = true
	end,
	TextLabel = function(o)
		o.Text = ""
		o.TextSize = 14
	end,
	TextButton = function(o)
		o.Text = ""
		o.TextSize = 14
	end,
}

local IS_A = {
	Part          = { "BasePart", "PVInstance", "Instance" },
	MeshPart      = { "BasePart", "PVInstance", "Instance" },
	WedgePart     = { "BasePart", "PVInstance", "Instance" },
	CornerWedgePart = { "BasePart", "PVInstance", "Instance" },
	TrussPart     = { "BasePart", "PVInstance", "Instance" },
	SpawnLocation = { "BasePart", "PVInstance", "Instance" },
	Terrain       = { "BasePart", "PVInstance", "Instance" },
	Model         = { "Model", "PVInstance", "Instance" },
	Folder        = { "Folder", "Instance" },
	Camera        = { "Camera", "Instance" },
	Humanoid      = { "Humanoid", "Instance" },
	WeldConstraint= { "WeldConstraint", "JointInstance", "Instance" },
	Weld          = { "Weld", "JointInstance", "Instance" },
	Motor6D       = { "Motor6D", "JointInstance", "Instance" },
	Snap          = { "Snap", "JointInstance", "Instance" },
	ParticleEmitter = { "ParticleEmitter", "Instance" },
	Sound         = { "Sound", "Instance" },
	Attachment    = { "Attachment", "Instance" },
	Trail         = { "Trail", "Instance" },
	Highlight     = { "Highlight", "Instance" },
	PointLight    = { "PointLight", "Light", "Instance" },
}

-- Roblox events the system legitimately uses (keeps the "unknown keys"
-- report free of noise, so anything that shows up there is worth a look)
local KNOWN_EVENTS = {
	Died = true, Chatted = true, CharacterAdded = true, CharacterRemoving = true,
	PlayerAdded = true, PlayerRemoving = true, InputBegan = true, InputEnded = true,
	InputChanged = true, SendingMessage = true, OnServerEvent = true,
	OnClientEvent = true, Touched = true, TouchEnded = true, Heartbeat = true,
	RenderStepped = true, Stepped = true, DescendantAdded = true,
	AncestryChanged = true, Changed = true, MouseButton1Down = true,
	MouseButton1Up = true, MouseButton1Click = true, MouseLeave = true,
	MouseEnter = true, Activated = true, FocusLost = true, Triggered = true,
}

local Event = {}
Event.__name = "Event"
Event.__index = Event
function Event.new(owner, name)
	return setmetatable({ _owner = owner, _name = name, _handlers = {} }, Event)
end
function Event:Connect(fn)
	table.insert(self._handlers, fn)
	local conn = {
		Connected = true,
		Disconnect = function(c)
			c.Connected = false
			for i, h in ipairs(self._handlers) do
				if h == fn then table.remove(self._handlers, i) break end
			end
		end,
	}
	return conn
end
function Event:Wait()
	return nil
end
function Event:_fire(...)
	for _, h in ipairs(self._handlers) do
		h(...)
	end
end

function Mock.new(className)
	local o = {
		ClassName = className,
		Name = className,
		_Parent = nil,
		_children = {},
		_props = {},
		_events = {},
		_attrs = {},
		_destroyed = false,
	}
	local init = CLASS_DEFAULTS[className] or CLASS_DEFAULTS[IS_A[className] and "BasePart" or className]
	if init then init(o) end
	if IS_A[className] and CLASS_DEFAULTS.BasePart and className ~= "BasePart" then
		-- parts get part defaults
	end
	return setmetatable(o, Inst)
end

function Inst.__index(t, k)
	if Inst[k] then return Inst[k] end
	if k == "Parent" then return rawget(t, "_Parent") end
	if k == "Position" and t:IsA("BasePart") then
		return (rawget(t, "_props").CFrame or CFrame.new()).Position
	end
	local p = rawget(t, "_props")
	if p and p[k] ~= nil then return p[k] end

	-- child access (workspace.Part)
	local kids = rawget(t, "_children")
	for i = #kids, 1, -1 do
		if kids[i].Name == k then return kids[i] end
	end

	-- anything else becomes an event (Roblox-like); unknown names get logged
	if not KNOWN_EVENTS[k] then
		note(tostring(t.ClassName) .. "." .. tostring(k))
	end
	local ev = rawget(t, "_events")[k]
	if not ev then
		ev = Event.new(t, k)
		rawget(t, "_events")[k] = ev
	end
	return ev
end

function Inst.__newindex(t, k, v)
	if k == "Position" and t:IsA("BasePart") then
		local cf = rawget(t, "_props").CFrame or CFrame.new()
		rawget(t, "_props").CFrame = CFrame.new(v) * (cf - cf.Position)
		return
	end
	if k == "Parent" then
		local old = rawget(t, "_Parent")
		if old then
			local kids = rawget(old, "_children")
			for i, c in ipairs(kids) do
				if c == t then table.remove(kids, i) break end
			end
		end
		if v then
			rawset(t, "_Parent", v)
			table.insert(rawget(v, "_children"), t)
		else
			rawset(t, "_Parent", nil)
		end
		return
	end
	rawget(t, "_props")[k] = v
end

function Inst:Destroy()
	self._destroyed = true
	self.Parent = nil
end

function Inst:Clone()
	local copy = Mock.new(self.ClassName)
	copy.Name = self.Name
	for k, v in pairs(rawget(self, "_props")) do
		if type(v) ~= "table" or v.X == nil then copy._props[k] = v end
	end
	return copy
end

function Inst:GetChildren()
	local out = {}
	for _, c in ipairs(rawget(self, "_children")) do table.insert(out, c) end
	return out
end

function Inst:GetDescendants()
	local out = {}
	local function walk(node)
		for _, c in ipairs(node:GetChildren()) do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(self)
	return out
end

function Inst:FindFirstChild(name, _recursive)
	for _, c in ipairs(rawget(self, "_children")) do
		if c.Name == name then return c end
	end
	return nil
end

function Inst:FindFirstChildOfClass(cls)
	for _, c in ipairs(rawget(self, "_children")) do
		if c.ClassName == cls or c:IsA(cls) then return c end
	end
	return nil
end

function Inst:FindFirstAncestorOfClass(cls)
	local p = rawget(self, "_Parent")
	while p do
		if p.ClassName == cls or p:IsA(cls) then return p end
		p = rawget(p, "_Parent")
	end
	return nil
end

function Inst:WaitForChild(name, _timeout)
	local found = self:FindFirstChild(name)
	if found then return found end
	local child = Mock.new("Folder")   -- mock: never really yields
	child.Name = name
	child.Parent = self
	return child
end

function Inst:IsA(cls)
	if self.ClassName == cls then return true end
	local list = IS_A[self.ClassName]
	if not list then return false end
	for _, c in ipairs(list) do
		if c == cls then return true end
	end
	return false
end

function Inst:IsDescendantOf(ancestor)
	local p = rawget(self, "_Parent")
	while p do
		if p == ancestor then return true end
		p = rawget(p, "_Parent")
	end
	return false
end

function Inst:GetFullName()
	local parts, p = { self.Name }, rawget(self, "_Parent")
	while p do
		table.insert(parts, 1, p.Name)
		p = rawget(p, "_Parent")
	end
	return table.concat(parts, ".")
end

function Inst:GetAttribute(name) return rawget(self, "_attrs")[name] end
function Inst:SetAttribute(name, value) rawget(self, "_attrs")[name] = value end
function Inst:GetMass() return 1 end
function Inst:ApplyImpulse(_) end
function Inst:ApplyImpulseAtPosition(_, __) end
function Inst:FireServer(...)
	local ev = rawget(self, "_events").OnServerEvent
	if ev then ev:_fire(Mock.localPlayer, ...) end
end
function Inst:FireAllClients(...)
	local ev = rawget(self, "_events").OnClientEvent
	if ev then ev:_fire(...) end
end
function Inst:FireClient(_, _player, ...)
	local ev = rawget(self, "_events").OnClientEvent
	if ev then ev:_fire(...) end
end
function Inst:InvokeServer(...) return nil end

function Inst:SetNetworkOwner(owner)
	rawget(self, "_props").__networkOwner = owner or "server"
end
function Inst:GetNetworkOwner() return nil end
function Inst:Emit(_) end
function Inst:Play() end
function Inst:Stop() end
function Inst:ScreenPointToRay(_, __)
	return { Origin = self.CFrame.Position, Direction = self.CFrame.LookVector }
end
function Inst:ViewportPointToRay(_, __)
	return { Origin = self.CFrame.Position, Direction = self.CFrame.LookVector }
end
function Inst:ClearAllChildren() rawset(self, "_children", {}) end

----------------------------------------------------------------------
--  workspace physics queries (very approximate — enough for tests)
----------------------------------------------------------------------
local function aabbHit(origin, dir, part, maxDist)
	local size = part.Size
	local center = part.CFrame.Position
	local lo = center - size * 0.5
	local hi = center + size * 0.5
	local tmin, tmax = 0, maxDist
	for _, axis in ipairs({ "X", "Y", "Z" }) do
		local o, d = origin[axis], dir[axis]
		if math.abs(d) < 1e-8 then
			if o < lo[axis] or o > hi[axis] then return nil end
		else
			local t1 = (lo[axis] - o) / d
			local t2 = (hi[axis] - o) / d
			if t1 > t2 then t1, t2 = t2, t1 end
			tmin = math.max(tmin, t1)
			tmax = math.min(tmax, t2)
			if tmin > tmax then return nil end
		end
	end
	return tmin
end

local function excluded(part, params)
	if not params then return false end
	for _, inst in ipairs(params.FilterDescendantsInstances or {}) do
		if part == inst or part:IsDescendantOf(inst) then return true end
	end
	return false
end

----------------------------------------------------------------------
--  services
----------------------------------------------------------------------
local services = {}

local function service(name, className)
	if services[name] then return services[name] end
	local s = Mock.new(className or name)
	s.Name = name
	services[name] = s
	s.Parent = Mock.game
	return s
end

----------------------------------------------------------------------
--  install
----------------------------------------------------------------------
function Mock.install()
	local game = Mock.new("DataModel")
	game.Name = "game"
	Mock.game = game

	function game.GetService(_, name)
		return service(name)
	end
	game.GetService = function(_, name) return service(name) end

	local workspace = service("Workspace", "Workspace")
	game.Workspace = workspace

	function workspace.Raycast(_, origin, dir, params)
		local len = dir.Magnitude
		if len < 1e-6 then return nil end
		local unit = dir / len
		local best, bestT = nil, math.huge
		for _, part in ipairs(workspace:GetDescendants()) do
			if part:IsA("BasePart") and part.CanQuery ~= false and not excluded(part, params) then
				local t = aabbHit(origin, unit, part, len)
				if t and t < bestT then
					bestT, best = t, part
				end
			end
		end
		if not best then return nil end
		return {
			Instance = best,
			Position = origin + unit * bestT,
			Distance = bestT,
			Normal = Vector3.new(0, 1, 0),
			Material = Enum.Material.Plastic,
		}
	end

	function workspace.GetPartBoundsInBox(_, cf, size, params)
		local out = {}
		local lo = cf.Position - size * 0.5
		local hi = cf.Position + size * 0.5
		for _, part in ipairs(workspace:GetDescendants()) do
			if part:IsA("BasePart") and not excluded(part, params) then
				local p = part.CFrame.Position
				if p.X >= lo.X and p.X <= hi.X and p.Y >= lo.Y and p.Y <= hi.Y and p.Z >= lo.Z and p.Z <= hi.Z then
					table.insert(out, part)
				end
			end
		end
		return out
	end

	-- RunService
	local run = service("RunService")
	local renderSteps = {}
	function run.BindToRenderStep(_, name, _priority, fn)
		renderSteps[name] = fn
	end
	function run.UnbindFromRenderStep(_, name) renderSteps[name] = nil end
	function run.IsClient(_) return true end
	function run.IsServer(_) return false end
	Mock.step = function(dt)
		for _, fn in pairs(renderSteps) do fn(dt) end
	end

	-- UserInputService
	local uis = service("UserInputService")
	uis.TouchEnabled = false
	uis.KeyboardEnabled = true
	uis.MouseEnabled = true
	function uis.IsKeyDown(_, _code) return false end
	Mock.fireInput = function(kind, input, processed)
		local ev = rawget(uis, "_events")[kind]
		if ev then ev:_fire(input, processed) end
	end

	-- ContextActionService
	local cas = service("ContextActionService")
	local bound = {}
	function cas.BindActionAtPriority(_, name, fn, _createTouch, _priority, ...)
		bound[name] = fn
	end
	function cas.UnbindAction(_, name) bound[name] = nil end
	Mock.fireAction = function(name, state, input)
		local fn = bound[name]
		if fn then return fn(name, state, input or {}) end
	end

	-- Players
	local players = service("Players")
	function players.GetPlayers(_) return rawget(players, "_children") end
	function players.GetPlayerFromCharacter(_, _) return Mock.localPlayer end

	-- TweenService
	local tween = service("TweenService")
	function tween.Create(_, _inst, _info, _props)
		return { Play = function() end, Cancel = function() end }
	end

	-- Debris
	local debris = service("Debris")
	function debris.AddItem(_, inst, _life)
		if inst and inst.Parent then inst.Parent = nil end
	end

	-- TextChatService
	service("TextChatService")

	-- ReplicatedStorage / ServerScriptService / SoundService
	service("ReplicatedStorage")
	service("ServerScriptService")
	service("SoundService")
	service("StarterPlayer")

	------------------------------------------------------------------
	--  globals
	------------------------------------------------------------------
	_G.game      = game
	_G.workspace = workspace
	_G.Instance  = { new = function(className) return Mock.new(className) end }
	_G.Vector3   = setmetatable(Vector3, { __call = function(_, x, y, z) return Vector3.new(x, y, z) end })
	_G.CFrame    = setmetatable(CFrame, { __call = function(_, x, y, z) return CFrame.new(x, y, z) end })
	_G.Vector2   = Vector2
	_G.UDim      = UDim
	_G.UDim2     = UDim2
	_G.Color3    = Color3
	_G.ColorSequence = ColorSequence
	_G.NumberSequence = NumberSequence
	_G.NumberSequenceKeypoint = NumberSequenceKeypoint
	_G.NumberRange = NumberRange
	_G.Ray       = Ray
	_G.Enum      = Enum

	_G.RaycastParams = setmetatable({}, {
		__call = function()
			return setmetatable({
				FilterDescendantsInstances = {},
				FilterType = Enum.RaycastFilterType.Exclude,
				IgnoreWater = false,
			}, {})
		end,
	})
	RaycastParams.new = function() return RaycastParams() end

	_G.OverlapParams = setmetatable({}, {
		__call = function()
			return setmetatable({
				FilterDescendantsInstances = {},
				FilterType = Enum.RaycastFilterType.Exclude,
				MaxParts = 1000,
			}, {})
		end,
	})
	OverlapParams.new = function() return OverlapParams() end

	_G.TweenInfo = setmetatable({}, { __call = function() return {} end })
	TweenInfo.new = function() return {} end

	_G.task = {
		spawn = function(fn, ...)
			local args = { ... }
			local co = coroutine.create(function() fn(table.unpack(args)) end)
			local ok, err = coroutine.resume(co)
			if not ok and not tostring(err):find("cannot resume") then
				print("[mock] task.spawn error: " .. tostring(err))
			end
		end,
		delay = function(_t, fn, ...) end,
		wait  = function(_t) coroutine.yield() end,
		defer = function(fn, ...) fn(...) end,
	}

	_G.typeof = function(x)
		if type(x) == "table" then
			return (getmetatable(x) and getmetatable(x).__name) or x.ClassName or "table"
		end
		return type(x)
	end

	_G.warn  = function(...) print("[warn]", ...) end
	_G.print = print

	return Mock
end

----------------------------------------------------------------------
--  test helpers
----------------------------------------------------------------------
function Mock.makePlayer(name)
	local players = game:GetService("Players")
	local p = Mock.new("Player")
	p.Name = name or "LocalPlayer"
	p.UserId = 12345
	p.Parent = players
	function p.GetMouse(_)
		return Mock.mouse or { X = 0, Y = 0, Target = nil, Hit = CFrame.new() }
	end
	Mock.localPlayer = p
	game:GetService("Players").LocalPlayer = p
	return p
end

function Mock.makeCharacter(player)
	local char = Mock.new("Model")
	char.Name = player.Name
	char.PrimaryPart = nil

	local root = Mock.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = CFrame.new(0, 3, 0)
	root.Parent = char

	local hum = Mock.new("Humanoid")
	hum.Name = "Humanoid"
	hum.Parent = char

	char.PrimaryPart = root
	char.Parent = workspace
	player.Character = char
	return char
end

function Mock.makeCamera(cf)
	local cam = Mock.new("Camera")
	cam.Name = "Camera"
	cam.CFrame = cf or CFrame.lookAt(Vector3.new(0, 5, 12), Vector3.new(0, 2, 0))
	cam.Parent = workspace
	workspace.CurrentCamera = cam
	return cam
end

function Mock.fire(instance, eventName, ...)
	local ev = rawget(instance, "_events")[eventName]
	if ev then
		ev:_fire(...)
		return true
	end
	return false
end

return Mock
