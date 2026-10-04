--!nolint
--[=[
	ORBIT GRAB  —  OrbitGrabClient.client.lua
	====================================================================
	Place in  StarterPlayer ▸ StarterPlayerScripts.

	This is the wiring layer: keyboard, mouse wheel, right-click charging,
	mobile buttons, chat commands and the render loop. All of the actual
	behaviour lives in ReplicatedStorage ▸ OrbitGrab.

	Nothing in this file needs editing to tune the feel — use
	OrbitGrab ▸ Config.lua for that.
--]=]

local Players             = game:GetService("Players")
local UserInputService    = game:GetService("UserInputService")
local ContextActionService= game:GetService("ContextActionService")
local RunService          = game:GetService("RunService")
local TextChatService     = game:GetService("TextChatService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
if not player.Character then player.CharacterAdded:Wait() end

local OrbitGrab = require(ReplicatedStorage:WaitForChild("OrbitGrab"))
local Config    = OrbitGrab.Config
local UI        = OrbitGrab.UI

local carrier = OrbitGrab.Carrier.new()

-- Exposed on _G so you can poke at it from the Studio command bar, or drive
-- it from another script:   _G.OrbitGrabCarrier:Explode()
_G.OrbitGrab        = OrbitGrab
_G.OrbitGrabCarrier = carrier

----------------------------------------------------------------------
--  input helpers
----------------------------------------------------------------------
local function matches(action, input)
	local keys = Config.Keys[action]
	if not keys then return false end
	for _, k in ipairs(keys) do
		if input.KeyCode == k or input.UserInputType == k then
			return true
		end
	end
	return false
end

local function isRightMouse(input)
	return input.UserInputType == Enum.UserInputType.MouseButton2
end

local function down(code)
	return UserInputService:IsKeyDown(code)
end

local function shiftDown()
	return down(Enum.KeyCode.LeftShift) or down(Enum.KeyCode.RightShift)
end

local function ctrlDown()
	return down(Enum.KeyCode.LeftControl) or down(Enum.KeyCode.RightControl)
end

----------------------------------------------------------------------
--  keyboard / mouse
----------------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if not Config.General.Enabled then return end
	if isRightMouse(input) then return end   -- handled by the charge binding below

	if matches("Grab", input) then
		carrier:GrabAtCursor()

	elseif matches("Throw", input) then
		carrier:BeginCharge()

	elseif matches("Burst", input) then
		carrier:Burst()

	elseif matches("Explode", input) then
		carrier:Explode()

	elseif matches("DropAll", input) then
		carrier:DropAll()

	elseif matches("Undo", input) then
		carrier:UndoAll()

	elseif matches("Park", input) then
		carrier:ParkSelected()

	elseif matches("Vacuum", input) then
		carrier.vacuuming = true
		UI.Toast("Vacuum on", UI.Colors.ACCENT)

	elseif matches("CycleMode", input) then
		carrier:CycleFormation(shiftDown() and -1 or 1)

	elseif matches("Pause", input) then
		carrier:SetPaused()

	elseif matches("Glow", input) then
		carrier:ToggleGlow()

	elseif matches("ToggleUI", input) then
		UI.Toggle()

	elseif matches("ToggleHints", input) then
		UI.ToggleHints()

	elseif matches("SlowMo", input) then
		carrier:SetSlowMo(true)

	elseif matches("RadiusDown", input) then
		carrier:Tune("Radius", -Config.Adjust.RadiusStep)
	elseif matches("RadiusUp", input) then
		carrier:Tune("Radius", Config.Adjust.RadiusStep)

	elseif matches("HeightDown", input) then
		carrier:Tune("Height", -Config.Adjust.HeightStep)
	elseif matches("HeightUp", input) then
		carrier:Tune("Height", Config.Adjust.HeightStep)

	elseif matches("SpeedDown", input) then
		carrier:Tune("Speed", -Config.Adjust.SpeedStep)
	elseif matches("SpeedUp", input) then
		carrier:Tune("Speed", Config.Adjust.SpeedStep)

	elseif matches("SpinDown", input) then
		carrier:Tune("Spin", -Config.Adjust.SpinStep)
	elseif matches("SpinUp", input) then
		carrier:Tune("Spin", Config.Adjust.SpinStep)

	elseif matches("TiltDown", input) then
		carrier:Tune("Tilt", -Config.Adjust.TiltStep)
	elseif matches("TiltUp", input) then
		carrier:Tune("Tilt", Config.Adjust.TiltStep)

	elseif matches("ResetTuning", input) then
		carrier:ResetTuning()
	end
end)

