--!nolint
--[=[
	ORBIT GRAB  —  UI.lua
	====================================================================
	The whole interface is built in code — nothing to import, no .rbxmx,
	no plugin. Drop the module in and the HUD appears:

	  • top-left status panel  (count, formation, live tuning values)
	  • centre crosshair       (turns hot when you're aimed at something)
	  • charge bar             (right-click / hold R)
	  • bottom control hints   (toggle with J)
	  • toasts                 (little confirmations for every action)
	  • mobile buttons         (auto-shown on touch devices)
--]=]

local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")

local UI = {}

local Config      = nil
local gui         = nil
local refs        = {}
local statRows    = {}
local statFlash   = {}
local visible     = true
local hintsOn     = true
local toastHolder = nil
local chargeActive = false

local ACCENT  = Color3.fromRGB(120, 200, 255)
local ACCENT2 = Color3.fromRGB(255, 190, 90)
local GOOD    = Color3.fromRGB(140, 240, 170)
local BAD     = Color3.fromRGB(255, 120, 120)
local DIM     = Color3.fromRGB(160, 175, 195)

----------------------------------------------------------------------
--  tiny helpers
----------------------------------------------------------------------
local function mk(class, props, children)
	local o = Instance.new(class)
	if props then
		for k, v in pairs(props) do
			if k ~= "Parent" then
				o[k] = v
			end
		end
	end
	if children then
		for _, c in ipairs(children) do
			c.Parent = o
		end
	end
	if props and props.Parent then
		o.Parent = props.Parent
	end
	return o
end

local function corner(parent, r)
	return mk("UICorner", { CornerRadius = UDim.new(0, r or 8), Parent = parent })
end

local function stroke(parent, color, thickness, transparency)
	return mk("UIStroke", {
		Color = color or Color3.fromRGB(255, 255, 255),
		Thickness = thickness or 1,
		Transparency = transparency or 0.85,
		Parent = parent,
	})
end

local function panel(parent, size, pos, anchor, transparency)
	return mk("Frame", {
		Name = "Panel",
		Size = size,
		Position = pos,
		AnchorPoint = anchor or Vector2.new(0, 0),
		BackgroundColor3 = Color3.fromRGB(12, 16, 24),
		BackgroundTransparency = transparency or 0.35,
		BorderSizePixel = 0,
		Parent = parent,
	})
end

local function label(parent, text, size, pos, color, font, align)
	return mk("TextLabel", {
		Name = "Label",
		Size = size or UDim2.new(1, 0, 0, 16),
		Position = pos or UDim2.new(0, 0, 0, 0),
		BackgroundTransparency = 1,
		Text = text or "",
		TextColor3 = color or Color3.fromRGB(230, 238, 248),
		TextScaled = false,
		TextSize = 14,
		Font = font or Enum.Font.Gotham,
		TextXAlignment = align or Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		Parent = parent,
	})
end

----------------------------------------------------------------------
--  build: main status panel
----------------------------------------------------------------------
local STAT_DEFS = {
	{ key = "Radius", fmt = function(v) return string.format("%.2f", v) end },
	{ key = "Height", fmt = function(v) return string.format("%.2f", v) end },
	{ key = "Speed",  fmt = function(v) return string.format("%.2f", v) end },
	{ key = "Spin",   fmt = function(v) return string.format("%.2f", v) end },
	{ key = "Tilt",   fmt = function(v) return string.format("%.2f", v) end },
	{ key = "Reach",  fmt = function(v) return string.format("%d", v) end, src = "General" },
}

local function buildMain(parent)
	local p = panel(parent, UDim2.new(0, 268, 0, 0), UDim2.new(0, 14, 0, 14))
	p.AutomaticSize = Enum.AutomaticSize.Y
	corner(p, 10)
	stroke(p, ACCENT, 1, 0.75)
	mk("UIPadding", {
		PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10),
		PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), Parent = p,
	})
	mk("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6), Parent = p })

	refs.title = label(p, "ORBIT GRAB", UDim2.new(1, 0, 0, 20), nil, Color3.fromRGB(245, 250, 255), Enum.Font.GothamBold)
	refs.title.TextSize = 17
	mk("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(120, 200, 255), Color3.fromRGB(190, 150, 255)),
		Parent = refs.title,
	})

	refs.version = label(p, "v1.0  ·  H hides  ·  J hints", UDim2.new(1, 0, 0, 12), nil, DIM, Enum.Font.Gotham)
	refs.version.TextSize = 11

	mk("Frame", { Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = ACCENT, BackgroundTransparency = 0.75, BorderSizePixel = 0, Parent = p })

	-- carrying count
	local countRow = mk("Frame", { Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, Parent = p })
	label(countRow, "CARRYING", UDim2.new(0.5, 0, 1, 0), nil, DIM, Enum.Font.GothamSemibold).TextSize = 12
	refs.count = label(countRow, "0 / 0", UDim2.new(0.5, 0, 1, 0), UDim2.new(0.5, 0, 0, 0), Color3.fromRGB(245, 250, 255), Enum.Font.GothamBold, Enum.TextXAlignment.Right)
	refs.count.TextSize = 13

	-- formation
	local modeRow = mk("Frame", { Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, Parent = p })
	label(modeRow, "FORMATION", UDim2.new(0.5, 0, 1, 0), nil, DIM, Enum.Font.GothamSemibold).TextSize = 12
	refs.mode = label(modeRow, "Ring", UDim2.new(0.5, 0, 1, 0), UDim2.new(0.5, 0, 0, 0), ACCENT2, Enum.Font.GothamBold, Enum.TextXAlignment.Right)
	refs.mode.TextSize = 13

	-- live tuning grid
	local grid = mk("Frame", { Size = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 1, Parent = p })
	grid.AutomaticSize = Enum.AutomaticSize.Y
	mk("UIGridLayout", {
		CellSize = UDim2.new(0.5, -2, 0, 16),
		CellPadding = UDim2.new(0, 4, 0, 2),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	for _, def in ipairs(STAT_DEFS) do
		local cell = mk("Frame", { BackgroundTransparency = 1, Parent = grid })
		local l = label(cell, def.key:upper(), UDim2.new(0.62, 0, 1, 0), nil, DIM, Enum.Font.Gotham)
		l.TextSize = 11
		local v = label(cell, "-", UDim2.new(0.38, 0, 1, 0), UDim2.new(0.62, 0, 0, 0), Color3.fromRGB(235, 242, 250), Enum.Font.GothamSemibold, Enum.TextXAlignment.Right)
		v.TextSize = 12
		statRows[def.key] = v
	end

	refs.status = label(p, "", UDim2.new(1, 0, 0, 16), nil, ACCENT2, Enum.Font.GothamBold)
	refs.status.TextSize = 12

	return p
end

----------------------------------------------------------------------
--  build: hints
----------------------------------------------------------------------
local HINTS = {
	{ "LMB / E",  "Grab part" },          { "RMB / R", "Hold = charge throw" },
	{ "Wheel",    "Orbit radius" },       { "⇧ Wheel", "Orbit height" },
	{ "⌃ Wheel",  "Orbit speed" },        { "C",       "Next formation" },
	{ "T",        "Burst throw all" },    { "V",       "Explode all" },
	{ "Z",        "Drop all" },           { "Backspace","Undo / send home" },
	{ "X",        "Park selected" },      { "G",       "Hold = vacuum" },
	{ "F",        "Pause orbit" },        { "M",       "Glow" },
	{ "[  ]",     "Radius" },             { "−  =",    "Height" },
	{ ";  '",     "Speed" },              { ",  .",    "Spin" },
	{ "O  P",     "Tilt" },               { "Alt",     "Slow motion" },
	{ "H / J",    "Hide UI / hints" },    { "`",       "Reset tuning" },
}

local function buildHints(parent)
	local p = panel(parent, UDim2.new(0, 520, 0, 0), UDim2.new(0.5, 0, 1, -14), Vector2.new(0.5, 1), 0.45)
	p.AutomaticSize = Enum.AutomaticSize.Y
	corner(p, 10)
	stroke(p, Color3.fromRGB(255, 255, 255), 1, 0.9)
	mk("UIPadding", {
		PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
		PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = p,
	})
	local grid = mk("Frame", { Size = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 1, Parent = p })
	grid.AutomaticSize = Enum.AutomaticSize.Y
	mk("UIGridLayout", {
		CellSize = UDim2.new(0.5, -3, 0, 15),
		CellPadding = UDim2.new(0, 6, 0, 1),
		FillDirectionMaxCells = 2,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	for _, h in ipairs(HINTS) do
		local row = mk("Frame", { BackgroundTransparency = 1, Parent = grid })
		local k = label(row, h[1], UDim2.new(0.4, 0, 1, 0), nil, ACCENT, Enum.Font.Code)
		k.TextSize = 11
		local d = label(row, h[2], UDim2.new(0.6, 0, 1, 0), UDim2.new(0.4, 0, 0, 0), DIM, Enum.Font.Gotham)
		d.TextSize = 11
	end
	refs.hints = p
	return p
end

----------------------------------------------------------------------
--  build: crosshair + target label
----------------------------------------------------------------------
local function buildCrosshair(parent)
	local c = mk("Frame", {
		Name = "Crosshair",
		Size = UDim2.new(0, 26, 0, 26),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	refs.chRing = mk("Frame", {
		Size = UDim2.new(1, 0, 1, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		BackgroundColor3 = Config.Visuals.CrosshairColor,
		BackgroundTransparency = 0.75,
		BorderSizePixel = 0,
		Parent = c,
	})
	corner(refs.chRing, 999)
	refs.chDot = mk("Frame", {
		Size = UDim2.new(0, 4, 0, 4),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		BackgroundColor3 = Config.Visuals.CrosshairColor,
		BorderSizePixel = 0,
		Parent = c,
	})
	corner(refs.chDot, 999)

	refs.target = label(parent, "", UDim2.new(0, 320, 0, 18),
		UDim2.new(0.5, 0, 0.5, 26), Color3.fromRGB(235, 245, 255), Enum.Font.GothamSemibold, Enum.TextXAlignment.Center)
	refs.target.AnchorPoint = Vector2.new(0.5, 0)
	refs.target.TextSize = 13
	refs.target.TextStrokeTransparency = 0.6
	refs.target.Visible = false
	return c
end

----------------------------------------------------------------------
--  build: charge bar
----------------------------------------------------------------------
local function buildCharge(parent)
	local p = mk("Frame", {
		Name = "Charge",
		Size = UDim2.new(0, 260, 0, 12),
		Position = UDim2.new(0.5, 0, 1, -100),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = Color3.fromRGB(10, 14, 22),
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Visible = false,
		Parent = parent,
	})
	corner(p, 6)
	stroke(p, ACCENT, 1, 0.7)
	refs.chargeFill = mk("Frame", {
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = ACCENT,
		BorderSizePixel = 0,
		Parent = p,
	})
	corner(refs.chargeFill, 6)
	mk("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(120, 220, 255), Color3.fromRGB(255, 170, 80)),
		Parent = refs.chargeFill,
	})
	refs.chargeText = label(parent, "POWER", UDim2.new(0, 260, 0, 14),
		UDim2.new(0.5, 0, 1, -114), ACCENT, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
	refs.chargeText.AnchorPoint = Vector2.new(0.5, 1)
	refs.chargeText.TextSize = 12
	refs.chargeText.Visible = false
	refs.charge = p
	return p
end

----------------------------------------------------------------------
--  build: toasts
----------------------------------------------------------------------
local function buildToasts(parent)
	local holder = mk("Frame", {
		Name = "Toasts",
		Size = UDim2.new(0, 320, 0, 0),
		Position = UDim2.new(0.5, 0, 0, 14),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	mk("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 4),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Parent = holder,
	})
	toastHolder = holder
	return holder
end

----------------------------------------------------------------------
--  build: mobile buttons
----------------------------------------------------------------------
local function buildMobile(parent, handlers)
	local isTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	if not (Config.UI.MobileButtons and isTouch) then return end

	local p = mk("Frame", {
		Name = "Mobile",
		Size = UDim2.new(0, 210, 0, 118),
		Position = UDim2.new(1, -14, 1, -14),
		AnchorPoint = Vector2.new(1, 1),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	mk("UIGridLayout", {
		CellSize = UDim2.new(0, 100, 0, 52),
		CellPadding = UDim2.new(0, 10, 0, 10),
		Parent = p,
	})

	local buttons = {
		{ "GRAB",  ACCENT,  handlers.onGrab,  false },
		{ "THROW", ACCENT2, nil,              true  },
		{ "MODE",  GOOD,    handlers.onMode,  false },
		{ "DROP",  BAD,     handlers.onDrop,  false },
	}
	for _, b in ipairs(buttons) do
		local btn = mk("TextButton", {
			Text = b[1],
			TextColor3 = Color3.fromRGB(15, 20, 28),
			Font = Enum.Font.GothamBold,
			TextSize = 15,
			BackgroundColor3 = b[2],
			BackgroundTransparency = 0.15,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Parent = p,
		})
		corner(btn, 10)
		if b[4] then
			btn.MouseButton1Down:Connect(function() if handlers.onThrowStart then handlers.onThrowStart() end end)
			btn.MouseButton1Up:Connect(function() if handlers.onThrowEnd then handlers.onThrowEnd() end end)
			btn.MouseLeave:Connect(function() if handlers.onThrowEnd then handlers.onThrowEnd() end end)
		elseif b[3] then
			btn.MouseButton1Click:Connect(b[3])
		end
	end
	refs.mobile = p
end

----------------------------------------------------------------------
--  public API
----------------------------------------------------------------------
function UI.Init(config, handlers)
	Config = config
	handlers = handlers or {}

	local player = game:GetService("Players").LocalPlayer
	gui = mk("ScreenGui", {
		Name = "OrbitGrab",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 100,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})
	mk("UIScale", { Scale = Config.UI.Scale, Parent = gui })

	refs.main = buildMain(gui)
	buildCrosshair(gui)
	buildCharge(gui)
	buildHints(gui)
	buildToasts(gui)
	buildMobile(gui, handlers)

	refs.hints.Visible = Config.UI.ShowHints
	hintsOn = Config.UI.ShowHints
	visible = Config.UI.Enabled
	gui.Enabled = visible

	return UI
end

function UI.SetVisible(on)
	visible = on
	if gui then gui.Enabled = on end
end

function UI.IsVisible()
	return visible
end

function UI.Toggle()
	UI.SetVisible(not visible)
	return visible
end

function UI.ToggleHints()
	hintsOn = not hintsOn
	if refs.hints then refs.hints.Visible = hintsOn end
	return hintsOn
end

function UI.FlashStat(key)
	statFlash[key] = os.clock()
end

function UI.Toast(text, color)
	if not gui then return end
	if not (Config.UI.ToastEnabled and Config.Visuals.ToastEnabled) then return end
	local hold = mk("Frame", {
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		Parent = toastHolder,
	})
	local t = label(hold, text, UDim2.new(1, 0, 1, 0), nil, color or Color3.fromRGB(235, 245, 255), Enum.Font.GothamSemibold, Enum.TextXAlignment.Center)
	t.TextSize = 13
	t.TextStrokeTransparency = 0.55

	t.TextTransparency = 1
	TweenService:Create(t, TweenInfo.new(0.18), { TextTransparency = 0 }):Play()
	task.delay(Config.Visuals.ToastTime, function()
		if t.Parent then
			TweenService:Create(t, TweenInfo.new(0.35), { TextTransparency = 1 }):Play()
			task.wait(0.4)
			hold:Destroy()
		end
	end)

	-- keep the stack short
	local kids = toastHolder:GetChildren()
	local count = 0
	for i = #kids, 1, -1 do
		if kids[i]:IsA("Frame") then
			count = count + 1
			if count > 5 then kids[i]:Destroy() end
		end
	end
end

--[[
	UI.Update(state)
	state = {
		count, max, formation, paused, slowmo, vacuum,
		charge = 0..1 or nil, power = number,
		targetName = string|nil, distance = number,
		values = { Radius=..., Height=..., Speed=..., Spin=..., Tilt=..., Reach=... }
	}
]]
function UI.Update(state)
	if not gui or not gui.Enabled then return end

	refs.count.Text = string.format("%d / %d", state.count, state.max)
	refs.count.TextColor3 = (state.count >= state.max) and BAD or Color3.fromRGB(245, 250, 255)
	refs.mode.Text = state.formation

	local statuses = {}
	if state.paused then table.insert(statuses, "PAUSED") end
	if state.slowmo then table.insert(statuses, "SLOW-MO") end
	if state.vacuum then table.insert(statuses, "VACUUM") end
	if state.glow then table.insert(statuses, "GLOW") end
	refs.status.Text = (#statuses > 0) and ("● " .. table.concat(statuses, "  ● ")) or ""
	refs.status.TextColor3 = state.paused and BAD or ACCENT2
	refs.status.Visible = (#statuses > 0)

	local now = os.clock()
	for _, def in ipairs(STAT_DEFS) do
		local row = statRows[def.key]
		if row then
			local v = state.values and state.values[def.key]
			row.Text = (v ~= nil) and def.fmt(v) or "-"
			local hot = statFlash[def.key] and (now - statFlash[def.key] < 0.7)
			row.TextColor3 = hot and ACCENT or Color3.fromRGB(235, 242, 250)
		end
	end

	-- crosshair
	if Config.Visuals.Crosshair then
		local has = state.targetName ~= nil
		refs.chRing.Size = has and UDim2.new(1.45, 0, 1.45, 0) or UDim2.new(1, 0, 1, 0)
		refs.chRing.BackgroundTransparency = has and 0.45 or 0.75
		refs.chRing.BackgroundColor3 = has and ACCENT2 or Config.Visuals.CrosshairColor
		refs.chDot.BackgroundColor3 = has and ACCENT2 or Config.Visuals.CrosshairColor
		refs.target.Visible = has and Config.General.ShowTargetName
		if has then
			refs.target.Text = string.format("%s   ·   %d studs", state.targetName, math.floor(state.distance + 0.5))
		end
	else
		refs.target.Visible = false
	end

	-- charge bar
	if state.charge and state.charge > 0 then
		refs.charge.Visible = true
		refs.chargeText.Visible = true
		refs.chargeFill.Size = UDim2.new(math.clamp(state.charge, 0, 1), 0, 1, 0)
		refs.chargeText.Text = string.format("POWER  %d", math.floor(state.power + 0.5))
	else
		refs.charge.Visible = false
		refs.chargeText.Visible = false
	end
end

function UI.Destroy()
	if gui then
		gui:Destroy()
		gui = nil
		refs = {}
		statRows = {}
	end
end

UI.Colors = { ACCENT = ACCENT, ACCENT2 = ACCENT2, GOOD = GOOD, BAD = BAD, DIM = DIM }

return UI
