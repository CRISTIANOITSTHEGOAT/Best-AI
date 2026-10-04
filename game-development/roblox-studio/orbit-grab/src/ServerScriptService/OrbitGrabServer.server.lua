--!nolint
--[=[
	ORBIT GRAB  —  OrbitGrabServer.server.lua
	====================================================================
	Place in  ServerScriptService.

	Two jobs, both boring and both necessary:

	1. Hand the client network ownership of whatever it grabs, so the
	   parts it moves actually replicate to everyone else in the server.
	   Without this, Orbit Grab works perfectly — for you only.

	2. Take that ownership back on release / on leave, and make sure a
	   player who disconnects mid-orbit doesn't leave the map full of
	   anchored, floating junk.

	Everything the client sends is treated as a *request* and validated
	here. Tune the SERVER block below for your game.
--]=]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

----------------------------------------------------------------------
--  SERVER SETTINGS  (deliberately separate from the client Config —
--  a client should never be able to talk the server into raising these)
----------------------------------------------------------------------
local SERVER = {
	MaxDistance      = 250,    -- how far a player may reach (server truth)
	MaxPartSize      = 120,    -- biggest axis allowed
	MaxPartsPerGrab  = 200,    -- parts in one Model
	MaxPartsPerPlayer= 120,    -- concurrent owned parts per player
	MaxMass          = 250000,
	RateLimitPerSec  = 60,     -- ownership requests per second per player
	RespectLocked    = true,   -- never take ownership of Locked parts
	RestoreOnLeave   = true,   -- unanchor + return ownership when someone leaves
	Debug            = false,
	-- AllowedUserIds = { 12345678 },   -- uncomment + fill to restrict to testers
}

----------------------------------------------------------------------
--  remotes
----------------------------------------------------------------------
local folder = Instance.new("Folder")
folder.Name  = "OrbitGrab_Remotes"
folder.Parent = ReplicatedStorage

local RequestOwnership = Instance.new("RemoteEvent")
RequestOwnership.Name   = "RequestOwnership"
RequestOwnership.Parent = folder

local ReleaseOwnership = Instance.new("RemoteEvent")
ReleaseOwnership.Name   = "ReleaseOwnership"
ReleaseOwnership.Parent = folder

----------------------------------------------------------------------
--  state
----------------------------------------------------------------------
local owned     = {}   -- [Player] = { [BasePart] = true }
local buckets   = {}   -- [Player] = { t, n }  rate limiting
local log       = SERVER.Debug and print or function() end

local function partCount(player)
	local set = owned[player]
	if not set then return 0 end
	local n = 0
	for _ in pairs(set) do n = n + 1 end
	return n
end

local function remember(player, part)
	local set = owned[player]
	if not set then
		set = {}
		owned[player] = set
	end
	set[part] = true
end

local function forget(player, part)
	local set = owned[player]
	if set then set[part] = nil end
end

local function rateOk(player)
	local now = os.clock()
	local b = buckets[player]
	if not b then
		buckets[player] = { t = now, n = 1 }
		return true
	end
	if now - b.t > 1 then
		b.t = now
		b.n = 1
		return true
	end
	b.n = b.n + 1
	return b.n <= SERVER.RateLimitPerSec
end

local function allowed(player)
	if not SERVER.AllowedUserIds then return true end
	for _, id in ipairs(SERVER.AllowedUserIds) do
		if player.UserId == id then return true end
	end
	return false
end

local function rootPosition(player)
	local char = player.Character
	if not char then return nil end
	local rp = char:FindFirstChild("HumanoidRootPart")
	return rp and rp.Position or nil
end

-- Reject anything that isn't a sane, nearby, non-essential part.
local function valid(player, part, origin)
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then return false end
	if part:IsA("Terrain") then return false end
	if SERVER.RespectLocked and part.Locked then return false end

	local size = part.Size
	if math.max(size.X, size.Y, size.Z) > SERVER.MaxPartSize then return false end
	if part.AssemblyMass > SERVER.MaxMass then return false end

	-- never let anyone grab another player
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player and other.Character and part:IsDescendantOf(other.Character) then
			return false
		end
	end

	if origin and (part.Position - origin).Magnitude > SERVER.MaxDistance then return false end
	return true
end

----------------------------------------------------------------------
--  handlers
----------------------------------------------------------------------
RequestOwnership.OnServerEvent:Connect(function(player, root, parts)
	if not allowed(player) then return end
	if not rateOk(player) then
		log("[OrbitGrab] rate limited " .. player.Name)
		return
	end

	local origin = rootPosition(player)
	if not origin then return end

	if partCount(player) >= SERVER.MaxPartsPerPlayer then return end
	if not valid(player, root, origin) then return end

	local targets = {}
	if typeof(parts) == "table" then
		for i = 1, math.min(#parts, SERVER.MaxPartsPerGrab) do
			local p = parts[i]
			if valid(player, p, origin) then
				table.insert(targets, p)
			end
		end
	else
		table.insert(targets, root)
	end
	if #targets == 0 then table.insert(targets, root) end

	for _, p in ipairs(targets) do
		if partCount(player) >= SERVER.MaxPartsPerPlayer then break end
		local ok, err = pcall(function()
			p:SetNetworkOwner(player)
		end)
		if ok then
			remember(player, p)
		elseif SERVER.Debug then
			warn("[OrbitGrab] ownership failed on " .. p.Name .. ": " .. tostring(err))
		end
	end
end)

ReleaseOwnership.OnServerEvent:Connect(function(player, root, parts)
	local set = owned[player]
	if not set then return end

	local targets = {}
	if typeof(parts) == "table" then
		for i = 1, math.min(#parts, SERVER.MaxPartsPerGrab) do
			table.insert(targets, parts[i])
		end
	end
	if #targets == 0 and typeof(root) == "Instance" then
		table.insert(targets, root)
	end

	for _, p in ipairs(targets) do
		if typeof(p) == "Instance" and p:IsA("BasePart") and set[p] then
			forget(player, p)
			pcall(function() p:SetNetworkOwner(nil) end)
		end
	end
end)

----------------------------------------------------------------------
--  cleanup
----------------------------------------------------------------------
local function releaseAll(player)
	local set = owned[player]
	if not set then return end
	for p in pairs(set) do
		if p and p.Parent then
			if SERVER.RestoreOnLeave then
				-- best effort: hand the world back its parts
				pcall(function()
					p.Anchored = false
					p.CanCollide = true
					p:SetNetworkOwner(nil)
				end)
			else
				pcall(function() p:SetNetworkOwner(nil) end)
			end
		end
		set[p] = nil
	end
	owned[player] = nil
	buckets[player] = nil
end

Players.PlayerRemoving:Connect(releaseAll)

-- Safety net: if a part ends up anchored with nobody owning it (crash,
-- teleport, exploit, Studio stop), quietly give it back to the world.
-- Runs once a minute and only touches things Orbit Grab is responsible for.
task.spawn(function()
	while true do
		task.wait(60)
		for player in pairs(owned) do
			if not player.Parent then
				releaseAll(player)
			end
		end
	end
end)

log("[OrbitGrab] server ready")
