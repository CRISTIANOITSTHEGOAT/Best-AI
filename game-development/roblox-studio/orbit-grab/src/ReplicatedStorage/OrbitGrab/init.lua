--!nolint
--[=[
	ORBIT GRAB  —  init.lua
	====================================================================
	Public entry point. With Rojo this folder becomes a single ModuleScript:

		local OrbitGrab = require(ReplicatedStorage:WaitForChild("OrbitGrab"))
		local carrier   = OrbitGrab.Carrier.new()
--]=]

local Config  = require(script.Parent.Config)
local Orbit   = require(script.Parent.Orbit)
local FX      = require(script.Parent.FX)
local UI      = require(script.Parent.UI)
local Carrier = require(script.Parent.Carrier)

return {
	Version = "1.0.0",
	Config  = Config,
	Orbit   = Orbit,
	FX      = FX,
	UI      = UI,
	Carrier = Carrier,
	new     = function() return Carrier.new() end,
}
