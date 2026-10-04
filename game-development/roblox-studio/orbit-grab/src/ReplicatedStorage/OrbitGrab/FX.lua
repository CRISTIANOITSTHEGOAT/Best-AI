--!nolint
--[=[
	ORBIT GRAB  —  FX.lua
	====================================================================
	All of the juice: target outlines, glow, particle puffs, throw trails
	and (optional) sound. Everything here is cosmetic and safe to delete
	if you want the system completely silent and invisible.
--]=]

local Debris      = game:GetService("Debris")
local SoundService = game:GetService("SoundService")

local FX = {}
local Config = nil

local hoverHighlight = nil
local carryFolder = nil      -- holds highlights / lights for carried parts
local loopSound = nil

function FX.Init(config)
	Config = config
	carryFolder = Instance.new("Folder")
	carryFolder.Name = "OrbitGrab_FX"
	carryFolder.Parent = workspace
	return FX
end

function FX.GetCarryFolder()
	return carryFolder
end

----------------------------------------------------------------------
--  TARGET OUTLINE
----------------------------------------------------------------------
function FX.HighlightTarget(adornee)
	if not Config or not Config.General.HighlightTarget then return end
	if not adornee then
		FX.ClearTarget()
		return
	end
	if not hoverHighlight then
		hoverHighlight = Instance.new("Highlight")
		hoverHighlight.Name = "OrbitGrab_Target"
		hoverHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		hoverHighlight.Parent = workspace
	end
	hoverHighlight.FillColor       = Config.Visuals.HighlightColor
	hoverHighlight.FillTransparency = Config.Visuals.HighlightFill
	hoverHighlight.OutlineColor     = Config.Visuals.HighlightColor
	hoverHighlight.OutlineTransparency = Config.Visuals.HighlightOutline
	hoverHighlight.Adornee = adornee
end

function FX.ClearTarget()
	if hoverHighlight then
		hoverHighlight.Adornee = nil
	end
end

----------------------------------------------------------------------
--  CARRIED-PART OUTLINE / GLOW
----------------------------------------------------------------------
function FX.AttachCarryFX(item)
	if not Config then return end
	if Config.Visuals.CarryHighlight then
		local h = Instance.new("Highlight")
		h.Name = "OrbitGrab_Carry"
		h.FillColor = Config.Visuals.CarryHighlightColor
		h.FillTransparency = 0.9
		h.OutlineColor = Config.Visuals.CarryHighlightColor
		h.OutlineTransparency = 0
		h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		h.Adornee = item.root
		h.Parent = carryFolder
		item.highlight = h
	end
	if Config.Visuals.Glow then
		FX.SetGlow(item, true)
	end
end

function FX.DetachCarryFX(item)
	if item.highlight then
		item.highlight:Destroy()
		item.highlight = nil
	end
	FX.SetGlow(item, false)
end

function FX.SetGlow(item, on)
	if on then
		if item.light then return end
		local l = Instance.new("PointLight")
		l.Name = "OrbitGrab_Glow"
		l.Color = Config.Visuals.GlowColor
		l.Range = Config.Visuals.GlowRange
		l.Brightness = Config.Visuals.GlowBrightness
		l.Shadows = false
		l.Parent = item.root
		item.light = l
	else
		if item.light then
			item.light:Destroy()
			item.light = nil
		end
	end
end

function FX.ToggleGlowAll(items, on)
	for _, item in ipairs(items) do
		FX.SetGlow(item, on)
	end
end

----------------------------------------------------------------------
--  PARTICLE PUFF
----------------------------------------------------------------------
function FX.Burst(position, color, count)
	if not Config then return end
	local p = Instance.new("Part")
	p.Name = "OrbitGrab_Puff"
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.CFrame = CFrame.new(position)
	p.Parent = workspace

	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(color or Config.Visuals.BurstColor)
	e.LightEmission = 0.6
	e.LightInfluence = 0.2
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.7),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Lifetime = NumberRange.new(0.25, 0.6)
	e.Speed = NumberRange.new(4, 11)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Rate = 0
	e.Parent = p
	e:Emit(count or 14)

	Debris:AddItem(p, 1.2)
end

----------------------------------------------------------------------
--  THROW TRAIL
----------------------------------------------------------------------
function FX.Trail(part, life)
	if not Config or not Config.Throw.Trail then return end
	local size = part.Size
	local half = math.max(size.X, size.Y, size.Z) * 0.5 + 0.2

	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, half, 0)
	a0.Parent = part
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -half, 0)
	a1.Parent = part

	local trail = Instance.new("Trail")
	trail.Name = "OrbitGrab_Trail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(Config.Throw.TrailColor)
	trail.Lifetime = life or Config.Throw.TrailLife
	trail.MinLength = 0.05
	trail.FaceCamera = true
	trail.LightEmission = 0.5
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	trail.Parent = part

	Debris:AddItem(a0, trail.Lifetime + 0.2)
	Debris:AddItem(a1, trail.Lifetime + 0.2)
	Debris:AddItem(trail, trail.Lifetime + 0.2)
end

----------------------------------------------------------------------
--  SOUND
----------------------------------------------------------------------
local function play(id)
	if not Config or not Config.Sounds.Enabled then return end
	if not id or id == 0 then return end
	local ok, err = pcall(function()
		local s = Instance.new("Sound")
		s.SoundId = "rbxassetid://" .. tostring(id)
		s.Volume = Config.Sounds.Volume
		s.RollOffMaxDistance = 120
		s.Parent = SoundService
		s:Play()
		Debris:AddItem(s, 3)
	end)
	if not ok and Config.Debug then
		warn("[OrbitGrab] sound failed: " .. tostring(err))
	end
end

function FX.Sound(kind)
	if not Config or not Config.Sounds.Enabled then return end
	play(Config.Sounds[kind])
end

function FX.StartLoop()
	if not Config or not Config.Sounds.Enabled then return end
	if loopSound or not Config.Sounds.Loop or Config.Sounds.Loop == 0 then return end
	local ok = pcall(function()
		loopSound = Instance.new("Sound")
		loopSound.SoundId = "rbxassetid://" .. tostring(Config.Sounds.Loop)
		loopSound.Volume = Config.Sounds.Volume * 0.6
		loopSound.Looped = true
		loopSound.Parent = SoundService
		loopSound:Play()
	end)
	if not ok then loopSound = nil end
end

function FX.StopLoop()
	if loopSound then
		loopSound:Stop()
		loopSound:Destroy()
		loopSound = nil
	end
end

return FX
