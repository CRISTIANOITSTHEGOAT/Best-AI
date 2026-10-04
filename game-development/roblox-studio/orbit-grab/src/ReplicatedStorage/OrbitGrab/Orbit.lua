--!nolint
--[=[
	ORBIT GRAB  —  Orbit.lua
	====================================================================
	Pure math. No Roblox instances, no state, no side effects — give it a
	formation name, an index, a count and a time, and it gives you back a
	local-space point (relative to your character).

	Local space convention:  X = right, Y = up, -Z = the way you're facing.

	Want a new formation? Add a name to Config.Orbit.Formations and a
	branch here. That's it — the rest of the system picks it up.
--]=]

local TAU = math.pi * 2
local PHI = math.pi * (3 - math.sqrt(5))   -- golden angle, for even sphere packing

local Orbit = {}

-- Rotate a vector around the X axis (used by the Atom rings).
local function rotX(v, a)
	local c, s = math.cos(a), math.sin(a)
	return Vector3.new(v.X, v.Y * c - v.Z * s, v.Y * s + v.Z * c)
end

local function clampCount(n)
	if n < 1 then return 1 end
	return n
end

--[[
	Orbit.LocalPosition(formation, index, count, time, cfg, seed)
	  → Vector3 localPosition, number extraYaw
]]
function Orbit.LocalPosition(formation, i, count, t, cfg, seed)
	local n = clampCount(count)
	local R = cfg.Radius
	local H = cfg.Height
	local speed = cfg.Speed
	local seed = seed or 0

	-- 0..1 position of this part in the swarm; -0.5..0.5 centred version
	local u = (i - 1) / n
	local uc = u - 0.5
	local phase = seed * TAU

	if formation == "Ring" then
		local a = u * TAU + t * speed + phase * 0.15
		return Vector3.new(math.cos(a) * R, H, math.sin(a) * R), 0

	elseif formation == "Helix" then
		local per = math.max(1, cfg.PerRing)
		local ring = math.floor((i - 1) / per)
		local rings = math.max(1, math.ceil(n / per))
		local a = ((i - 1) % per) / per * TAU + t * speed * (1 - ring * 0.07) + ring * 0.6 + phase * 0.1
		local r = R * (1 - ring * 0.055)
		local y = H + (ring - (rings - 1) / 2) * cfg.RingGap
		return Vector3.new(math.cos(a) * r, y, math.sin(a) * r), 0

	elseif formation == "Sphere" then
		local k = (i - 0.5) / n
		local y = 1 - 2 * k                                  -- 1 (top) .. -1 (bottom)
		local r = math.sqrt(math.max(0, 1 - y * y))
		local a = PHI * (i - 1) + t * speed * 0.6 + phase * 0.2
		return Vector3.new(math.cos(a) * r * R, H + y * R * 0.78, math.sin(a) * r * R), 0

	elseif formation == "Vortex" then
		local f = (u + t * speed * 0.14 + seed * 0.3) % 1      -- 0..1 climb, wraps around
		local a = u * TAU * 2 + t * speed + phase
		local y = f * cfg.VortexRise
		local r = R * (0.35 + 0.65 * (1 - f))
		return Vector3.new(math.cos(a) * r, H + y - cfg.VortexRise * 0.35, math.sin(a) * r), 0

	elseif formation == "Figure8" then
		local a = t * speed + u * TAU + phase * 0.1
		return Vector3.new(math.sin(a) * R, H + math.sin(a * 2) * R * 0.22, math.sin(a * 2) * R * 0.5), 0

	elseif formation == "Tower" then
		local a = (i - 1) * 0.55 + t * speed * 0.35 + phase
		local r = R * 0.22
		return Vector3.new(math.cos(a) * r, H + (i - 1) * cfg.StackStep, math.sin(a) * r), 0

	elseif formation == "Galaxy" then
		local r = R * (0.22 + 0.78 * u)
		local a = u * 5.0 + t * speed * (1.5 - u * 0.9) + phase * 0.2
		local y = math.sin(u * TAU + t * speed) * 0.45
		return Vector3.new(math.cos(a) * r, H + y, math.sin(a) * r), 0

	elseif formation == "Wave" then
		local spread = math.min(2.0, 24 / n)
		local x = uc * n * spread
		local a = (i - 1) * 0.7 + t * speed * 2
		return Vector3.new(x, H + math.sin(a) * 1.3, -R * 0.55 + math.cos(a) * 0.4), 0

	elseif formation == "Crown" then
		local a = u * TAU + t * speed * 0.7 + phase * 0.1
		local r = R * 0.85
		return Vector3.new(math.cos(a) * r, H + R * 0.45 + math.cos(a * 3) * 0.35, math.sin(a) * r), 0

	elseif formation == "Atom" then
		local rings = math.max(1, cfg.AtomRings)
		local ringIdx = (i - 1) % rings
		local inRing = math.floor((i - 1) / rings)
		local perRing = math.max(1, math.ceil(n / rings))
		local a = (inRing / perRing) * TAU + t * speed + phase * 0.1
		local v = Vector3.new(math.cos(a) * R, math.sin(a) * R, 0)
		v = rotX(v, (ringIdx / rings) * math.pi)
		return Vector3.new(v.X, H + v.Y, v.Z), 0
	end

	-- Fallback: flat ring
	local a = u * TAU + t * speed + phase * 0.15
	return Vector3.new(math.cos(a) * R, H, math.sin(a) * R), 0
