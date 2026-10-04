--!nolint
--[=[
	ORBIT GRAB  —  Config.lua
	====================================================================
	Every knob, dial and slider of the system lives here.
	Nothing else in the codebase hard-codes a number you might want to
	change, so you can tune the whole feel of the tool from this file.

	Tip: in Studio, edit this file, re-run your place (or hot-reload with
	Rojo) and the changes apply immediately.
--]=]

local Config = {}

----------------------------------------------------------------------
--  GENERAL  ·  what can be picked up, and how far
----------------------------------------------------------------------
Config.General = {
	Enabled            = true,      -- master switch (toggle at runtime with the chat command `/orb toggle`)
	MaxCarried         = 60,        -- hard cap on how many parts orbit you at once
	Reach              = 150,       -- how far ahead you can grab (studs)
	MaxPartSize        = 80,        -- ignore parts whose biggest axis is larger than this
	MaxModelParts      = 150,       -- if a Model has more parts than this, only grab the clicked part
	MaxMass            = 100000,    -- ignore absurdly heavy assemblies
	GrabWholeModel     = true,      -- clicking one brick of a Model grabs the whole Model
	AllowAnchored      = true,      -- can you rip anchored parts out of the world? (yes — it's fun)
	AllowLocked        = false,     -- respect Part.Locked
	AllowNPCs          = false,     -- allow grabbing Models that contain a Humanoid
	OnlyInFolder       = nil,       -- e.g. "Grabbables" → only parts inside workspace.Grabbables can be grabbed
	IgnoreAttribute    = "OrbitGrabIgnore", -- set this attribute to true on a part to make it un-grabbable
	IgnoreNames        = { "Terrain" },
	AimMode            = "Mouse",   -- "Mouse" (aim under cursor) or "Center" (always aim at crosshair)
	DropOnDeath        = true,      -- drop everything when you respawn
	UndoOnDeath        = false,     -- ...or teleport everything back where you found it
	HighlightTarget    = true,      -- outline whatever you're aiming at
	ShowTargetName     = true,      -- floating label with the part's name + distance
}

----------------------------------------------------------------------
--  ORBIT  ·  how the parts move around you
----------------------------------------------------------------------
Config.Orbit = {
	Formation   = "Ring",     -- starting formation (see Config.Orbit.Formations)
	Formations  = {
		"Ring",              -- classic flat circle
		"Helix",             -- multiple stacked rings, each spinning a bit slower
		"Sphere",            -- Fibonacci sphere shell (evenly spaced, looks great)
		"Vortex",            -- rising spiral column that recycles from the bottom
		"Figure8",           -- Lissajous infinity ribbon
		"Tower",             -- a juggling stack right above your head
		"Galaxy",            -- spiral disk — outer parts orbit slower, like a real galaxy
		"Wave",              -- a sinuous snake line floating in front of you
		"Crown",             -- tilted halo above your head
		"Atom",              -- three tilted rings crossing like the classic atom symbol
		"Follow",            -- conga line: each part retraces exactly where you just walked
		"Freeze",            -- parts lock in place relative to you (no motion at all)
	},

	Radius      = 7,         -- orbit radius (studs)
	Height      = 1.5,       -- vertical offset from your HumanoidRootPart
	Speed       = 0.9,       -- orbit speed (radians/second-ish)
	Spin        = 1.2,       -- how fast each part rotates on its own axis
	Tilt        = -0.12,     -- tilts the whole orbit plane (radians)
	Bob         = 0.35,      -- vertical sine-wave bob (studs)
	BobSpeed    = 1.7,

	PerRing     = 8,         -- Helix: parts per ring
	RingGap     = 2.2,       -- Helix: vertical distance between rings
	StackStep   = 1.1,       -- Tower: vertical distance between parts
	VortexRise  = 7,         -- Vortex: height of the column
	FollowSpacing = 0.09,    -- Follow: seconds of "lag" between each part
	AtomRings   = 3,         -- Atom: how many crossing rings

	-- How each part is rotated while it orbits.
	--   "Spin"     → continuous rotation (uses Spin value)
	--   "Outward"  → always face away from you
	--   "Player"   → always stare at you (creepy, in a good way)
	--   "Forward"  → face the way you're facing
	--   "Velocity" → face the direction you're moving
	--   "Keep"     → preserve the rotation the part had when you grabbed it
	FaceMode    = "Spin",

	Smoothing   = 14,        -- how snappily parts chase their slot (higher = tighter, lower = floatier)
	GrabEase    = 0.5,       -- seconds for a freshly grabbed part to settle into orbit
	Stagger     = 0.06,      -- extra per-index angle so neighbours never spawn overlapped
}

----------------------------------------------------------------------
--  ADJUST  ·  keyboard / scroll-wheel tuning (min-max clamps)
----------------------------------------------------------------------
Config.Adjust = {
	RadiusStep = 0.75,  MinRadius = 1.5,  MaxRadius = 45,
	HeightStep = 0.5,   MinHeight = -8,   MaxHeight = 35,
	SpeedStep  = 0.1,   MinSpeed  = -5,   MaxSpeed  = 6,
	SpinStep   = 0.25,  MinSpin   = -10,  MaxSpin   = 10,
	TiltStep   = 0.05,  MinTilt   = -1.3, MaxTilt   = 1.3,
	WheelMultiplier = 1,
	SlowMoScale     = 0.25,   -- time scale while holding the SlowMo key
}

----------------------------------------------------------------------
--  THROW  ·  letting go, violently
----------------------------------------------------------------------
Config.Throw = {
	Power      = 95,     -- impulse for a normal (uncharged) throw
	ChargeRate = 150,    -- power gained per second while charging
	MaxPower   = 320,    -- ceiling for a fully charged throw
	UpBias     = 0.14,   -- slight upward arc so throws feel arced, not flat
	RandomSpin = 10,     -- random tumble added on release
	Spread     = 0.06,   -- cone spread for Burst (radians)
	Trail      = true,   -- attach a short-lived trail to thrown parts
	TrailLife  = 0.6,
	TrailColor = Color3.fromRGB(120, 200, 255),
	UseImpulse = true,   -- ApplyImpulse (feels weighty) instead of setting velocity directly
	Burst      = 95,     -- power used by Burst (T)
	Explode    = 110,    -- power used by Explode (V)
}

----------------------------------------------------------------------
--  VACUUM  ·  hold G to inhale everything nearby
----------------------------------------------------------------------
Config.Vacuum = {
	Enabled    = true,
	Radius     = 25,
	TickRate   = 0.06,   -- seconds between inhales
	PerTick    = 3,      -- parts inhaled per tick
	OnlyLoose  = true,   -- skip parts that are welded/anchored to something else
}

----------------------------------------------------------------------
--  VISUALS
----------------------------------------------------------------------
Config.Visuals = {
	HighlightColor     = Color3.fromRGB(120, 200, 255),
	HighlightFill      = 0.82,
	HighlightOutline   = 0.25,
	CarryHighlight     = true,   -- outline parts while you're carrying them
	CarryHighlightColor= Color3.fromRGB(255, 190, 90),
	Glow               = false,  -- attach a PointLight to carried parts (toggle with M)
	GlowColor          = Color3.fromRGB(255, 200, 120),
	GlowRange          = 9,
	GlowBrightness     = 1.2,
	GrabBurst          = true,   -- little particle puff when a part joins the orbit
	ThrowBurst         = true,
	BurstColor         = Color3.fromRGB(140, 215, 255),
	Crosshair          = true,
	CrosshairColor     = Color3.fromRGB(230, 245, 255),
	ToastTime          = 2.2,
	ToastEnabled       = true,
}

----------------------------------------------------------------------
--  SOUNDS  (paste any Roblox audio asset id; 0 = disabled)
----------------------------------------------------------------------
Config.Sounds = {
	Enabled = false,
	Volume  = 0.5,
	Grab    = 0,   -- e.g. 9118823106
	Throw   = 0,
	Drop    = 0,
	Error   = 0,
	Loop    = 0,   -- optional looping hum while carrying (stops when you drop everything)
}

----------------------------------------------------------------------
--  UI
----------------------------------------------------------------------
Config.UI = {
	Enabled        = true,
	ShowHints      = true,   -- bottom control bar (toggle with J)
	MobileButtons  = true,   -- on-screen buttons on touch devices
	Scale          = 1,
	ToastEnabled   = true,
	ShowStats      = true,
}

----------------------------------------------------------------------
--  CONTROLS
--  Each action is a list of KeyCodes / UserInputTypes. Add or remove
--  freely — the on-screen hint bar is generated from this table.
----------------------------------------------------------------------
Config.Keys = {
	Grab        = { Enum.UserInputType.MouseButton1, Enum.KeyCode.E, Enum.KeyCode.Q },
	Throw       = { Enum.UserInputType.MouseButton2, Enum.KeyCode.R },
	Burst       = { Enum.KeyCode.T },                 -- throw everything forward
	Explode     = { Enum.KeyCode.V },                 -- throw everything outward
	DropAll     = { Enum.KeyCode.Z },                 -- gently release everything
	Undo        = { Enum.KeyCode.Backspace },         -- teleport every part home
	Park        = { Enum.KeyCode.X },                 -- freeze the selected part in mid-air
	Vacuum      = { Enum.KeyCode.G },                 -- hold to inhale nearby parts
	CycleMode   = { Enum.KeyCode.C },
	Pause       = { Enum.KeyCode.F },                 -- freeze all orbital motion
	Glow        = { Enum.KeyCode.M },
	ToggleUI    = { Enum.KeyCode.H },
	ToggleHints = { Enum.KeyCode.J },
	SlowMo      = { Enum.KeyCode.LeftAlt },           -- hold for bullet-time orbits

	RadiusDown  = { Enum.KeyCode.LeftBracket },
	RadiusUp    = { Enum.KeyCode.RightBracket },
	HeightDown  = { Enum.KeyCode.Minus },
	HeightUp    = { Enum.KeyCode.Equals },
	SpeedDown   = { Enum.KeyCode.Semicolon },
	SpeedUp     = { Enum.KeyCode.Quote },
	SpinDown    = { Enum.KeyCode.Comma },
	SpinUp      = { Enum.KeyCode.Period },
	TiltDown    = { Enum.KeyCode.O },
	TiltUp      = { Enum.KeyCode.P },
	ResetTuning = { Enum.KeyCode.Backquote },         -- radius/height/speed/spin/tilt back to defaults
}

----------------------------------------------------------------------
--  CHAT COMMANDS   (`/orb help` in game)
----------------------------------------------------------------------
Config.Chat = {
	Enabled  = true,
	Prefixes = { "/orb", "!orb", ";orb" },
}

Config.Debug = false

return Config