UserInputService.InputEnded:Connect(function(input, processed)
	if isRightMouse(input) then return end

	if matches("Throw", input) then
		carrier:ReleaseCharge()
	elseif matches("Vacuum", input) then
		if carrier.vacuuming then
			carrier.vacuuming = false
			UI.Toast("Vacuum off", UI.Colors.DIM)
		end
	elseif matches("SlowMo", input) then
		carrier:SetSlowMo(false)
	end
end)

-- scroll wheel: radius (plain), height (⇧), speed (⌃)
UserInputService.InputChanged:Connect(function(input, processed)
	if processed then return end
	if input.UserInputType ~= Enum.UserInputType.MouseWheel then return end
	if not Config.General.Enabled then return end

	local dir = (input.Position.Z > 0 and 1 or -1) * Config.Adjust.WheelMultiplier
	if ctrlDown() then
		carrier:Tune("Speed", dir * Config.Adjust.SpeedStep)
	elseif shiftDown() then
		carrier:Tune("Height", dir * Config.Adjust.HeightStep)
	else
		carrier:Tune("Radius", dir * Config.Adjust.RadiusStep)
	end
end)

-- Hold right mouse to charge a throw.
-- Bound at high priority so Roblox's right-click context menu doesn't pop up.
ContextActionService:BindActionAtPriority("OrbitGrab_Charge", function(_, state, _)
	if state == Enum.UserInputState.Begin then
		carrier:BeginCharge()
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		carrier:ReleaseCharge()
	end
	return Enum.ContextActionResult.Sink
end, false, 3000, Enum.UserInputType.MouseButton2)

----------------------------------------------------------------------
--  chat commands   (/orb help)
----------------------------------------------------------------------
local lastCommand, lastCommandTime = nil, 0

local function toastLines(lines)
	for _, l in ipairs(lines) do
		UI.Toast(l, UI.Colors.DIM)
	end
end