end

--[=[
	Orbit.Orientation(mode, worldPos, centerCF, cfg, time, item)
	  → CFrame (position + rotation) for a part sitting at worldPos.
	`item` needs: .seed (0..1) and optionally .originalRot (CFrame rotation).
--]=]
function Orbit.Orientation(mode, worldPos, centerCF, cfg, t, item)
	local seed = item and item.seed or 0
	local spin = t * cfg.Spin + seed * TAU
	local tilt = cfg.Tilt * 0.35
	local centerPos = centerCF.Position

	if mode == "Outward" then
		local out = (worldPos - centerPos) * Vector3.new(1, 0, 1)
		if out.Magnitude < 0.001 then out = centerCF.LookVector end
		return CFrame.lookAt(worldPos, worldPos + out.Unit) * CFrame.Angles(0, 0, spin * 0.25)

	elseif mode == "Player" then
		return CFrame.lookAt(worldPos, centerPos)

	elseif mode == "Forward" then
		return CFrame.lookAt(worldPos, worldPos + centerCF.LookVector)

	elseif mode == "Velocity" then
		local vel = item and item.centerVelocity or Vector3.new()
		if vel.Magnitude < 1 then
			return CFrame.lookAt(worldPos, worldPos + centerCF.LookVector)
		end
		return CFrame.lookAt(worldPos, worldPos + vel.Unit)

	elseif mode == "Keep" then
		local base = item and item.originalRot
		if base then
			return CFrame.new(worldPos) * (base - base.Position) * CFrame.Angles(0, spin * 0.35, 0)
		end
		return CFrame.new(worldPos) * CFrame.Angles(tilt, spin, 0)
	end

	-- "Spin" (default): inherits your character's facing, plus its own tumble.
	-- (centerCF - centerCF.Position) is the rotation-only part of the CFrame.
	local rot = centerCF - centerCF.Position
	return CFrame.new(worldPos) * rot * CFrame.Angles(0, spin, 0) * CFrame.Angles(tilt, 0, tilt * 0.5)
end

-- Nice easing used for the "pop" as a part flies into its orbit slot.
function Orbit.EaseOutBack(x)
	local c1 = 1.70158
	local c3 = c1 + 1
	local p = x - 1
	return 1 + c3 * p * p * p + c1 * p * p
end

function Orbit.EaseOutCubic(x)
	local p = 1 - x
	return 1 - p * p * p
end

Orbit.TAU = TAU

return Orbit