local function runCommand(text)
	local lower = text:lower()
	local prefix
	for _, p in ipairs(Config.Chat.Prefixes) do
		if lower:sub(1, #p) == p:lower() then
			prefix = p
			break
		end
	end
	if not prefix then return false end

	-- guard against the same message arriving on two chat events
	local now = os.clock()
	if lower == lastCommand and (now - lastCommandTime) < 0.25 then return true end
	lastCommand, lastCommandTime = lower, now

	local args = {}
	for word in text:sub(#prefix + 1):gmatch("%S+") do
		table.insert(args, word)
	end
	local cmd = table.remove(args, 1)
	if not cmd or cmd == "" then cmd = "help" end
	cmd = cmd:lower()

	if cmd == "help" then
		toastLines({
			"/orb mode <name|next>   /orb radius <n>   /orb height <n>",
			"/orb speed <n>   /orb spin <n>   /orb tilt <n>   /orb reach <n>",
			"/orb burst   /orb explode   /orb drop   /orb undo   /orb park",
			"/orb max <n>   /orb pause   /orb glow   /orb reset   /orb toggle",
			"/orb ui   /orb hints   /orb count   /orb help",
		})
		return true
	end

	if cmd == "mode" or cmd == "formation" then
		local a = (args[1] or "next"):lower()
		if a == "next" then
			carrier:CycleFormation(1)
		elseif a == "prev" or a == "back" then
			carrier:CycleFormation(-1)
		elseif carrier:SetFormation(a) then
			-- handled
		else
			UI.Toast("Unknown formation: " .. a, UI.Colors.BAD)
		end
		return true
	end

	if cmd == "radius" or cmd == "height" or cmd == "speed" or cmd == "spin" or cmd == "tilt" then
		local key = cmd:sub(1, 1):upper() .. cmd:sub(2)
		local n = tonumber(args[1])
		if not n then
			UI.Toast(cmd .. " is " .. tostring(Config.Orbit[key]), UI.Colors.DIM)
		else
			UI.Toast(cmd .. " → " .. tostring(carrier:SetTuning(key, n)), UI.Colors.ACCENT)
		end
		return true
	end

	if cmd == "reach" then
		local n = tonumber(args[1])
		if n then
			Config.General.Reach = math.clamp(n, 5, 2000)
			UI.FlashStat("Reach")
			UI.Toast("Reach → " .. tostring(Config.General.Reach), UI.Colors.ACCENT)
		else
			UI.Toast("Reach is " .. tostring(Config.General.Reach), UI.Colors.DIM)
		end
		return true
	end

	if cmd == "max" then
		local n = tonumber(args[1])
		if n then
			Config.General.MaxCarried = math.max(1, math.floor(n))
			UI.Toast("Max carried → " .. tostring(Config.General.MaxCarried), UI.Colors.ACCENT)
		end
		return true
	end

	if cmd == "burst"   then carrier:Burst(tonumber(args[1]))   return true end
	if cmd == "explode" then carrier:Explode(tonumber(args[1])) return true end
	if cmd == "drop"    then carrier:DropAll()                  return true end
	if cmd == "undo"    then carrier:UndoAll()                  return true end
	if cmd == "park"    then carrier:ParkSelected()             return true end
	if cmd == "throw"   then carrier:ThrowSelected(tonumber(args[1])) return true end
	if cmd == "pause"   then carrier:SetPaused()                return true end
	if cmd == "glow"    then carrier:ToggleGlow()               return true end
	if cmd == "reset"   then carrier:ResetTuning()              return true end
	if cmd == "ui"      then UI.Toggle()                        return true end
	if cmd == "hints"   then UI.ToggleHints()                   return true end
	if cmd == "count"   then
		UI.Toast("Carrying " .. #carrier.items .. " / " .. Config.General.MaxCarried, UI.Colors.DIM)
		return true
	end
	if cmd == "toggle" then
		Config.General.Enabled = not Config.General.Enabled
		if not Config.General.Enabled then carrier:DropAll() end
		UI.Toast("Orbit Grab " .. (Config.General.Enabled and "enabled" or "disabled"),
			Config.General.Enabled and UI.Colors.GOOD or UI.Colors.BAD)
		return true
	end

	UI.Toast("Unknown command '/orb " .. cmd .. "' — try /orb help", UI.Colors.BAD)
	return true
end

if Config.Chat.Enabled then
	player.Chatted:Connect(runCommand)
	pcall(function()
		TextChatService.SendingMessage:Connect(function(message)
			runCommand(message.Text)
		end)
	end)
end

----------------------------------------------------------------------
--  render loop
----------------------------------------------------------------------
RunService:BindToRenderStep("OrbitGrab_Step", Enum.RenderPriority.Camera.Value + 1, function(dt)
	dt = math.min(dt, 1 / 20)      -- survive hitches without teleporting parts
	if Config.General.Enabled then
		carrier:Update(dt)
	end
	carrier:Render(dt)
end)

----------------------------------------------------------------------
UI.Toast("Orbit Grab ready — grab something", UI.Colors.ACCENT)
UI.Toast("Press J for the control list", UI.Colors.DIM)
