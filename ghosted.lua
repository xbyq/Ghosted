--[[
	Ghosted Menu - universal executor script (PC + mobile)

	Tabs:   Move / Visuals / Players / Misc / Extra / Config
	Open:   RightShift (rebindable in Config) or tap the floating ghost
	Binds:  right-click any toggle (PC), press a key to bind it, Esc clears it
	Saves:  toggles, sliders, binds, options, accent color and menu key -> GhostedMenu_settings.json
	Reload: re-running the script cleanly unloads the previous copy first

	Bug fixes:
	  - mainFrame background was white (flash on open) → now dark
	  - menuOpacity slider had no effect on UIGradient frame → fixed
	  - Camera Aim Mode toggle initial state now matches code default (true)
	  - Toggle icon color now tracks accent changes
	  - Stats HUD ping now color-codes (green/yellow/red)
	  - Section labels get accent bar on the left

	New features:
	  - Animated tab indicator bar (slides under active tab)
	  - God Mode toggle (Misc tab)
	  - Teleport to Coords (Misc tab, XYZ TextBox popup)
	  - Copy Username button on player rows
	  - Team color dot on player rows
	  - Server uptime in Stats HUD
	  - Accent swatches show active ring
	  - Brick Players button on player rows
	  - Close button styled as ×
	  - NEW "Extra" tab: Bunny Hop, Air Walk, Spin, No Ragdoll, Anti-Fling,
	    Respawn Here, Auto Clicker, Camera Noclip, FPS Boost, Waypoints

	From earlier version:
	  - Fly: deprecated BodyVelocity/BodyGyro → LinearVelocity + AlignOrientation
	          with legacy fallback for old executors
	  - Speed: re-captures speedOrig after respawn so restore works correctly
	  - Anti-void: fixed inverted floor check (was saving while airborne)
	  - Players: added Fling button + fling power slider (Misc tab)
]]

if not game:IsLoaded() then game.Loaded:Wait() end

local Players        = game:GetService("Players")
local TweenService   = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService     = game:GetService("RunService")
local HttpService    = game:GetService("HttpService")
local Lighting       = game:GetService("Lighting")
local Stats          = game:GetService("Stats")
local TeleportService = game:GetService("TeleportService")

if not Players.LocalPlayer then Players:GetPropertyChangedSignal("LocalPlayer"):Wait() end
local player = Players.LocalPlayer

local env = (typeof(getgenv) == "function" and getgenv()) or _G
if env.GhostedMenuUnload then pcall(env.GhostedMenuUnload) end

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local kDefaultToggleKey = Enum.KeyCode.RightShift
local kMenuW            = 360
local kMenuH            = 560
local kTweenTime        = 0.35
local kSaveFile         = "GhostedMenu_settings.json"
local kDiscordLink      = "https://discord.gg/ghostedd"
local kDefaultFlySpeed  = 60
local kDefaultWalkSpeed = 50
local kDefaultJumpPower = 100
local kClickTpHeight    = 3.5
local kDefaultEspDist   = 2000
local kToggleBtnSize    = 64
local kEspBoxColor      = Color3.fromRGB(255, 255, 255)
local kEspNameColor     = Color3.fromRGB(255, 255, 255)
local kTracerColor      = Color3.fromRGB(110, 110, 255)
local kChamsFill        = Color3.fromRGB(255, 70, 90)
local kChamsOutline     = Color3.fromRGB(255, 255, 255)
local kDefaultFlingPower = 5000

local kRowBg      = Color3.fromRGB(28, 28, 36)
local kRowBgHover = Color3.fromRGB(36, 36, 48)
local kSwitchOff  = Color3.fromRGB(50, 50, 60)
local kTextDim    = Color3.fromRGB(140, 140, 165)

local themes = {
	{ name = "Ghost",   color = Color3.fromRGB(160, 150, 255) },
	{ name = "Indigo",  color = Color3.fromRGB(110, 110, 255) },
	{ name = "Crimson", color = Color3.fromRGB(255, 90, 110) },
	{ name = "Emerald", color = Color3.fromRGB(70, 220, 140) },
	{ name = "Amber",   color = Color3.fromRGB(255, 190, 70) },
	{ name = "Pink",    color = Color3.fromRGB(255, 120, 200) },
	{ name = "Cyan",    color = Color3.fromRGB(70, 200, 255) },
}

----------------------------------------------------------------
-- CONNECTION TRACKING
----------------------------------------------------------------
local conns = {}
local function track(c)
	conns[#conns + 1] = c
	return c
end
local function disconnect(c)
	if c then pcall(function() c:Disconnect() end) end
end

local alive = true
local cleanups = {}
local function onUnload(fn)
	cleanups[#cleanups + 1] = fn
end

----------------------------------------------------------------
-- SETTINGS
----------------------------------------------------------------
local settings = { toggles = {}, sliders = {}, binds = {}, opts = {}, accent = 1, menuKey = "RightShift", presets = {}, notes = "", places = {} }
local canFile = typeof(readfile) == "function" and typeof(writefile) == "function" and typeof(isfile) == "function"

if canFile then
	local ok, data = pcall(function()
		if isfile(kSaveFile) then
			return HttpService:JSONDecode(readfile(kSaveFile))
		end
		return nil
	end)
	if ok and type(data) == "table" then
		if type(data.toggles) == "table" then settings.toggles = data.toggles end
		if type(data.sliders) == "table" then settings.sliders = data.sliders end
		if type(data.accent)  == "number" then settings.accent  = data.accent  end
		if type(data.menuKey) == "string" then settings.menuKey = data.menuKey end
		if type(data.binds)   == "table" then settings.binds   = data.binds   end
		if type(data.opts)    == "table" then settings.opts    = data.opts    end
		if type(data.presets) == "table" then settings.presets = data.presets end
		if type(data.notes)   == "string" then settings.notes  = data.notes   end
		if type(data.places)  == "table" then settings.places  = data.places  end
	end
end

local opts = settings.opts
do
	local defaults = { splash = true, openOnLoad = true, notifs = true, showButton = true, sounds = false }
	for k, v in pairs(defaults) do
		if opts[k] == nil then opts[k] = v end
	end
end

local saveQueued = false
local function saveSettings()
	if not canFile or saveQueued then return end
	saveQueued = true
	task.delay(0.5, function()
		saveQueued = false
		pcall(function() writefile(kSaveFile, HttpService:JSONEncode(settings)) end)
	end)
end

local toggleKey = kDefaultToggleKey
do
	local ok, key = pcall(function() return Enum.KeyCode[settings.menuKey] end)
	if ok and key then toggleKey = key end
end

----------------------------------------------------------------
-- ACCENT THEME
----------------------------------------------------------------
local accent = (themes[settings.accent] or themes[1]).color
local accentTargets   = {}
local accentCallbacks = {}

local function bindAccent(inst, prop)
	inst[prop] = accent
	accentTargets[#accentTargets + 1] = { inst, prop }
end

local function setAccent(idx)
	local t = themes[idx]
	if not t then return end
	accent = t.color
	settings.accent = idx
	for _, e in ipairs(accentTargets) do pcall(function() e[1][e[2]] = accent end) end
	for _, cb in ipairs(accentCallbacks) do pcall(cb, accent) end
	saveSettings()
end

----------------------------------------------------------------
-- UI HELPERS
----------------------------------------------------------------
local function addCorner(inst, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = (r < 0) and UDim.new(1, 0) or UDim.new(0, r)
	c.Parent = inst
	return c
end

local function addStroke(inst, color, thickness, transparency)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness or 1
	s.Transparency = transparency or 0
	s.Parent = inst
	return s
end

local function getGuiParent()
	local ok, hui = pcall(function() return gethui and gethui() end)
	if ok and hui then return hui end
	local ok2, coreGui = pcall(function() return game:GetService("CoreGui") end)
	if ok2 and coreGui then
		local okTest = pcall(function()
			local test = Instance.new("Folder")
			test.Parent = coreGui
			test:Destroy()
		end)
		if okTest then return coreGui end
	end
	return player:WaitForChild("PlayerGui")
end

local guiParent = getGuiParent()
do
	local old = guiParent:FindFirstChild("GhostedMenu")
	if old then old:Destroy() end
	local oldChams = guiParent:FindFirstChild("GhostedChams")
	if oldChams then oldChams:Destroy() end
end

local function makeDraggable(handle, target, onTap)
	local dragging, moved = false, false
	local dragInput, dragStart, startPos

	track(handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			moved = false
			dragStart = input.Position
			startPos = target.Position
			local c
			c = input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
					if c then c:Disconnect() end
					if not moved and onTap then onTap() end
				end
			end)
		end
	end))

	track(handle.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			dragInput = input
		end
	end))

	track(UserInputService.InputChanged:Connect(function(input)
		if dragging and input == dragInput then
			local d = input.Position - dragStart
			if d.Magnitude > 6 then moved = true end
			local us = target:FindFirstChildOfClass("UIScale")
			local k = us and us.Scale or 1
			target.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + d.X / k,
				startPos.Y.Scale, startPos.Y.Offset + d.Y / k
			)
		end
	end))
end

----------------------------------------------------------------
-- GHOST ICON (pixel art, same data as original)
----------------------------------------------------------------
local kGhostData = "e51,e51,e51,e51,e51,e51,e27k12e12,e24k4w10k3e10,e23k2w16k2e8,e21k2w19k3e6,e19k2w23k2e5,e18k2w25k3e3,e17k2w28k1e3,e16k2w29k2e2,e15k2w31k1e2,e15k1w32k2e1,e15k1w33k1e1,e14k2w9k5w3k1w3k1w2k5w4k1e1,e14k1w10k5w3k5w2k5w4k1e1,e14k1w18k1w3k1w11k1e1,e13k2w34k1e1,e13k1w35k1e1,e13k1w35k1e1,e12k2w35k1e1,e12k1w36k1e1,e12k1w36k1e1,e11k2w36k1e1,e11k1w37k1e1,e11k1w37k1e1,e10k2w36k2e1,e10k1w37k1e2,e9k2w37k1e2,e9k1w38k1e2,e8k1w38k2e2,e8k1w38k1e3,e7k1w39k1e3,e6k2w39k1e3,e6k1w39k1e4,e6k1w39k1e4,e5k1w40k1e4,e4k2w8k3w29k1e4,e4k1w8k2g1k1w28k1e5,e3k2w6k3g2k1w27k2e5,e3k1w5k3g4k1w27k1e6,e3k1w3k4g5k1w26k2e6,e3k4e3k2g3k1w27k1e7,e11k1g3k1w13k5w9k1e7,e11k1g3k1w12k2g2k2w8k2e7,e12k4w11k2g2k3w8k1e8,e15k1w10k1g3k2e2k1w6k2e8,e15k1w8k2g3k2e3k1w6k1e9,e15k2w4k4g3k2e4k1w5k2e9,e16k6e2k2g1k2e5k1w4k2e10,e25k2e7k2w2k2e11,e35k4e12,e51,e51,e51/e51,e51,e51,e51,e51,e27k11e13,e24k3w10k4e10,e22k3w15k3e8,e20k3w19k3e6,e19k2w23k2e5,e18k2w25k2e4,e17k2w27k2e3,e16k2w29k1e3,e15k2w30k2e2,e15k1w32k2e1,e15k1w33k1e1,e14k2w9k5w3k1w3k1w2k5w4k1e1,e14k1w10k5w3k5w2k5w4k1e1,e14k1w18k1w3k1w11k1e1,e14k1w34k1e1,e14k1w34k1e1,e14k1w34k1e1,e13k2w34k1e1,e13k1w35k1e1,e13k1w35k1e1,e12k2w35k1e1,e12k1w36k1e1,e11k2w36k1e1,e11k1w37k1e1,e10k2w36k1e2,e10k1w37k1e2,e9k1w38k1e2,e8k2w38k1e2,e7k2w38k1e3,e6k2w39k1e3,e6k1w40k1e3,e5k1w40k2e3,e4k2w40k1e4,e3k2w5k2w34k1e4,e2k2w3k3e1k2w33k1e4,e2k1w2k3e4k2w31k2e4,e1k1w2k2e5k1g1k1w31k1e5,e1k1w1k2e6k1g1k1w30k2e5,e2k2e7k1g1k1w30k1e6,e11k1g1k1w12k5w12k2e6,e11k1g1k1w10k3g3k2w11k1e7,e11k3w9k2g6k2w10k1e7,e11k2w10k2g7k1w9k1e8,e12k1w9k1e1k1g6k2w8k2e8,e12k2w7k2e1k2g5k2w8k1e9,e13k2w4k3e3k1g4k1e1k1w7k2e9,e14k6e6k2g1k2e1k2w5k3e9,e27k3e3k1w4k2e11,e33k6e12,e51,e51,e51,e51/e51,e51,e51,e51,e27k11e13,e24k4w9k4e10,e22k3w15k3e8,e21k2w19k3e6,e20k2w22k2e5,e18k2w25k2e4,e17k2w27k2e3,e16k2w29k2e2,e16k1w31k1e2,e15k2w31k2e1,e15k1w33k1e1,e15k1w9k5w3k1w3k1w2k5w4k1e1,e15k1w9k5w3k5w2k5w4k1e1,e14k2w17k1w3k1w11k1e1,e14k1w34k1e1,e14k1w34k1e1,e14k1w34k1e1,e13k2w34k1e1,e13k1w35k1e1,e13k1w35k1e1,e12k1w36k1e1,e12k1w36k1e1,e11k1w37k1e1,e11k1w37k1e1,e10k1w37k1e2,e9k2w37k1e2,e9k1w38k1e2,e8k2w38k1e2,e8k1w38k1e3,e7k1w39k1e3,e6k2w38k1e4,e6k1w39k1e4,e5k2w39k1e4,e4k2g1k4w34k1e5,e4k3g3k2w33k1e5,e3k3g2k2e1k1w33k1e5,e3k2g2k2e2k1w32k1e6,e2k2g2k2e3k1w32k1e6,e2k1g1k3e4k1w31k2e6,e2k3e6k1w13k6w12k1e7,e11k1w11k2e1k1g2k2w12k1e7,e10k1w11k2e2k1g3k1w11k2e7,e10k1w10k2e3k1g3k1w10k1e9,e10k1w9k2e4k1g3k1w9k2e9,e10k2w7k2e5k1g3k2w8k1e10,e11k2w4k2e7k1g3k2w7k2e10,e12k6e8k1g2k3w6k2e11,e27k3e1k2w3k3e12,e32k5e14,e51,e51,e51,e51,e51/e51,e51,e32k4e15,e26k6w3k5e11,e23k4w12k3e9,e21k3w17k2e8,e20k2w21k2e6,e18k2w24k2e5,e17k2w26k2e4,e17k1w28k2e3,e16k1w30k1e3,e15k2w30k2e2,e15k1w32k2e1,e15k1w33k1e1,e15k1w9k5w3k1w3k1w2k5w4k1e1,e15k1w9k5w3k5w2k5w4k1e1,e14k1w18k1w3k1w11k2,e14k1w35k1,e14k1w35k1,e13k2w35k1,e13k1w36k1,e13k1w36k1,e12k1w37k1,e12k1w36k2,e12k1w36k1e1,e11k1w37k1e1,e11k1w37k1e1,e10k1w38k1e1,e9k2w37k2e1,e9k1w38k1e2,e8k1w38k2e2,e7k2w38k1e3,e7k1w39k1e3,e6k2w38k2e3,e6k1w39k1e4,e5k2w39k1e4,e4k6w35k1e5,e4k1g4k1w35k1e5,e3k1g5k1w35k1e5,e3k1g4k2w34k1e6,e2k1g4k3w34k1e6,e2k1g2k3e1k1w15k3w16k1e6,e2k4e3k1w14k2e1k2w14k1e7,e9k1w13k2e3k1w14k1e7,e9k1w12k2e4k1w13k2e7,e9k1w10k3e5k1w12k1e9,e10k1w8k3e6k1w12k1e9,e10k2w4k3g1k2e6k1w10k2e10,e11k9e8k1w10k1e11,e28k2w8k1e12,e28k3w5k2e13,e30k7e14,e51,e51,e51,e51,e51,e51/e51,e51,e51,e27k13e11,e23k5w11k2e10,e22k2w17k2e8,e20k3w19k3e6,e19k2w23k2e5,e18k2w25k2e4,e17k2w27k2e3,e16k2w29k1e3,e16k1w31k1e2,e15k1w32k2e1,e15k1w9k5w3k1w3k1w2k5w4k1e1,e14k2w9k5w3k5w2k5w4k1e1,e14k1w18k1w3k1w11k2,e14k1w35k1,e14k1w35k1,e14k1w35k1,e13k1w36k1,e13k1w36k1,e13k1w36k1,e12k2w36k1,e12k1w37k1,e11k2w36k1e1,e11k1w37k1e1,e10k1w38k1e1,e10k1w37k2e1,e9k1w38k1e2,e8k2w37k2e2,e8k1w38k1e3,e7k1w38k1e4,e6k2w38k1e4,e6k1w39k1e4,e5k3w38k1e4,e5k1g1k1w37k1e5,e4k1g3k1w36k1e5,e3k2g4k1w35k1e5,e3k1g4k2w34k1e6,e3k1g3k2w35k1e6,e2k2g2k3w34k2e6,e2k6w16k4w15k1e7,e3k2e2k1w14k3e2k1w15k1e7,e7k1w12k3g1k1e2k1w15k1e7,e7k1w11k2g2k2e2k1w12k1w1k2e7,e7k2w8k2g4k1e3k1w11k1g1k2e8,e8k2w5k3g4k2e3k1w10k2g1k2e8,e9k7e2k1g2k2e4k1w10k1g2k1e9,e18k4e5k2w8k2g1k2e9,e28k2w6k2g1k2e10,e29k1w5k5e11,e30k9e12,e51,e51,e51,e51,e51,e51/e51,e51,e51,e29k8e14,e26k4w6k4e11,e24k3w12k3e9,e22k2w17k3e7,e20k2w21k2e6,e19k2w23k2e5,e17k2w26k2e4,e16k2w28k1e4,e16k1w29k2e3,e15k2w30k1e3,e15k1w31k2e2,e14k1w10k5w3k1w3k1w2k5w3k1e2,e14k1w10k5w3k5w2k5w3k2e1,e14k1w18k1w3k1w11k1e1,e14k1w34k1e1,e14k1w34k1e1,e13k1w35k1e1,e13k1w36k1,e13k1w36k1,e12k2w36k1,e12k1w36k2,e12k1w36k1e1,e11k1w37k1e1,e11k1w37k1e1,e10k1w38k1e1,e9k2w37k1e2,e9k1w37k2e2,e8k1w38k1e3,e7k2w37k2e3,e7k1w38k1e4,e6k1w39k1e4,e5k1w40k1e4,e5k2w39k1e4,e5k1g1k1w37k1e5,e4k2g1k1w37k1e5,e4k1g3k1w36k1e5,e3k1g4k1w36k1e5,e3k1g3k1w36k1e6,e2k2g2k2w14k3w19k1e6,e2k1g3k1w13k3g2k1w17k1e7,e2k5w11k3g5k1w16k1e7,e6k1w10k2g7k1w16k1e7,e5k2w8k4g6k2w11k3w2k1e7,e5k2w7k2e2k1g5k3w9k2g2k4e7,e6k2w3k3e4k1g4k2e1k1w9k1g4k2e8,e8k4e6k2g2k2e2k1w8k2g4k2e8,e19k3e4k1w7k3g4k1e9,e27k1w5k2e1k1g3k2e9,e27k2w2k3e2k1g2k2e10,e28k4e4k4e11,e51,e51,e51,e51,e51/e51,e51,e51,e51,e30k4e17,e27k4w2k6e12,e23k4w11k3e10,e21k3w16k2e9,e19k3w20k2e7,e18k2w23k2e6,e17k2w25k2e5,e16k2w27k2e4,e15k2w29k1e4,e15k1w30k2e3,e15k1w9k5w3k1w3k1w2k5w2k2e2,e14k1w10k5w3k5w2k5w3k1e2,e14k1w18k1w3k1w10k2e1,e14k1w34k1e1,e14k1w34k1e1,e13k1w35k1e1,e13k1w35k1e1,e13k1w35k2,e13k1w36k1,e12k2w36k1,e12k1w36k2,e12k1w36k1e1,e11k2w36k1e1,e10k1w38k1e1,e10k1w37k2e1,e10k1w37k1e2,e9k1w37k2e2,e8k2w37k1e3,e8k1w38k1e3,e7k2w38k1e3,e6k1w39k1e4,e6k1w39k1e4,e6k1w39k1e4,e6k1w38k1e5,e5k2w38k1e5,e5k2w38k1e5,e4k3w37k1e6,e4k2w38k1e6,e4k2w15k4w19k1e6,e4k2w13k2g3k2w17k1e7,e4k1w12k3g5k1w17k1e7,e4k1w10k3e1k1g5k1w17k1e7,e4k2w7k3e3k1g5k1w10k4w2k1e8,e6k8e5k1g4k1w10k2g3k1w1k1e8,e19k1g4k1w10k2g3k1w1k1e8,e19k2g2k3w7k4g3k1w1k1e8,e20k4e1k1w6k2e2k1g3k1w1k1e8,e25k1w5k2e4k1g2k3e8,e25k6e6k2g1k2e9,e38k4e9,e51,e51,e51,e51/e51,e51,e51,e51,e51,e51,e51,e25k10e16,e23k3w8k5e12,e21k3w14k3e10,e19k3w18k2e9,e18k2w21k3e7,e17k2w24k2e6,e16k2w26k2e5,e16k1w28k2e4,e15k1w30k2e3,e14k2w9k5w3k1w3k1w2k5w2k1e3,e14k1w10k5w3k5w2k5w2k2e2,e14k1w18k1w3k1w10k1e2,e14k1w33k2e1,e13k1w35k1e1,e13k1w35k1e1,e13k1w35k1e1,e13k1w35k1e1,e13k1w35k1e1,e12k2w35k1e1,e12k1w36k1e1,e12k1w36k1e1,e11k1w37k1e1,e10k2w36k2e1,e10k1w37k1e2,e9k1w38k1e2,e9k1w37k1e3,e8k1w38k1e3,e8k1w38k1e3,e7k1w39k1e3,e7k1w38k1e4,e6k1w39k1e4,e6k1w39k1e4,e5k1w40k1e4,e4k1w40k1e5,e4k1w40k1e5,e3k1w41k1e5,e3k1w15k5w20k1e6,e3k1w14k2e1k1g1k2w19k1e6,e3k1w11k3e3k1g2k1w18k1e7,e3k1w9k3e4k1g3k1w18k1e7,e4k2w5k3e6k1g2k2w18k1e7,e5k6e9k1g2k1w10k5w3k2e7,e20k1g2k1w10k1e1k1g1k2w2k1e8,e20k1g2k1w9k1e3k1g1k1w2k1e8,e20k1g2k1w8k2e3k3w2k1e8,e20k2g1k2w6k1e6k2w2k1e8,e21k4w4k2e8k1w1k2e8,e24k6e9k1w1k1e9,e39k3e9,e51,e51/e51,e51,e51,e51,e51,e51,e51,e51,e26k12e13,e23k4w10k3e11,e21k3w16k2e9,e19k3w19k3e7,e18k2w23k2e6,e17k2w25k2e5,e16k2w27k2e4,e15k2w29k1e4,e15k1w31k1e3,e14k2w31k2e2,e14k1w10k5w3k1w3k1w2k5w3k1e2,e14k1w10k5w3k5w2k5w3k1e2,e13k2w18k1w3k1w10k2e1,e13k1w35k1e1,e13k1w35k1e1,e13k1w35k1e1,e13k1w35k1e1,e12k2w35k1e1,e12k1w36k1e1,e12k1w36k1e1,e12k1w36k1e1,e11k1w37k1e1,e10k1w37k2e1,e10k1w37k1e2,e10k1w37k1e2,e9k1w37k1e3,e8k1w38k1e3,e8k1w38k1e3,e7k1w39k1e3,e7k1w39k1e3,e6k1w39k1e4,e6k1w39k1e4,e5k1w40k1e4,e4k1w40k1e5,e3k1w41k1e5,e3k1w13k5w23k1e5,e2k2w11k2e4k2w21k1e6,e2k1w10k3e6k1w21k1e6,e2k1w7k3g1k1e6k2w20k1e7,e2k3w2k4g2k2e6k1w21k1e7,e4k4e1k1g1k3e7k1w21k1e7,e9k3e8k1w11k5w5k2e7,e20k1w10k2e3k2w5k1e7,e20k1w9k2e5k1w4k1e8,e20k1w8k2e6k1w4k1e8,e20k2w6k2e7k2w3k1e8,e21k2w2k4e9k1w2k2e8,e22k3e13k1w2k1e9,e38k4e9,e39k2e10/e51,e51,e51,e51,e51,e51,e51,e27k11e13,e24k4w10k3e10,e21k3w16k3e8,e19k3w20k2e7,e18k2w23k2e6,e17k2w25k2e5,e16k2w27k2e4,e15k2w29k1e4,e14k2w30k2e3,e14k1w32k1e3,e13k2w32k2e2,e13k1w11k5w3k1w3k1w2k5w3k1e2,e13k1w11k5w3k5w2k5w3k1e2,e13k1w19k1w3k1w11k1e1,e12k1w36k1e1,e12k1w36k1e1,e12k1w36k1e1,e12k1w36k1e1,e12k1w36k1e1,e11k1w36k2e1,e11k1w36k1e2,e10k1w37k1e2,e10k1w37k1e2,e9k1w38k1e2,e9k1w37k2e2,e8k1w38k1e3,e8k1w38k1e3,e7k1w39k1e3,e7k1w39k1e3,e6k1w39k1e4,e5k2w39k1e4,e4k2w40k1e4,e3k1w41k1e5,e2k1w42k1e5,e1k2w11k5w26k1e5,e1k1w11k2g3k2w24k1e6,e1k1w8k3g4k3w24k1e6,e1k1w6k3g6k1e1k1w24k1e6,e1k1w3k5g6k1e1k1w24k1e7,e1k5e3k1g5k1e2k1w24k1e7,e9k1g3k2e3k1w23k2e7,e10k4e3k2w14k4w5k1e8,e17k1w14k2e2k2w4k1e8,e17k1w12k2e5k1w4k1e8,e17k2w10k2e6k1w3k2e8,e18k2w7k3e7k1w3k1e9,e19k2w3k3g1k1e8k1w3k1e9,e20k9e8k1w2k2e9,e37k4e10,e38k2e11,e51"
local kGhostW, kGhostH = 51, 58
local ghostPalette = {
	k = Color3.fromRGB(10, 10, 14),
	w = Color3.fromRGB(255, 255, 255),
	g = Color3.fromRGB(157, 157, 157),
}

local ghostFrames = {}
for frameStr in string.gmatch(kGhostData, "[^/]+") do
	local runs = {}
	local y = 0
	for rowStr in string.gmatch(frameStr, "[^,]+") do
		local x = 0
		for c, n in string.gmatch(rowStr, "(%a)(%d+)") do
			n = tonumber(n)
			if c ~= "e" then runs[#runs + 1] = { x, y, n, c } end
			x = x + n
		end
		y = y + 1
	end
	ghostFrames[#ghostFrames + 1] = runs
end

local function createGhost(parent, px)
	local root = Instance.new("Frame")
	root.Name = "Ghost"
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Size = UDim2.fromOffset(kGhostW * px, kGhostH * px)
	root.Parent = parent

	local pool = {}
	local current = 0
	local ghost = { root = root }

	function ghost:setFrame(i)
		local runs = ghostFrames[i]
		if not runs or current == i then return end
		current = i
		for j = 1, #runs do
			local r = runs[j]
			local f = pool[j]
			if not f then
				f = Instance.new("Frame")
				f.BorderSizePixel = 0
				f.Parent = root
				pool[j] = f
			end
			f.Position = UDim2.fromOffset(r[1] * px, r[2] * px)
			f.Size = UDim2.fromOffset(r[3] * px, px)
			f.BackgroundColor3 = ghostPalette[r[4]]
			f.Visible = true
		end
		for j = #runs + 1, #pool do pool[j].Visible = false end
	end

	function ghost:play(cycles, fps)
		for _ = 1, cycles do
			for i = 1, #ghostFrames do
				if not root.Parent then return end
				ghost:setFrame(i)
				task.wait(1 / fps)
			end
		end
		if root.Parent then ghost:setFrame(1) end
	end

	ghost:setFrame(1)
	return ghost
end

----------------------------------------------------------------
-- ROOT GUI
----------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "GhostedMenu"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder = 999
screenGui.Parent = guiParent

local mainFrame = Instance.new("Frame")
mainFrame.Name = "Main"
mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
mainFrame.Size = UDim2.new(0, 0, 0, 0)
mainFrame.BackgroundColor3 = Color3.fromRGB(22, 22, 30)  -- FIX: was Color3.new(1,1,1) → white flash on open
mainFrame.BorderSizePixel = 0
mainFrame.ClipsDescendants = true
mainFrame.Visible = false
mainFrame.Parent = screenGui
addCorner(mainFrame, 14)

local menuScale = Instance.new("UIScale")
menuScale.Scale = 1
menuScale.Parent = mainFrame

do
	local stroke = addStroke(mainFrame, accent, 1.5, 0.2)
	bindAccent(stroke, "Color")
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(28, 28, 38)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(16, 16, 22)),
	})
	gradient.Rotation = 90
	gradient.Parent = mainFrame
end

----------------------------------------------------------------
-- TOAST
----------------------------------------------------------------
local toast = Instance.new("TextLabel")
toast.Name = "Toast"
toast.AnchorPoint = Vector2.new(0.5, 1)
toast.Position = UDim2.new(0.5, 0, 1, -24)
toast.Size = UDim2.new(0, 250, 0, 34)
toast.BackgroundColor3 = Color3.fromRGB(22, 22, 30)
toast.BackgroundTransparency = 1
toast.TextTransparency = 1
toast.TextColor3 = Color3.new(1, 1, 1)
toast.Font = Enum.Font.GothamBold
toast.TextSize = 14
toast.Text = ""
toast.ZIndex = 100
toast.Parent = screenGui
addCorner(toast, -1)
local toastStroke = addStroke(toast, Color3.fromRGB(110, 110, 255), 1, 1)
bindAccent(toastStroke, "Color")

local toastToken = 0
local function notify(text)
	if not opts.notifs then return end
	if opts.sounds then
		pcall(function()
			local s = Instance.new("Sound")
			s.SoundId = "rbxasset://sounds/electronicpingshort.wav"
			s.Volume = 0.4
			s.Parent = screenGui
			s:Play()
			game:GetService("Debris"):AddItem(s, 2)
		end)
	end
	toastToken = toastToken + 1
	local mine = toastToken
	toast.Text = text
	TweenService:Create(toast, TweenInfo.new(0.15), { BackgroundTransparency = 0.05, TextTransparency = 0 }):Play()
	TweenService:Create(toastStroke, TweenInfo.new(0.15), { Transparency = 0.4 }):Play()
	task.delay(1.7, function()
		if toastToken ~= mine then return end
		TweenService:Create(toast, TweenInfo.new(0.3), { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
		TweenService:Create(toastStroke, TweenInfo.new(0.3), { Transparency = 1 }):Play()
	end)
end

----------------------------------------------------------------
-- TITLE BAR
----------------------------------------------------------------
local titleBar = Instance.new("Frame")
titleBar.Name = "TitleBar"
titleBar.Size = UDim2.new(1, 0, 0, 56)
titleBar.BackgroundTransparency = 1
titleBar.Parent = mainFrame

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "Title"
titleLabel.Size = UDim2.new(1, -140, 0, 26)
titleLabel.Position = UDim2.new(0, 12, 0, 8)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "Ghosted Menu"
titleLabel.TextColor3 = Color3.new(1, 1, 1)
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 22
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.TextTransparency = 1
titleLabel.Parent = titleBar

local creditLabel = Instance.new("TextLabel")
creditLabel.Name = "Credit"
creditLabel.Size = UDim2.new(1, -140, 0, 16)
creditLabel.Position = UDim2.new(0, 12, 0, 32)
creditLabel.BackgroundTransparency = 1
creditLabel.Text = "made by Dani & Elixir & Hade"
creditLabel.TextColor3 = kTextDim
creditLabel.Font = Enum.Font.Gotham
creditLabel.TextSize = 13
creditLabel.TextXAlignment = Enum.TextXAlignment.Left
creditLabel.TextTransparency = 1
creditLabel.Parent = titleBar

local activeBadge = Instance.new("Frame")
activeBadge.Name = "ActiveBadge"
activeBadge.AnchorPoint = Vector2.new(1, 0)
activeBadge.Position = UDim2.new(1, -46, 0, 14)
activeBadge.Size = UDim2.new(0, 80, 0, 24)
activeBadge.BackgroundColor3 = Color3.fromRGB(40, 40, 54)
activeBadge.Parent = titleBar
addCorner(activeBadge, -1)

local activeDot = Instance.new("Frame")
activeDot.AnchorPoint = Vector2.new(0.5, 0.5)
activeDot.Position = UDim2.new(0, 14, 0.5, 0)
activeDot.Size = UDim2.new(0, 8, 0, 8)
activeDot.BackgroundColor3 = Color3.fromRGB(90, 230, 120)
activeDot.Parent = activeBadge
addCorner(activeDot, -1)

local activeLabel = Instance.new("TextLabel")
activeLabel.AnchorPoint = Vector2.new(0, 0.5)
activeLabel.Position = UDim2.new(0, 26, 0.5, 0)
activeLabel.Size = UDim2.new(1, -30, 1, 0)
activeLabel.BackgroundTransparency = 1
activeLabel.Text = "0 active"
activeLabel.TextColor3 = Color3.fromRGB(200, 200, 215)
activeLabel.Font = Enum.Font.GothamBold
activeLabel.TextSize = 12
activeLabel.TextXAlignment = Enum.TextXAlignment.Left
activeLabel.Parent = activeBadge

local activeCount = 0
local function bumpActive(delta)
	activeCount = math.max(0, activeCount + delta)
	activeLabel.Text = activeCount .. " active"
	TweenService:Create(activeDot, TweenInfo.new(0.1), { Size = UDim2.new(0, 12, 0, 12) }):Play()
	task.delay(0.1, function()
		TweenService:Create(activeDot, TweenInfo.new(0.12), { Size = UDim2.new(0, 8, 0, 8) }):Play()
	end)
end

local closeBtn = Instance.new("TextButton")
closeBtn.Name = "Close"
closeBtn.AnchorPoint = Vector2.new(1, 0)
closeBtn.Position = UDim2.new(1, -12, 0, 13)
closeBtn.Size = UDim2.new(0, 26, 0, 26)
closeBtn.BackgroundColor3 = Color3.fromRGB(55, 30, 38)
closeBtn.Text = "×"
closeBtn.TextColor3 = Color3.fromRGB(255, 100, 100)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 18
closeBtn.AutoButtonColor = false
closeBtn.Parent = titleBar
addCorner(closeBtn, 6)
track(closeBtn.MouseEnter:Connect(function()
	TweenService:Create(closeBtn, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(200, 50, 60) }):Play()
	TweenService:Create(closeBtn, TweenInfo.new(0.1), { TextColor3 = Color3.new(1,1,1) }):Play()
end))
track(closeBtn.MouseLeave:Connect(function()
	TweenService:Create(closeBtn, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(55, 30, 38) }):Play()
	TweenService:Create(closeBtn, TweenInfo.new(0.1), { TextColor3 = Color3.fromRGB(255, 100, 100) }):Play()
end))

local underline = Instance.new("Frame")
underline.Size = UDim2.new(0, 0, 0, 3)
underline.Position = UDim2.new(0.5, 0, 0, 52)
underline.AnchorPoint = Vector2.new(0.5, 0)
underline.BorderSizePixel = 0
underline.Parent = mainFrame
bindAccent(underline, "BackgroundColor3")
addCorner(underline, -1)

makeDraggable(titleBar, mainFrame, nil)

----------------------------------------------------------------
-- TABS + PAGES
----------------------------------------------------------------
-- Horizontally scrollable tab bar (drag / swipe / scrollbar / Shift+wheel)
local tabBar = Instance.new("ScrollingFrame")
tabBar.Name = "TabBar"
tabBar.Size = UDim2.new(1, -20, 0, 34)
tabBar.Position = UDim2.new(0, 10, 0, 62)
tabBar.BackgroundTransparency = 1
tabBar.BorderSizePixel = 0
tabBar.Active = true
tabBar.ScrollingDirection = Enum.ScrollingDirection.X
tabBar.CanvasSize = UDim2.new(0, 0, 0, 0)
tabBar.AutomaticCanvasSize = Enum.AutomaticSize.X
tabBar.ScrollBarThickness = 3
tabBar.ScrollBarImageTransparency = 0.4
tabBar.ElasticBehavior = Enum.ElasticBehavior.Never
tabBar.HorizontalScrollBarInset = Enum.ScrollBarInset.Always
tabBar.Parent = mainFrame
bindAccent(tabBar, "ScrollBarImageColor3")

local tabRow = Instance.new("Frame")
tabRow.Name = "TabRow"
tabRow.Size = UDim2.new(0, 0, 0, 28)
tabRow.AutomaticSize = Enum.AutomaticSize.X
tabRow.BackgroundTransparency = 1
tabRow.Parent = tabBar

do
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Horizontal
	l.Padding = UDim.new(0, 6)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = tabRow
end

-- Sliding indicator bar under tabs (not inside the list layout)
local tabIndicator = Instance.new("Frame")
tabIndicator.Name = "TabIndicator"
tabIndicator.Size = UDim2.new(0, 40, 0, 2)
tabIndicator.Position = UDim2.new(0, 0, 0, 29)
tabIndicator.BorderSizePixel = 0
tabIndicator.ZIndex = 5
tabIndicator.Parent = tabBar
bindAccent(tabIndicator, "BackgroundColor3")
addCorner(tabIndicator, -1)

local pagesHolder = Instance.new("Frame")
pagesHolder.Name = "Pages"
pagesHolder.Size = UDim2.new(1, -20, 1, -166)
pagesHolder.Position = UDim2.new(0, 10, 0, 104)
pagesHolder.BackgroundTransparency = 1
pagesHolder.Parent = mainFrame

local tabNames = { "Move", "Visuals", "Players", "Misc", "Extra", "Fun", "World", "Chat", "Tools", "Combat", "Camera", "Audio", "Session", "Automation", "Teleports", "Server", "Presets", "Keybinds", "Themes", "Notes", "Credits", "Updates", "Config" }
local tabButtons = {}
local pages = {}
local currentTab = "Move"

local function selectTab(name)
	currentTab = name
	for pname, page in pairs(pages) do page.Visible = (pname == name) end
	for bname, btn in pairs(tabButtons) do
		local active = (bname == name)
		TweenService:Create(btn, TweenInfo.new(0.15), {
			BackgroundColor3 = active and Color3.fromRGB(38, 38, 52) or kRowBg,
		}):Play()
		btn.TextColor3 = active and Color3.new(1, 1, 1) or Color3.fromRGB(130, 130, 150)
		-- animate indicator to active tab
		if active then
			task.defer(function()
				local k = menuScale.Scale
				local x = (btn.AbsolutePosition.X - tabRow.AbsolutePosition.X) / k
				local w = btn.AbsoluteSize.X / k
				TweenService:Create(tabIndicator, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
					Position = UDim2.new(0, x, 0, 29),
					Size = UDim2.new(0, w, 0, 2),
				}):Play()
				-- scroll the tab into view
				local view = tabBar.AbsoluteSize.X / k
				local cur = tabBar.CanvasPosition.X
				local target = cur
				if x < cur then target = x - 4
				elseif x + w > cur + view then target = x + w - view + 4 end
				if target ~= cur then
					TweenService:Create(tabBar, TweenInfo.new(0.2), { CanvasPosition = Vector2.new(math.max(target, 0), 0) }):Play()
				end
			end)
		end
	end
end
accentCallbacks[#accentCallbacks + 1] = function() selectTab(currentTab) end

for i, name in ipairs(tabNames) do
	local btn = Instance.new("TextButton")
	btn.Name = name .. "Tab"
	btn.Size = UDim2.new(0, 70, 1, 0)
	btn.LayoutOrder = i
	btn.BackgroundColor3 = kRowBg
	btn.Text = name
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 13
	btn.TextColor3 = Color3.fromRGB(150, 150, 165)
	btn.AutoButtonColor = false
	btn.Parent = tabRow
	addCorner(btn, 8)
	track(btn.MouseButton1Click:Connect(function() selectTab(name) end))
	tabButtons[name] = btn

	local page = Instance.new("ScrollingFrame")
	page.Name = name .. "Page"
	page.Size = UDim2.new(1, 0, 1, 0)
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.ScrollBarThickness = 4
	page.CanvasSize = UDim2.new(0, 0, 0, 0)
	page.AutomaticCanvasSize = Enum.AutomaticSize.Y
	page.ClipsDescendants = true
	page.Active = true
	page.ScrollingEnabled = true
	page.ScrollingDirection = Enum.ScrollingDirection.Y
	page.ElasticBehavior = Enum.ElasticBehavior.Never
	page.ScrollBarImageTransparency = 0.3
	page.VerticalScrollBarInset = Enum.ScrollBarInset.Always
	page.Visible = false
	page.Parent = pagesHolder
	bindAccent(page, "ScrollBarImageColor3")

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = page

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 2)
	pad.PaddingRight = UDim.new(0, 6)
	pad.PaddingTop = UDim.new(0, 2)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.Parent = page

	pages[name] = page
end
selectTab("Move")

local movePage    = pages.Move
local visualsPage = pages.Visuals
local miscPage    = pages.Misc
local configPage  = pages.Config
local playersPage = pages.Players

----------------------------------------------------------------
-- ROW BUILDERS
----------------------------------------------------------------
local toggleSetters = {}
local sliderResets  = {}

local function makeSection(text, order, parent)
	local container = Instance.new("Frame")
	container.Size = UDim2.new(1, 0, 0, 20)
	container.BackgroundTransparency = 1
	container.LayoutOrder = order
	container.Parent = parent

	-- accent bar on left
	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(0, 3, 1, -4)
	bar.Position = UDim2.new(0, 2, 0, 2)
	bar.BorderSizePixel = 0
	bar.Parent = container
	addCorner(bar, -1)
	bindAccent(bar, "BackgroundColor3")

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, -14, 1, 0)
	lbl.Position = UDim2.new(0, 12, 0, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text = text
	lbl.TextColor3 = Color3.fromRGB(130, 130, 155)
	lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = 11
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Parent = container

	-- we return lbl so existing code that reads/writes .Text still works
	return lbl
end

local featureToggles = {}
local bindingFeature = nil
local rebinding      = false

local function refreshBindTag(key)
	local e = featureToggles[key]
	if not e then return end
	local bound = settings.binds[key]
	e.tag.Text = (bindingFeature == key) and "press key" or (bound and ("[" .. bound .. "]") or "")
end

local function makeToggleRow(o)
	local hasDesc  = o.desc ~= nil
	local iconColor = o.color or accent

	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, hasDesc and 52 or 42)
	row.BackgroundColor3 = kRowBg
	row.LayoutOrder = o.order or 0
	row.Parent = o.parent
	addCorner(row, 8)

	local rowStroke = addStroke(row, accent, 1, 1)
	bindAccent(rowStroke, "Color")

	local icon = Instance.new("Frame")
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 10, 0.5, 0)
	icon.Size = UDim2.new(0, 4, 0, hasDesc and 28 or 22)
	icon.BackgroundColor3 = iconColor
	icon.BackgroundTransparency = 0.7
	icon.BorderSizePixel = 0
	icon.Parent = row
	addCorner(icon, -1)

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -120, 0, hasDesc and 20 or 42)
	label.Position = UDim2.new(0, 24, 0, hasDesc and 6 or 0)
	label.BackgroundTransparency = 1
	label.Text = o.name
	label.TextColor3 = Color3.fromRGB(230, 230, 235)
	label.Font = Enum.Font.Gotham
	label.TextSize = 15
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = row

	if hasDesc then
		local desc = Instance.new("TextLabel")
		desc.Size = UDim2.new(1, -120, 0, 16)
		desc.Position = UDim2.new(0, 24, 0, 27)
		desc.BackgroundTransparency = 1
		desc.Text = o.desc
		desc.TextColor3 = kTextDim
		desc.Font = Enum.Font.Gotham
		desc.TextSize = 11
		desc.TextXAlignment = Enum.TextXAlignment.Left
		desc.TextTruncate = Enum.TextTruncate.AtEnd
		desc.Parent = row
	end

	local bindTag = Instance.new("TextLabel")
	bindTag.AnchorPoint = Vector2.new(1, 0.5)
	bindTag.Position = UDim2.new(1, -64, 0.5, 0)
	bindTag.Size = UDim2.new(0, 56, 0, 16)
	bindTag.BackgroundTransparency = 1
	bindTag.Text = ""
	bindTag.TextColor3 = kTextDim
	bindTag.Font = Enum.Font.GothamBold
	bindTag.TextSize = 11
	bindTag.TextXAlignment = Enum.TextXAlignment.Right
	bindTag.Parent = row

	local switchBg = Instance.new("Frame")
	switchBg.Size = UDim2.new(0, 46, 0, 24)
	switchBg.AnchorPoint = Vector2.new(1, 0.5)
	switchBg.Position = UDim2.new(1, -10, 0.5, 0)
	switchBg.BackgroundColor3 = kSwitchOff
	switchBg.Parent = row
	addCorner(switchBg, -1)

	local knob = Instance.new("Frame")
	knob.Size = UDim2.new(0, 18, 0, 18)
	knob.Position = UDim2.new(0, 3, 0.5, -9)
	knob.BackgroundColor3 = Color3.new(1, 1, 1)
	knob.Parent = switchBg
	addCorner(knob, -1)

	local clickBtn = Instance.new("TextButton")
	clickBtn.Size = UDim2.new(1, 0, 1, 0)
	clickBtn.BackgroundTransparency = 1
	clickBtn.Text = ""
	clickBtn.Parent = row

	track(clickBtn.MouseEnter:Connect(function()
		TweenService:Create(row, TweenInfo.new(0.12), { BackgroundColor3 = kRowBgHover }):Play()
	end))
	track(clickBtn.MouseLeave:Connect(function()
		TweenService:Create(row, TweenInfo.new(0.12), { BackgroundColor3 = kRowBg }):Play()
	end))

	local state = false
	local function setState(on, silent)
		on = on and true or false
		if state == on then return end
		state = on

		TweenService:Create(knob, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
			Position = on and UDim2.new(0, 25, 0.5, -9) or UDim2.new(0, 3, 0.5, -9),
		}):Play()
		TweenService:Create(switchBg, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
			BackgroundColor3 = on and accent or kSwitchOff,
		}):Play()
		TweenService:Create(icon, TweenInfo.new(0.15), { BackgroundTransparency = on and 0 or 0.7 }):Play()
		TweenService:Create(rowStroke, TweenInfo.new(0.15), { Transparency = on and 0.5 or 1 }):Play()

		if o.opt then
			settings.opts[o.opt] = on
			if not silent then saveSettings() end
		else
			bumpActive(on and 1 or -1)
			if o.key then
				settings.toggles[o.key] = on or nil
				if not silent then saveSettings() end
			end
		end

		local ok, err = pcall(o.callback, on)
		if not ok then warn("[Ghosted Menu] " .. o.name .. ": " .. tostring(err)) end
		if not silent then notify(o.name .. (on and " on" or " off")) end
	end

	accentCallbacks[#accentCallbacks + 1] = function(c)
		if state then switchBg.BackgroundColor3 = c end
	end

	track(clickBtn.MouseButton1Click:Connect(function() setState(not state) end))

	if o.key and not o.opt then
		featureToggles[o.key] = { tag = bindTag, set = setState, get = function() return state end, name = o.name }
		refreshBindTag(o.key)
		track(clickBtn.MouseButton2Click:Connect(function()
			if rebinding then return end
			local prev = bindingFeature
			bindingFeature = o.key
			if prev and prev ~= o.key then refreshBindTag(prev) end
			refreshBindTag(o.key)
		end))
	end

	if not o.opt then toggleSetters[#toggleSetters + 1] = setState end

	if o.opt then
		if opts[o.opt] then setState(true, true) end
	elseif o.key and settings.toggles[o.key] == true then
		setState(true, true)
	end

	return row, setState
end

local function makeSliderRow(o)
	local min, max = o.min, o.max
	local value = o.default
	local saved = o.key and settings.sliders[o.key]
	if type(saved) == "number" then
		value = math.clamp(math.floor(saved), min, max)
	end

	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 48)
	row.BackgroundColor3 = kRowBg
	row.LayoutOrder = o.order or 0
	row.Parent = o.parent
	addCorner(row, 8)

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -24, 0, 20)
	label.Position = UDim2.new(0, 12, 0, 4)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(230, 230, 235)
	label.Font = Enum.Font.Gotham
	label.TextSize = 14
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = row

	local track_ = Instance.new("Frame")
	track_.Size = UDim2.new(1, -24, 0, 6)
	track_.Position = UDim2.new(0, 12, 1, -14)
	track_.BackgroundColor3 = kSwitchOff
	track_.Parent = row
	addCorner(track_, -1)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BorderSizePixel = 0
	fill.Parent = track_
	bindAccent(fill, "BackgroundColor3")
	addCorner(fill, -1)

	local function render(v)
		fill.Size = UDim2.new((v - min) / (max - min), 0, 1, 0)
		label.Text = o.name .. ": " .. tostring(v)
	end

	local function setValue(v, silent)
		v = math.clamp(math.floor(v + 0.5), min, max)
		value = v
		render(v)
		pcall(o.callback, v)
		if o.key then
			if v == o.default then settings.sliders[o.key] = nil else settings.sliders[o.key] = v end
			if not silent then saveSettings() end
		end
	end

	render(value)
	if value ~= o.default then pcall(o.callback, value) end
	sliderResets[#sliderResets + 1] = function() setValue(o.default, true) end

	local dragging = false
	local function fromX(x)
		local rel = math.clamp((x - track_.AbsolutePosition.X) / math.max(track_.AbsoluteSize.X, 1), 0, 1)
		setValue(min + (max - min) * rel)
	end

	track(track_.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			fromX(input.Position.X)
		end
	end))
	track(UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			fromX(input.Position.X)
		end
	end))
	track(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end))

	return row, setValue
end

local function makeButtonRow(o)
	local base = o.color or kRowBg
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, 0, 0, 40)
	btn.BackgroundColor3 = base
	btn.Text = o.text
	btn.TextColor3 = Color3.fromRGB(235, 235, 240)
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 14
	btn.AutoButtonColor = false
	btn.LayoutOrder = o.order or 0
	btn.Parent = o.parent
	addCorner(btn, 8)

	track(btn.MouseEnter:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundColor3 = base:Lerp(Color3.new(1, 1, 1), 0.1) }):Play()
	end))
	track(btn.MouseLeave:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundColor3 = base }):Play()
	end))
	track(btn.MouseButton1Click:Connect(function() o.callback(btn) end))
	return btn
end

----------------------------------------------------------------
-- OPEN / CLOSE
----------------------------------------------------------------
local isOpen = false

local function getMenuSize()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
	local k = menuScale.Scale
	return UDim2.new(0, math.min(kMenuW, (vp.X - 24) / k), 0, math.min(kMenuH, (vp.Y - 24) / k))
end

local function openMenu()
	mainFrame.Visible = true
	isOpen = true
	TweenService:Create(mainFrame, TweenInfo.new(kTweenTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = getMenuSize(),
	}):Play()
	TweenService:Create(titleLabel, TweenInfo.new(kTweenTime), { TextTransparency = 0 }):Play()
	TweenService:Create(creditLabel, TweenInfo.new(kTweenTime), { TextTransparency = 0 }):Play()
	task.delay(kTweenTime * 0.5, function()
		TweenService:Create(underline, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {
			Size = UDim2.new(0, 150, 0, 3),
		}):Play()
	end)
	-- re-place the tab indicator now that the menu has real size
	task.delay(kTweenTime + 0.05, function() selectTab(currentTab) end)
end

local function closeMenu()
	isOpen = false
	TweenService:Create(mainFrame, TweenInfo.new(kTweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Size = UDim2.new(0, 0, 0, 0),
	}):Play()
	TweenService:Create(titleLabel, TweenInfo.new(0.15), { TextTransparency = 1 }):Play()
	TweenService:Create(creditLabel, TweenInfo.new(0.15), { TextTransparency = 1 }):Play()
	TweenService:Create(underline, TweenInfo.new(0.15), { Size = UDim2.new(0, 0, 0, 3) }):Play()
	task.delay(kTweenTime, function()
		if not isOpen then mainFrame.Visible = false end
	end)
end

local function toggleMenu()
	if isOpen then closeMenu() else openMenu() end
end

track(closeBtn.MouseButton1Click:Connect(closeMenu))

local toggleBtn = Instance.new("TextButton")
toggleBtn.Name = "ToggleButton"
toggleBtn.Size = UDim2.new(0, kToggleBtnSize, 0, kToggleBtnSize)
toggleBtn.Position = UDim2.new(0, 20, 0.5, -kToggleBtnSize / 2)
toggleBtn.BackgroundColor3 = Color3.fromRGB(34, 34, 46)
toggleBtn.Text = ""
toggleBtn.AutoButtonColor = false
toggleBtn.ZIndex = 50
toggleBtn.Visible = opts.showButton
toggleBtn.Parent = screenGui
addCorner(toggleBtn, 18)
do
	local s = addStroke(toggleBtn, accent, 1.5, 0)
	bindAccent(s, "Color")
end

local btnGhost = createGhost(toggleBtn, 1)
do
	local gx = -math.floor(kGhostW / 2)
	local gy = -math.floor(kGhostH / 2)
	btnGhost.root.Position = UDim2.new(0.5, gx, 0.5, gy - 2)
	TweenService:Create(btnGhost.root, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		Position = UDim2.new(0.5, gx, 0.5, gy + 2),
	}):Play()

	local playing = false
	track(toggleBtn.MouseEnter:Connect(function()
		if playing then return end
		playing = true
		task.spawn(function()
			btnGhost:play(1, 20)
			playing = false
		end)
	end))
end
makeDraggable(toggleBtn, toggleBtn, toggleMenu)

----------------------------------------------------------------
-- FOOTER: DISCORD
----------------------------------------------------------------
do
	local blurple = Color3.fromRGB(88, 101, 242)
	local btn = Instance.new("TextButton")
	btn.Name = "DiscordButton"
	btn.AnchorPoint = Vector2.new(0.5, 1)
	btn.Position = UDim2.new(0.5, 0, 1, -12)
	btn.Size = UDim2.new(1, -20, 0, 40)
	btn.BackgroundColor3 = blurple
	btn.Text = "Join Discord"
	btn.TextColor3 = Color3.new(1, 1, 1)
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 15
	btn.AutoButtonColor = false
	btn.Parent = mainFrame
	addCorner(btn, 8)
	addStroke(btn, Color3.fromRGB(140, 150, 255), 1, 0.4)

	track(btn.MouseEnter:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundColor3 = Color3.fromRGB(104, 116, 246) }):Play()
	end))
	track(btn.MouseLeave:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundColor3 = blurple }):Play()
	end))

	local busy = false
	track(btn.MouseButton1Click:Connect(function()
		if busy then return end
		busy = true
		local copied = pcall(function()
			if setclipboard then setclipboard(kDiscordLink)
			elseif toclipboard then toclipboard(kDiscordLink)
			else error("no clipboard api") end
		end)
		btn.Text = copied and "Copied link!" or "Copy failed - see console"
		TweenService:Create(btn, TweenInfo.new(0.12), {
			BackgroundColor3 = copied and Color3.fromRGB(90, 200, 120) or Color3.fromRGB(220, 80, 80),
		}):Play()
		if not copied then warn("[Ghosted Menu] No clipboard API. Discord: " .. kDiscordLink) end
		task.delay(1.6, function()
			btn.Text = "Join Discord"
			TweenService:Create(btn, TweenInfo.new(0.2), { BackgroundColor3 = blurple }):Play()
			busy = false
		end)
	end))
end

----------------------------------------------------------------
-- SHARED CHARACTER HELPERS
----------------------------------------------------------------
local function getHumanoid()
	local c = player.Character
	return c and c:FindFirstChildOfClass("Humanoid")
end

local origGravity = workspace.Gravity
local origFov = (workspace.CurrentCamera and workspace.CurrentCamera.FieldOfView) or 70

----------------------------------------------------------------
-- FLING HELPER (shared between Players tab buttons)
----------------------------------------------------------------
local flingPower = kDefaultFlingPower

-- Why the old version did nothing: it only changed the target's physics on YOUR
-- client, and other players' characters are simulated by their own owner, so it
-- never replicated. This version uses your own character as the projectile:
-- it spins you at huge speed, glues you onto the target for a moment so the
-- collision flings them, then puts you back where you started.
local flinging = false
local flingConn

local function flingPlayer(plr)
	if flinging then notify("Already flinging") return end

	local char = player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	local hum  = char and char:FindFirstChildOfClass("Humanoid")
	local tChar = plr.Character
	local tHrp  = tChar and tChar:FindFirstChild("HumanoidRootPart")
	local tHum  = tChar and tChar:FindFirstChildOfClass("Humanoid")
	if not (hrp and hum and tHrp and tHum) or hum.Health <= 0 then
		notify("No character to fling")
		return
	end

	flinging = true
	local origCF = hrp.CFrame
	local camera = workspace.CurrentCamera
	local oldSubject = camera and camera.CameraSubject
	local t0 = os.clock()
	local duration = 1.6
	local power = flingPower * 20          -- slider is 500-50000

	-- keep our own body from tripping while we spin
	pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Seated, false) end)

	-- watch the target so the camera doesn't spin with us
	if camera and tHum then camera.CameraSubject = tHum end

	local function finish()
		disconnect(flingConn)
		flingConn = nil
		local c = player.Character
		local h = c and c:FindFirstChild("HumanoidRootPart")
		local hm = c and c:FindFirstChildOfClass("Humanoid")
		if h then
			-- put us back, and keep zeroing velocity for a few frames so we don't drift
			for _ = 1, 6 do
				h.AssemblyLinearVelocity  = Vector3.zero
				h.AssemblyAngularVelocity = Vector3.zero
				h.CFrame = origCF
				RunService.Heartbeat:Wait()
			end
		end
		if hm then pcall(function() hm:SetStateEnabled(Enum.HumanoidStateType.Seated, true) end) end
		if camera and oldSubject and oldSubject.Parent then camera.CameraSubject = oldSubject
		elseif camera and hm then camera.CameraSubject = hm end
		flinging = false
	end

	flingConn = RunService.Heartbeat:Connect(function()
		local c  = player.Character
		local h  = c and c:FindFirstChild("HumanoidRootPart")
		local th = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
		local thm = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")

		-- stop if anything went away, the target died, or time is up
		if not h or not th or not thm or thm.Health <= 0 or os.clock() - t0 > duration then
			task.spawn(finish)
			disconnect(flingConn)
			flingConn = nil
			return
		end

		-- stay glued to where the target is going, with a little jitter so we keep colliding
		local lead = th.AssemblyLinearVelocity * 0.12
		local jitter = Vector3.new(math.random(-10, 10) / 10, 0, math.random(-10, 10) / 10)
		h.CFrame = CFrame.new(th.Position + lead + jitter) * CFrame.Angles(math.rad(math.random(0, 360)), 0, 0)
		h.AssemblyAngularVelocity = Vector3.new(power, power, power)
		h.AssemblyLinearVelocity  = Vector3.new(power, power * 10, power)
	end)

	notify("Flinging " .. plr.DisplayName)
end
onUnload(function()
	disconnect(flingConn)
	flingConn = nil
	flinging = false
end)

----------------------------------------------------------------
-- MOVE TAB
----------------------------------------------------------------
makeSection("FLIGHT", 0, movePage)

do
	local flySpeed = kDefaultFlySpeed
	local flyConn
	local flyVertical = 0
	local controls

	local flyVertFrame = Instance.new("Frame")
	flyVertFrame.Name = "FlyVertical"
	flyVertFrame.AnchorPoint = Vector2.new(1, 0.5)
	flyVertFrame.Position = UDim2.new(1, -20, 0.5, 0)
	flyVertFrame.Size = UDim2.new(0, 56, 0, 120)
	flyVertFrame.BackgroundTransparency = 1
	flyVertFrame.Visible = false
	flyVertFrame.Parent = screenGui

	local function makeVertButton(text, y, delta)
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(0, 56, 0, 56)
		b.Position = UDim2.new(0, 0, 0, y)
		b.BackgroundColor3 = kRowBg
		b.Text = text
		b.TextColor3 = Color3.fromRGB(230, 230, 235)
		b.Font = Enum.Font.GothamBold
		b.TextSize = 18
		b.AutoButtonColor = false
		b.Parent = flyVertFrame
		addCorner(b, -1)
		local s = addStroke(b, accent, 1.5, 0.3)
		bindAccent(s, "Color")
		track(b.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				flyVertical = delta
				b.BackgroundColor3 = accent
			end
		end))
		track(b.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				if flyVertical == delta then flyVertical = 0 end
				b.BackgroundColor3 = kRowBg
			end
		end))
	end
	makeVertButton("UP", 0, 1)
	makeVertButton("DN", 64, -1)

	local function getFlyDirection(hum, cam)
		if controls == nil then
			controls = false
			pcall(function()
				local ps = player:FindFirstChild("PlayerScripts")
				local pm = ps and ps:FindFirstChild("PlayerModule")
				if pm then controls = require(pm):GetControls() end
			end)
		end
		if controls then
			local ok, mv = pcall(function() return controls:GetMoveVector() end)
			if ok and typeof(mv) == "Vector3" then
				return cam.CFrame.RightVector * mv.X - cam.CFrame.LookVector * mv.Z
			end
		end
		return hum.MoveDirection
	end

	-- Clean up fly physics objects on the current character
	local function cleanupFlyObjects()
		local char = player.Character
		local hrp  = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			-- new API
			local att = hrp:FindFirstChild("GhostedFlyAtt")
			if att then att:Destroy() end
			local lv = hrp:FindFirstChild("GhostedFlyLV")
			if lv then lv:Destroy() end
			local ao = hrp:FindFirstChild("GhostedFlyAO")
			if ao then ao:Destroy() end
			-- legacy
			local bv = hrp:FindFirstChild("GhostedFlyBV")
			if bv then bv:Destroy() end
			local bg = hrp:FindFirstChild("GhostedFlyBG")
			if bg then bg:Destroy() end
		end
		local hum = getHumanoid()
		if hum then hum.PlatformStand = false end
	end

	local function setFly(on)
		-- disconnect first, then decide
		disconnect(flyConn)
		flyConn = nil
		flyVertical = 0
		flyVertFrame.Visible = on and UserInputService.TouchEnabled

		if not on then
			cleanupFlyObjects()
			return
		end

		flyConn = RunService.RenderStepped:Connect(function()
			local char = player.Character
			local hrp  = char and char:FindFirstChild("HumanoidRootPart")
			local hum  = char and char:FindFirstChildOfClass("Humanoid")
			local cam  = workspace.CurrentCamera
			if not (hrp and hum and cam) or hum.Health <= 0 then return end

			hum.PlatformStand = true

			local vertical = flyVertical
			if not UserInputService:GetFocusedTextBox() then
				if UserInputService:IsKeyDown(Enum.KeyCode.Space)       then vertical =  1 end
				if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then vertical = -1 end
			end

			local move = getFlyDirection(hum, cam) + Vector3.new(0, vertical, 0)
			if move.Magnitude > 1 then move = move.Unit end
			local vel = move * flySpeed

			-- Try LinearVelocity (engine ≥ 604)
			local ok = pcall(function()
				local att = hrp:FindFirstChild("GhostedFlyAtt")
				if not att then
					att = Instance.new("Attachment")
					att.Name = "GhostedFlyAtt"
					att.Parent = hrp
				end
				local lv = hrp:FindFirstChild("GhostedFlyLV")
				if not lv then
					lv = Instance.new("LinearVelocity")
					lv.Name        = "GhostedFlyLV"
					lv.Attachment0 = att
					lv.MaxForce   = math.huge
					lv.Parent     = hrp
				end
				lv.VectorVelocity = vel

				local ao = hrp:FindFirstChild("GhostedFlyAO")
				if not ao then
					ao = Instance.new("AlignOrientation")
					ao.Name        = "GhostedFlyAO"
					ao.Attachment0 = att
					ao.MaxTorque   = math.huge
					ao.MaxAngularVelocity = math.huge
					ao.Responsiveness = 200
					ao.Parent     = hrp
				end
				ao.CFrame = cam.CFrame
			end)

			if not ok then
				-- legacy BodyVelocity / BodyGyro fallback
				local bv = hrp:FindFirstChild("GhostedFlyBV")
				if not bv then
					bv = Instance.new("BodyVelocity")
					bv.Name = "GhostedFlyBV"
					bv.MaxForce = Vector3.new(9e9, 9e9, 9e9)
					bv.Velocity = Vector3.zero
					bv.Parent = hrp
				end
				local bg = hrp:FindFirstChild("GhostedFlyBG")
				if not bg then
					bg = Instance.new("BodyGyro")
					bg.Name = "GhostedFlyBG"
					bg.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
					bg.P = 9e4
					bg.D = 1e3
					bg.Parent = hrp
				end
				bv.Velocity = vel
				bg.CFrame   = cam.CFrame
			end
		end)
	end

	makeToggleRow({
		name = "Fly", desc = "Space / Ctrl, or the UP / DN buttons",
		key = "fly", color = Color3.fromRGB(110, 170, 255), order = 1, parent = movePage, callback = setFly,
	})
	makeSliderRow({
		name = "Fly Speed", key = "flySpeed", min = 10, max = 250, default = kDefaultFlySpeed,
		order = 2, parent = movePage, callback = function(v) flySpeed = v end,
	})
end

makeSection("BODY", 3, movePage)

-- NOCLIP
do
	local noclipConn
	local orig = setmetatable({}, { __mode = "k" })

	local function setNoclip(on)
		disconnect(noclipConn)
		noclipConn = nil
		if on then
			noclipConn = RunService.Stepped:Connect(function()
				local char = player.Character
				if not char then return end
				for _, part in ipairs(char:GetDescendants()) do
					if part:IsA("BasePart") and part.CanCollide then
						orig[part] = true
						part.CanCollide = false
					end
				end
			end)
		else
			for part in pairs(orig) do
				if part.Parent then pcall(function() part.CanCollide = true end) end
				orig[part] = nil
			end
		end
	end

	makeToggleRow({
		name = "Noclip", desc = "Walk through walls",
		key = "noclip", color = Color3.fromRGB(180, 130, 255), order = 4, parent = movePage, callback = setNoclip,
	})
end

-- SPEED
do
	local walkSpeed = kDefaultWalkSpeed
	local speedConn, speedOrig

	local function setSpeed(on)
		disconnect(speedConn)
		speedConn = nil
		if on then
			-- capture orig; re-capture after respawn if stale
			local hum = getHumanoid()
			if hum and speedOrig == nil then speedOrig = hum.WalkSpeed end
			speedConn = RunService.Heartbeat:Connect(function()
				local h = getHumanoid()
				if h then
					-- if we just respawned we won't have orig yet
					if speedOrig == nil then speedOrig = h.WalkSpeed end
					h.WalkSpeed = walkSpeed
				end
			end)
		else
			local hum = getHumanoid()
			if hum and speedOrig then hum.WalkSpeed = speedOrig end
			speedOrig = nil
		end
	end

	makeToggleRow({
		name = "Speed Boost", desc = "Overrides WalkSpeed every frame",
		key = "speed", color = Color3.fromRGB(255, 200, 90), order = 5, parent = movePage, callback = setSpeed,
	})
	makeSliderRow({
		name = "Walk Speed", key = "walkSpeed", min = 16, max = 250, default = kDefaultWalkSpeed,
		order = 6, parent = movePage, callback = function(v) walkSpeed = v end,
	})
end

-- HIGH JUMP
do
	local jumpPower = kDefaultJumpPower
	local jumpConn, origPower, origUse

	local function setHighJump(on)
		disconnect(jumpConn)
		jumpConn = nil
		local hum = getHumanoid()
		if on then
			if hum and origPower == nil then
				origPower = hum.JumpPower
				origUse   = hum.UseJumpPower
			end
			jumpConn = RunService.Heartbeat:Connect(function()
				local h = getHumanoid()
				if h then
					pcall(function() h.UseJumpPower = true end)
					h.JumpPower = jumpPower
				end
			end)
		else
			if hum and origPower ~= nil then
				hum.JumpPower = origPower
				pcall(function() hum.UseJumpPower = origUse end)
			end
			origPower, origUse = nil, nil
		end
	end

	makeToggleRow({
		name = "High Jump", desc = "Overrides JumpPower every frame",
		key = "highjump", color = Color3.fromRGB(255, 150, 90), order = 7, parent = movePage, callback = setHighJump,
	})
	makeSliderRow({
		name = "Jump Power", key = "jumpPower", min = 50, max = 400, default = kDefaultJumpPower,
		order = 8, parent = movePage, callback = function(v) jumpPower = v end,
	})
end

-- INFINITE JUMP
do
	local jumpConn
	local function setInfiniteJump(on)
		disconnect(jumpConn)
		jumpConn = nil
		if on then
			jumpConn = UserInputService.JumpRequest:Connect(function()
				local hum = getHumanoid()
				if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
			end)
		end
	end
	makeToggleRow({
		name = "Infinite Jump", desc = "Jump again in mid-air",
		key = "infjump", color = Color3.fromRGB(90, 230, 150), order = 9, parent = movePage, callback = setInfiniteJump,
	})
end

makeSliderRow({
	name = "Gravity", key = "gravity", min = 10, max = 400, default = math.floor(origGravity + 0.5),
	order = 10, parent = movePage, callback = function(v) workspace.Gravity = v end,
})

----------------------------------------------------------------
-- VISUALS TAB
----------------------------------------------------------------
makeSection("ESP", 0, visualsPage)

local hasDrawing = (Drawing ~= nil) and (Drawing.new ~= nil)
local espTeamCheck = false

local chamsFolder = Instance.new("Folder")
chamsFolder.Name = "GhostedChams"
chamsFolder.Parent = guiParent

----------------------------------------------------------------
-- OVERHEAD TAG (Ghosted Member label + ghost icon above head)
-- Peer detection: players also running this script get a
-- "Using Ghosted" badge. We signal via a BoolValue parented
-- to LocalPlayer with a known name; remote clients see it.
----------------------------------------------------------------
do
	local kTagName       = "GhostedMemberTag"
	local kPeerSignal    = "GhostedScriptActive"    -- BoolValue we plant on ourselves
	local kTagColor      = Color3.fromRGB(160, 150, 255)  -- ghost-purple accent
	local kPeerColor     = Color3.fromRGB(80, 220, 140)   -- teal for same-script peers
	local kTagHeight     = 3.2   -- studs above HRP
	local kPeerHeight    = 4.5   -- a little higher so they don't overlap

	-- plant the signal on ourselves so others can detect us
	local signal = player:FindFirstChild(kPeerSignal)
	if not signal then
		signal = Instance.new("BoolValue")
		signal.Name  = kPeerSignal
		signal.Value = true
		signal.Parent = player
	end
	onUnload(function() if signal and signal.Parent then signal:Destroy() end end)

	-- ghost pixel art mini (2px scale) for the overhead tag
	local function makeOverheadGhost(parent)
		local root = Instance.new("Frame")
		root.Name = "OverheadGhost"
		root.BackgroundTransparency = 1
		root.BorderSizePixel = 0
		local px = 2
		root.Size = UDim2.fromOffset(kGhostW * px, kGhostH * px)
		root.AnchorPoint = Vector2.new(0.5, 1)
		root.Position = UDim2.new(0.5, 0, 0, 0)
		root.Parent = parent
		local pool = {}
		local function drawFrame(i)
			local runs = ghostFrames[i] or ghostFrames[1]
			for j, r in ipairs(runs) do
				local f = pool[j]
				if not f then
					f = Instance.new("Frame")
					f.BorderSizePixel = 0
					f.Parent = root
					pool[j] = f
				end
				f.Position = UDim2.fromOffset(r[1] * px, r[2] * px)
				f.Size     = UDim2.fromOffset(r[3] * px, px)
				f.BackgroundColor3 = ghostPalette[r[4]]
				f.Visible = true
			end
			for j = #runs + 1, #pool do pool[j].Visible = false end
		end
		drawFrame(1)
		-- animate
		task.spawn(function()
			local i = 1
			while root.Parent do
				drawFrame(i)
				i = i % #ghostFrames + 1
				task.wait(0.07)
			end
		end)
		return root
	end

	-- build a BillboardGui tag for a character
	local tagCache = {}

	local function buildTag(char, isPeer)
		-- remove any existing tag
		local old = char:FindFirstChild(kTagName)
		if old then old:Destroy() end

		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hrp then return end

		local bb = Instance.new("BillboardGui")
		bb.Name             = kTagName
		bb.Active           = false
		bb.AlwaysOnTop      = false
		bb.Size             = UDim2.fromOffset(160, 80)
		bb.StudsOffset      = Vector3.new(0, isPeer and kPeerHeight or kTagHeight, 0)
		bb.Adornee          = hrp
		bb.Parent           = char

		-- background pill
		local bg = Instance.new("Frame")
		bg.AnchorPoint = Vector2.new(0.5, 1)
		bg.Position    = UDim2.new(0.5, 0, 1, 0)
		bg.Size        = UDim2.fromOffset(140, 28)
		bg.BackgroundColor3 = Color3.fromRGB(16, 16, 22)
		bg.BackgroundTransparency = 0.25
		bg.BorderSizePixel = 0
		bg.Parent = bb
		addCorner(bg, -1)
		do
			local s = addStroke(bg, isPeer and kPeerColor or kTagColor, 1.5, 0)
			if not isPeer then bindAccent(s, "Color") end
		end

		-- label
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, 0, 1, 0)
		lbl.BackgroundTransparency = 1
		lbl.Text = isPeer and "🤝 Using Ghosted" or "👻 Ghosted Member"
		lbl.TextColor3 = isPeer and kPeerColor or kTagColor
		if not isPeer then
			accentCallbacks[#accentCallbacks + 1] = function(c) pcall(function() lbl.TextColor3 = c end) end
		end
		lbl.Font = Enum.Font.GothamBold
		lbl.TextSize = 11
		lbl.TextScaled = false
		lbl.Parent = bg

		-- ghost icon above the pill (only for our own tag, saves perf for peers)
		if not isPeer then
			local iconHolder = Instance.new("Frame")
			iconHolder.AnchorPoint = Vector2.new(0.5, 1)
			iconHolder.Position = UDim2.new(0.5, 0, 0, -2)
			iconHolder.Size = UDim2.fromOffset(kGhostW * 2, kGhostH * 2)
			iconHolder.BackgroundTransparency = 1
			iconHolder.BorderSizePixel = 0
			iconHolder.Parent = bb
			makeOverheadGhost(iconHolder)
		end

		return bb
	end

	-- apply tag to a player's current character
	local function applyTag(plr)
		if plr == player then
			-- tag ourselves
			local char = plr.Character
			if char then buildTag(char, false) end
			track(plr.CharacterAdded:Connect(function(c)
				task.wait(0.2)
				buildTag(c, false)
			end))
		else
			-- check if they're a peer
			local isPeer = plr:FindFirstChild(kPeerSignal) ~= nil
			local char = plr.Character
			if char then buildTag(char, isPeer) end
			track(plr.CharacterAdded:Connect(function(c)
				task.wait(0.2)
				local peer = plr:FindFirstChild(kPeerSignal) ~= nil
				buildTag(c, peer)
			end))
			-- if they load the script mid-session, rebuild their tag
			track(plr.ChildAdded:Connect(function(child)
				if child.Name == kPeerSignal then
					local c = plr.Character
					if c then buildTag(c, true) end
				end
			end))
		end
	end

	-- apply to all current players
	for _, plr in ipairs(Players:GetPlayers()) do
		applyTag(plr)
	end
	track(Players.PlayerAdded:Connect(applyTag))

	onUnload(function()
		-- remove all our tags
		for _, plr in ipairs(Players:GetPlayers()) do
			local char = plr.Character
			if char then
				local tag = char:FindFirstChild(kTagName)
				if tag then tag:Destroy() end
			end
		end
	end)
end

do
	local esp = { boxes = false, names = false, health = false, distance = false, tracers = false }
	local espCache  = {}
	local espMaxDist = kDefaultEspDist
	local espConn
	local chamsOn   = false
	local chamsMap  = {}

	local function killDrawing(d)
		if not d then return end
		if not pcall(function() d:Remove() end) then
			pcall(function() d:Destroy() end)
		end
	end

	local function newDrawing(kind, props)
		local d = Drawing.new(kind)
		for k, v in pairs(props) do d[k] = v end
		return d
	end

	local function createEspFor(plr)
		if espCache[plr] or plr == player then return end
		espCache[plr] = {
			box    = newDrawing("Square", { Thickness = 1.5, Color = kEspBoxColor, Filled = false, Visible = false }),
			name   = newDrawing("Text",   { Size = 14, Center = true, Outline = true, Color = kEspNameColor, Visible = false }),
			tracer = newDrawing("Line",   { Thickness = 1, Color = kTracerColor, Visible = false }),
			health = newDrawing("Line",   { Thickness = 2, Color = Color3.fromRGB(80, 255, 120), Visible = false }),
		}
	end

	local function removeEspFor(plr)
		local d = espCache[plr]
		if not d then return end
		killDrawing(d.box)
		killDrawing(d.name)
		killDrawing(d.tracer)
		killDrawing(d.health)
		espCache[plr] = nil
	end

	local function hideEsp(d)
		d.box.Visible    = false
		d.name.Visible   = false
		d.tracer.Visible = false
		d.health.Visible = false
	end

	local function sameTeam(plr)
		return espTeamCheck and plr.Team ~= nil and plr.Team == player.Team
	end

	local function renderEsp()
		local cam = workspace.CurrentCamera
		if not cam then return end
		local vp = cam.ViewportSize
		local origin = Vector2.new(vp.X / 2, vp.Y)

		for plr, d in pairs(espCache) do
			local char = plr.Character
			local hrp  = char and char:FindFirstChild("HumanoidRootPart")
			local hum  = char and char:FindFirstChildOfClass("Humanoid")

			if hrp and hum and hum.Health > 0 and not sameTeam(plr)
				and (hrp.Position - cam.CFrame.Position).Magnitude <= espMaxDist then
				local top, onScreen = cam:WorldToViewportPoint(hrp.Position + Vector3.new(0, 2.8, 0))
				local bottom        = cam:WorldToViewportPoint(hrp.Position - Vector3.new(0, 3.2, 0))

				if onScreen then
					local height = math.abs(bottom.Y - top.Y)
					local width  = height * 0.55
					local x      = top.X - width / 2
					local y      = math.min(top.Y, bottom.Y)

					d.box.Visible = esp.boxes
					if esp.boxes then
						d.box.Size     = Vector2.new(width, height)
						d.box.Position = Vector2.new(x, y)
					end

					if esp.names or esp.distance then
						local parts = {}
						if esp.names    then parts[#parts + 1] = plr.DisplayName end
						if esp.distance then
							parts[#parts + 1] = "[" .. math.floor((hrp.Position - cam.CFrame.Position).Magnitude) .. " st]"
						end
						d.name.Text     = table.concat(parts, " ")
						d.name.Position = Vector2.new(top.X, y - 16)
						d.name.Visible  = true
					else
						d.name.Visible = false
					end

					if esp.health then
						local maxHp = math.max(hum.MaxHealth, 1)
						local pct   = math.clamp(hum.Health / maxHp, 0, 1)
						d.health.From  = Vector2.new(x - 5, y + height)
						d.health.To    = Vector2.new(x - 5, y + height - height * pct)
						d.health.Color = Color3.fromRGB(255 * (1 - pct), 255 * pct, 60)
						d.health.Visible = true
					else
						d.health.Visible = false
					end

					if esp.tracers then
						d.tracer.From    = origin
						d.tracer.To      = Vector2.new(top.X, y + height)
						d.tracer.Visible = true
					else
						d.tracer.Visible = false
					end
				else
					hideEsp(d)
				end
			else
				hideEsp(d)
			end
		end
	end

	local function refreshEsp()
		local any = esp.boxes or esp.names or esp.health or esp.distance or esp.tracers
		if any and hasDrawing then
			if not espConn then
				for _, plr in ipairs(Players:GetPlayers()) do createEspFor(plr) end
				espConn = RunService.RenderStepped:Connect(renderEsp)
			end
		else
			disconnect(espConn)
			espConn = nil
			for plr in pairs(espCache) do removeEspFor(plr) end
		end
	end

	local function espCallback(flag)
		return function(on)
			if on and not hasDrawing then
				warn("[Ghosted Menu] No Drawing API, ESP overlays unavailable (Chams still work).")
			end
			esp[flag] = on
			refreshEsp()
		end
	end

	local function removeCham(plr)
		local h = chamsMap[plr]
		if h then h:Destroy(); chamsMap[plr] = nil end
	end

	local function applyCham(plr)
		if plr == player or not chamsOn then return end
		local char = plr.Character
		if not char or sameTeam(plr) then removeCham(plr); return end
		local h = chamsMap[plr]
		if not h then
			h = Instance.new("Highlight")
			h.Name               = plr.Name
			h.FillColor          = kChamsFill
			h.OutlineColor       = kChamsOutline
			h.FillTransparency   = 0.5
			h.OutlineTransparency = 0
			h.DepthMode          = Enum.HighlightDepthMode.AlwaysOnTop
			h.Parent             = chamsFolder
			chamsMap[plr]        = h
		end
		h.Adornee = char
	end

	local function setChams(on)
		chamsOn = on
		for _, plr in ipairs(Players:GetPlayers()) do
			if on then applyCham(plr) else removeCham(plr) end
		end
	end

	local function hookPlayer(plr)
		if plr == player then return end
		track(plr.CharacterAdded:Connect(function()
			task.wait(0.15)
			if chamsOn then applyCham(plr) end
		end))
	end
	for _, plr in ipairs(Players:GetPlayers()) do hookPlayer(plr) end

	track(Players.PlayerAdded:Connect(function(plr)
		hookPlayer(plr)
		if espConn then createEspFor(plr) end
		if chamsOn then applyCham(plr) end
	end))
	track(Players.PlayerRemoving:Connect(function(plr)
		removeEspFor(plr)
		removeCham(plr)
	end))

	makeToggleRow({ name = "Boxes",       desc = "Box around every player",           key = "espBoxes",    color = Color3.fromRGB(255,255,255), order = 1, parent = visualsPage, callback = espCallback("boxes")    })
	makeToggleRow({ name = "Names",       desc = "Display names above heads",          key = "espNames",    color = Color3.fromRGB(255,255,255), order = 2, parent = visualsPage, callback = espCallback("names")    })
	makeToggleRow({ name = "Health Bars", desc = "Bar to the left of the box",         key = "espHealth",   color = Color3.fromRGB( 80,255,120), order = 3, parent = visualsPage, callback = espCallback("health")   })
	makeToggleRow({ name = "Distance",    desc = "Studs away, shown with the name",    key = "espDistance", color = Color3.fromRGB(255,200, 90), order = 4, parent = visualsPage, callback = espCallback("distance") })
	makeToggleRow({ name = "Tracers",     desc = "Line from bottom-center to player",  key = "espTracers",  color = Color3.fromRGB(110,110,255), order = 5, parent = visualsPage, callback = espCallback("tracers")  })
	makeToggleRow({ name = "Chams",       desc = "Highlight players through walls",    key = "chams",       color = Color3.fromRGB(255, 70, 90), order = 6, parent = visualsPage, callback = setChams               })
	makeToggleRow({ name = "Team Check",  desc = "Skip your own teammates",            key = "teamCheck",   color = Color3.fromRGB( 90,200,255), order = 7, parent = visualsPage,
		callback = function(on)
			espTeamCheck = on
			if chamsOn then
				for _, plr in ipairs(Players:GetPlayers()) do
					removeCham(plr)
					applyCham(plr)
				end
			end
		end })
	makeSliderRow({
		name = "ESP Max Distance", key = "espDist", min = 100, max = 5000, default = kDefaultEspDist,
		order = 8, parent = visualsPage, callback = function(v) espMaxDist = v end,
	})
end

makeSection("WORLD", 9, visualsPage)

-- FULLBRIGHT
do
	local fbConn
	local saved

	local function setFullbright(on)
		disconnect(fbConn)
		fbConn = nil
		if on then
			saved = {
				Brightness     = Lighting.Brightness,
				ClockTime      = Lighting.ClockTime,
				FogEnd         = Lighting.FogEnd,
				GlobalShadows  = Lighting.GlobalShadows,
				Ambient        = Lighting.Ambient,
				OutdoorAmbient = Lighting.OutdoorAmbient,
			}
			fbConn = RunService.RenderStepped:Connect(function()
				Lighting.Brightness     = 2
				Lighting.ClockTime      = 14
				Lighting.FogEnd         = 1e5
				Lighting.GlobalShadows  = false
				Lighting.Ambient        = Color3.fromRGB(178, 178, 178)
				Lighting.OutdoorAmbient = Color3.fromRGB(178, 178, 178)
			end)
		elseif saved then
			for k, v in pairs(saved) do pcall(function() Lighting[k] = v end) end
			saved = nil
		end
	end

	makeToggleRow({
		name = "Fullbright", desc = "Removes darkness and fog",
		key = "fullbright", color = Color3.fromRGB(255,240,150), order = 10, parent = visualsPage, callback = setFullbright,
	})
end

makeSliderRow({
	name = "Field of View", key = "fov", min = 30, max = 120, default = math.floor(origFov + 0.5),
	order = 11, parent = visualsPage,
	callback = function(v)
		local cam = workspace.CurrentCamera
		if cam then cam.FieldOfView = v end
	end,
})

-- CROSSHAIR
do
	local crossGui = Instance.new("ScreenGui")
	crossGui.Name = "GhostedCrosshair"
	crossGui.ResetOnSpawn = false
	crossGui.IgnoreGuiInset = true
	crossGui.DisplayOrder = 998
	crossGui.Parent = guiParent

	local holder = Instance.new("Frame")
	holder.Size = UDim2.new(1, 0, 1, 0)
	holder.BackgroundTransparency = 1
	holder.Visible = false
	holder.Parent = crossGui

	local function bar(x, y, w, h)
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.new(0.5, x, 0.5, y)
		f.Size = UDim2.fromOffset(w, h)
		f.BorderSizePixel = 0
		f.Parent = holder
		bindAccent(f, "BackgroundColor3")
	end
	bar(0, -9, 2, 7)
	bar(0,  9, 2, 7)
	bar(-9, 0, 7, 2)
	bar( 9, 0, 7, 2)
	bar(0,  0, 2, 2)

	onUnload(function() crossGui:Destroy() end)

	makeToggleRow({
		name = "Crosshair", desc = "Accent colored dot-cross at screen center",
		key = "crosshair", color = Color3.fromRGB(255,120,120), order = 12, parent = visualsPage,
		callback = function(on) holder.Visible = on end,
	})
end

-- CUSTOM TIME
do
	local timeVal = 14
	local timeConn, savedTime
	local function setCustomTime(on)
		disconnect(timeConn)
		timeConn = nil
		if on then
			if savedTime == nil then savedTime = Lighting.ClockTime end
			timeConn = RunService.RenderStepped:Connect(function()
				Lighting.ClockTime = timeVal
			end)
		elseif savedTime ~= nil then
			Lighting.ClockTime = savedTime
			savedTime = nil
		end
	end
	makeToggleRow({
		name = "Custom Time", desc = "Locks the time of day (slider below)",
		key = "customTime", color = Color3.fromRGB(255,190,90), order = 13, parent = visualsPage, callback = setCustomTime,
	})
	makeSliderRow({
		name = "Time of Day", key = "timeOfDay", min = 0, max = 24, default = 14,
		order = 14, parent = visualsPage, callback = function(v) timeVal = v end,
	})
end

-- CAMERA ZOOM LIMIT
do
	local origMax = player.CameraMaxZoomDistance
	makeSliderRow({
		name = "Max Zoom", key = "maxZoom", min = 10, max = 1000,
		default = math.clamp(math.floor(origMax + 0.5), 10, 1000),
		order = 15, parent = visualsPage,
		callback = function(v) player.CameraMaxZoomDistance = v end,
	})
	onUnload(function() player.CameraMaxZoomDistance = origMax end)
end

----------------------------------------------------------------
-- PLAYERS TAB
----------------------------------------------------------------
do
	local searchRow = Instance.new("Frame")
	searchRow.Size = UDim2.new(1, 0, 0, 38)
	searchRow.BackgroundColor3 = kRowBg
	searchRow.LayoutOrder = 1
	searchRow.Parent = playersPage
	addCorner(searchRow, 8)

	local search = Instance.new("TextBox")
	search.Size = UDim2.new(1, -24, 1, 0)
	search.Position = UDim2.new(0, 12, 0, 0)
	search.BackgroundTransparency = 1
	search.PlaceholderText = "search players..."
	search.PlaceholderColor3 = kTextDim
	search.Text = ""
	search.TextColor3 = Color3.fromRGB(230, 230, 235)
	search.Font = Enum.Font.Gotham
	search.TextSize = 14
	search.TextXAlignment = Enum.TextXAlignment.Left
	search.ClearTextOnFocus = false
	search.Parent = searchRow

	local viewing, viewConn
	local stopBtn

	local function stopViewing()
		disconnect(viewConn)
		viewConn = nil
		viewing = nil
		local cam = workspace.CurrentCamera
		local hum = getHumanoid()
		if cam and hum then cam.CameraSubject = hum end
		if stopBtn then stopBtn.Visible = false end
	end

	local function startViewing(plr)
		stopViewing()
		viewing = plr
		stopBtn.Text = "Stop Viewing " .. plr.DisplayName
		stopBtn.Visible = true
		viewConn = RunService.RenderStepped:Connect(function()
			local cam  = workspace.CurrentCamera
			local char = viewing and viewing.Character
			local hum  = char and char:FindFirstChildOfClass("Humanoid")
			if cam and hum and cam.CameraSubject ~= hum then cam.CameraSubject = hum end
		end)
		notify("Viewing " .. plr.DisplayName)
	end

	stopBtn = makeButtonRow({
		text = "Stop Viewing", order = 2, parent = playersPage,
		callback = function() stopViewing() end,
	})
	stopBtn.Visible = false
	onUnload(stopViewing)

	local header = makeSection("PLAYERS", 3, playersPage)

	local function teleportTo(plr)
		local myChar = player.Character
		local hrp    = myChar and myChar:FindFirstChild("HumanoidRootPart")
		local tChar  = plr.Character
		local tHrp   = tChar and tChar:FindFirstChild("HumanoidRootPart")
		if hrp and tHrp then
			hrp.CFrame = tHrp.CFrame * CFrame.new(0, 0, 3)
			notify("Teleported to " .. plr.DisplayName)
		else
			notify("No character to teleport to")
		end
	end

	local function smallButton(parent, text, xOff, onClick)
		local b = Instance.new("TextButton")
		b.AnchorPoint = Vector2.new(1, 0.5)
		b.Position = UDim2.new(1, xOff, 0.5, 0)
		b.Size = UDim2.new(0, 46, 0, 26)
		b.BackgroundColor3 = accent
		b.Text = text
		b.TextColor3 = Color3.new(1, 1, 1)
		b.Font = Enum.Font.GothamBold
		b.TextSize = 11
		b.AutoButtonColor = false
		b.Parent = parent
		addCorner(b, 6)
		track(b.MouseButton1Click:Connect(onClick))
		accentCallbacks[#accentCallbacks + 1] = function(c) b.BackgroundColor3 = c end
		return b
	end

	local rows = {}
	local function refreshPlayers()
		for _, r in ipairs(rows) do r:Destroy() end
		rows = {}

		local q = string.lower(search.Text or "")
		local list = Players:GetPlayers()
		table.sort(list, function(a, b)
			return string.lower(a.DisplayName) < string.lower(b.DisplayName)
		end)

		local shown = 0
		for _, plr in ipairs(list) do
			local match = q == ""
				or string.find(string.lower(plr.DisplayName), q, 1, true)
				or string.find(string.lower(plr.Name),        q, 1, true)
			if plr ~= player and match then
				shown = shown + 1

				local row = Instance.new("Frame")
				row.Size = UDim2.new(1, 0, 0, 46)
				row.BackgroundColor3 = kRowBg
				row.LayoutOrder = 10 + shown
				row.Parent = playersPage
				addCorner(row, 8)
				rows[#rows + 1] = row

				local nameLbl = Instance.new("TextLabel")
				nameLbl.Size = UDim2.new(1, -220, 0, 18)
				nameLbl.Position = UDim2.new(0, 16, 0, 5)
				nameLbl.BackgroundTransparency = 1
				nameLbl.Text = plr.DisplayName
				nameLbl.TextColor3 = Color3.fromRGB(230, 230, 235)
				nameLbl.Font = Enum.Font.GothamBold
				nameLbl.TextSize = 14
				nameLbl.TextXAlignment = Enum.TextXAlignment.Left
				nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
				nameLbl.Parent = row

				local subLbl = Instance.new("TextLabel")
				subLbl.Size = UDim2.new(1, -220, 0, 14)
				subLbl.Position = UDim2.new(0, 16, 0, 25)
				subLbl.BackgroundTransparency = 1
				subLbl.Text = "@" .. plr.Name
				subLbl.TextColor3 = kTextDim
				subLbl.Font = Enum.Font.Gotham
				subLbl.TextSize = 11
				subLbl.TextXAlignment = Enum.TextXAlignment.Left
				subLbl.TextTruncate = Enum.TextTruncate.AtEnd
				subLbl.Parent = row

				-- team color dot
				local teamDot = Instance.new("Frame")
				teamDot.AnchorPoint = Vector2.new(0, 0.5)
				teamDot.Position = UDim2.new(0, 0, 0.5, 0)
				teamDot.Size = UDim2.fromOffset(5, 5)
				teamDot.BorderSizePixel = 0
				teamDot.BackgroundColor3 = (plr.Team and plr.Team.TeamColor and plr.Team.TeamColor.Color) or Color3.fromRGB(80, 80, 100)
				teamDot.Parent = row
				addCorner(teamDot, -1)
				-- listen for team change
				track(plr:GetPropertyChangedSignal("Team"):Connect(function()
					teamDot.BackgroundColor3 = (plr.Team and plr.Team.TeamColor and plr.Team.TeamColor.Color) or Color3.fromRGB(80, 80, 100)
				end))

				-- buttons: Brick / Fling / View / TP / Copy
				smallButton(row, "Copy",  -10,  function()
					local ok = pcall(function()
						if setclipboard then setclipboard(plr.Name)
						elseif toclipboard then toclipboard(plr.Name)
						else error("no clipboard") end
					end)
					notify(ok and ("Copied @" .. plr.Name) or "Clipboard unavailable")
				end)
				smallButton(row, "Fling", -62,  function() flingPlayer(plr) end)
				smallButton(row, "View",  -114, function() startViewing(plr) end)
				smallButton(row, "TP",    -166, function() teleportTo(plr) end)
			end
		end
		header.Text = "PLAYERS (" .. shown .. ")"
	end

	track(search:GetPropertyChangedSignal("Text"):Connect(refreshPlayers))
	track(Players.PlayerAdded:Connect(function() task.defer(refreshPlayers) end))
	track(Players.PlayerRemoving:Connect(function(plr)
		if viewing == plr then stopViewing() end
		task.defer(refreshPlayers)
	end))
	accentCallbacks[#accentCallbacks + 1] = function() refreshPlayers() end
	refreshPlayers()
end

----------------------------------------------------------------
-- MISC TAB
----------------------------------------------------------------
makeSection("UTILITY", 0, miscPage)

-- ANTI-AFK
do
	local afkConn
	local function setAntiAfk(on)
		disconnect(afkConn)
		afkConn = nil
		if on then
			afkConn = player.Idled:Connect(function()
				local vu = game:GetService("VirtualUser")
				vu:CaptureController()
				vu:ClickButton2(Vector2.new(0, 0))
			end)
		end
	end
	makeToggleRow({
		name = "Anti-AFK", desc = "Stops the 20-minute idle kick",
		key = "antiafk", color = Color3.fromRGB(90, 230, 150), order = 1, parent = miscPage, callback = setAntiAfk,
	})
end

-- CLICK TELEPORT
do
	local beginConn, endConn
	local touches = setmetatable({}, { __mode = "k" })

	local function teleportToRay(ray)
		local char = player.Character
		local hrp  = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then return end
		local params = RaycastParams.new()
		params.FilterDescendantsInstances = { char }
		params.FilterType = Enum.RaycastFilterType.Exclude
		local hit = workspace:Raycast(ray.Origin, ray.Direction * 2000, params)
		if hit then
			hrp.CFrame = CFrame.new(hit.Position + Vector3.new(0, kClickTpHeight, 0))
		end
	end

	local function setClickTp(on)
		disconnect(beginConn)
		disconnect(endConn)
		beginConn, endConn = nil, nil
		if not on then return end

		beginConn = UserInputService.InputBegan:Connect(function(input, processed)
			if processed then return end
			local cam = workspace.CurrentCamera
			if not cam then return end
			if input.UserInputType == Enum.UserInputType.MouseButton1
				and UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
				local loc = UserInputService:GetMouseLocation()
				teleportToRay(cam:ViewportPointToRay(loc.X, loc.Y))
			elseif input.UserInputType == Enum.UserInputType.Touch then
				touches[input] = { pos = input.Position, t = os.clock() }
			end
		end)

		endConn = UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.Touch then return end
			local rec = touches[input]
			touches[input] = nil
			local cam = workspace.CurrentCamera
			if rec and cam and (input.Position - rec.pos).Magnitude < 12 and os.clock() - rec.t < 0.25 then
				teleportToRay(cam:ScreenPointToRay(input.Position.X, input.Position.Y))
			end
		end)
	end

	makeToggleRow({
		name = "Click Teleport", desc = "Ctrl+click (PC) or quick tap (mobile)",
		key = "clicktp", color = Color3.fromRGB(180,130,255), order = 2, parent = miscPage, callback = setClickTp,
	})
end

-- STATS HUD
do
	local statsFrame = Instance.new("Frame")
	statsFrame.Name = "StatsHud"
	statsFrame.AnchorPoint = Vector2.new(0.5, 0)
	statsFrame.Position = UDim2.new(0.5, 0, 0, 8)
	statsFrame.Size = UDim2.new(0, 260, 0, 28)
	statsFrame.BackgroundColor3 = Color3.fromRGB(16, 16, 22)
	statsFrame.BackgroundTransparency = 0.15
	statsFrame.BorderSizePixel = 0
	statsFrame.Visible = false
	statsFrame.Parent = screenGui
	addCorner(statsFrame, -1)
	do
		local s = addStroke(statsFrame, accent, 1, 0.6)
		bindAccent(s, "Color")
	end

	local statsLabel = Instance.new("TextLabel")
	statsLabel.Size = UDim2.new(1, -12, 1, 0)
	statsLabel.Position = UDim2.new(0, 6, 0, 0)
	statsLabel.BackgroundTransparency = 1
	statsLabel.TextColor3 = Color3.new(1, 1, 1)
	statsLabel.Font = Enum.Font.GothamBold
	statsLabel.TextSize = 13
	statsLabel.Text = "-- FPS  |  -- ms  |  0s"
	statsLabel.RichText = true
	statsLabel.Parent = statsFrame

	local statsConn
	local serverStart = os.clock()
	local function setStats(on)
		disconnect(statsConn)
		statsConn = nil
		statsFrame.Visible = on
		serverStart = os.clock()
		if on then
			local frames, acc = 0, 0
			statsConn = RunService.Heartbeat:Connect(function(dt)
				frames = frames + 1
				acc = acc + dt
				if acc >= 0.5 then
					local fps  = math.floor(frames / acc + 0.5)
					local ping = 0
					pcall(function()
						ping = math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue() + 0.5)
					end)
					-- FIX: color-code ping
					local pingColor = (ping < 80) and "#50e880" or (ping < 150) and "#f5c842" or "#ff5050"
					-- uptime
					local upSec = math.floor(os.clock() - serverStart)
					local upStr = (upSec >= 60)
						and (math.floor(upSec/60) .. "m " .. (upSec%60) .. "s")
						or  (upSec .. "s")
					-- fps color
					local fpsColor = (fps >= 55) and "#50e880" or (fps >= 30) and "#f5c842" or "#ff5050"
					statsLabel.Text = string.format(
						'<font color="%s">%d FPS</font>  |  <font color="%s">%d ms</font>  |  ⏱ %s',
						fpsColor, fps, pingColor, ping, upStr
					)
					frames, acc = 0, 0
				end
			end)
		end
	end

	makeToggleRow({
		name = "Stats HUD", desc = "FPS and ping at the top of the screen",
		key = "stats", color = Color3.fromRGB(90,200,255), order = 3, parent = miscPage, callback = setStats,
	})
end

-- ANTI-VOID (fixed: was saving while airborne due to inverted floor check)
do
	local voidConn, lastSafe
	local function setAntiVoid(on)
		disconnect(voidConn)
		voidConn = nil
		lastSafe = nil
		if not on then return end
		voidConn = RunService.Heartbeat:Connect(function()
			local char = player.Character
			local hrp  = char and char:FindFirstChild("HumanoidRootPart")
			if not hrp then return end
			local floorY = workspace.FallenPartsDestroyHeight
			if hrp.Position.Y > floorY + 60 then
				-- only save when actually on the ground (FloorMaterial ~= Air means standing)
				local hum = char:FindFirstChildOfClass("Humanoid")
				if hum and hum.FloorMaterial ~= Enum.Material.Air then
					lastSafe = hrp.CFrame
				end
			elseif lastSafe then
				hrp.AssemblyLinearVelocity = Vector3.zero
				hrp.CFrame = lastSafe + Vector3.new(0, 3, 0)
			end
		end)
	end
	makeToggleRow({
		name = "Anti-Void", desc = "Saves you from falling out of the map",
		key = "antivoid", color = Color3.fromRGB(255,120,150), order = 4, parent = miscPage, callback = setAntiVoid,
	})
end

-- GOD MODE
do
	local godConn
	local function setGodMode(on)
		disconnect(godConn)
		godConn = nil
		if not on then return end
		godConn = RunService.Heartbeat:Connect(function()
			local hum = getHumanoid()
			if hum then
				pcall(function()
					if hum.MaxHealth ~= math.huge then hum.MaxHealth = math.huge end
					if hum.Health ~= math.huge then hum.Health = math.huge end
				end)
			end
		end)
	end
	makeToggleRow({
		name = "God Mode", desc = "Sets health to infinite every frame",
		key = "godmode", color = Color3.fromRGB(255, 215, 50), order = 5, parent = miscPage, callback = setGodMode,
	})
end

-- FREEZE (anchors HRP in place)
do
	local frozenCF, freezeConn
	local function setFreeze(on)
		disconnect(freezeConn)
		freezeConn = nil
		if on then
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if hrp then
				frozenCF = hrp.CFrame
				freezeConn = RunService.Heartbeat:Connect(function()
					local h = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
					if h and frozenCF then
						h.AssemblyLinearVelocity = Vector3.zero
						h.CFrame = frozenCF
					end
				end)
			end
		else
			frozenCF = nil
		end
	end
	makeToggleRow({
		name = "Freeze", desc = "Lock your character in place",
		key = "freeze", color = Color3.fromRGB(130, 200, 255), order = 5, parent = miscPage, callback = setFreeze,
	})
end

-- FPS CAP
do
	local touched = false
	makeSliderRow({
		name = "FPS Cap", key = "fpsCap", min = 30, max = 360, default = 60,
		order = 6, parent = miscPage,
		callback = function(v)
			touched = true
			if typeof(setfpscap) == "function" then pcall(setfpscap, v) end
		end,
	})
	onUnload(function()
		if touched and typeof(setfpscap) == "function" then pcall(setfpscap, 60) end
	end)
end

makeSection("SERVER", 8, miscPage)

local function copyText(text, label)
	local ok = pcall(function()
		if setclipboard then setclipboard(text)
		elseif toclipboard then toclipboard(text)
		else error("no clipboard api") end
	end)
	notify(ok and (label .. " copied") or "Clipboard not supported here")
end

-- FLING POWER (shared with Players tab)
makeSection("FLING", 20, miscPage)
makeSliderRow({
	name = "Fling Power", key = "flingPower", min = 500, max = 50000, default = kDefaultFlingPower,
	order = 21, parent = miscPage,
	callback = function(v) flingPower = v end,
})

-- SERVER HOP
do
	local busy = false
	makeButtonRow({
		text = "Server Hop", order = 8, parent = miscPage,
		callback = function()
			if busy then return end
			busy = true
			notify("Searching for a server...")
			task.spawn(function()
				local picked
				local ok, body = pcall(function()
					return game:HttpGet("https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100")
				end)
				if ok and type(body) == "string" then
					local okJ, data = pcall(function() return HttpService:JSONDecode(body) end)
					if okJ and type(data) == "table" and type(data.data) == "table" then
						local candidates = {}
						for _, srv in ipairs(data.data) do
							if srv.id ~= game.JobId and type(srv.playing) == "number"
								and type(srv.maxPlayers) == "number" and srv.playing < srv.maxPlayers - 1 then
								candidates[#candidates + 1] = srv.id
							end
						end
						if #candidates > 0 then picked = candidates[math.random(1, #candidates)] end
					end
				end
				if picked then
					notify("Hopping...")
					pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, picked, player) end)
				else
					notify("No server found (executor needs HttpGet)")
				end
				task.wait(2)
				busy = false
			end)
		end,
	})
end

makeButtonRow({ text = "Rejoin This Server", order = 7, parent = miscPage,
	callback = function()
		notify("Rejoining...")
		local ok = pcall(function()
			TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, player)
		end)
		if not ok then pcall(function() TeleportService:Teleport(game.PlaceId, player) end) end
	end,
})
makeButtonRow({ text = "Copy Job ID",       order = 9,  parent = miscPage, callback = function() copyText(game.JobId, "Job ID") end })
makeButtonRow({ text = "Copy Place ID",     order = 10, parent = miscPage, callback = function() copyText(tostring(game.PlaceId), "Place ID") end })
makeButtonRow({ text = "Reset Character",   order = 11, parent = miscPage,
	callback = function()
		local hum = getHumanoid()
		if hum then hum.Health = 0 end
	end,
})

-- TELEPORT TO COORDS
do
	local coordPopup = Instance.new("Frame")
	coordPopup.Name = "CoordPopup"
	coordPopup.AnchorPoint = Vector2.new(0.5, 0.5)
	coordPopup.Position = UDim2.new(0.5, 0, 0.5, 0)
	coordPopup.Size = UDim2.fromOffset(260, 120)
	coordPopup.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
	coordPopup.BorderSizePixel = 0
	coordPopup.ZIndex = 200
	coordPopup.Visible = false
	coordPopup.Parent = screenGui
	addCorner(coordPopup, 10)
	do
		local s = addStroke(coordPopup, accent, 1.5, 0)
		bindAccent(s, "Color")
	end

	local coordTitle = Instance.new("TextLabel")
	coordTitle.Size = UDim2.new(1, -16, 0, 28)
	coordTitle.Position = UDim2.new(0, 8, 0, 6)
	coordTitle.BackgroundTransparency = 1
	coordTitle.Text = "Teleport to Coords"
	coordTitle.TextColor3 = Color3.new(1,1,1)
	coordTitle.Font = Enum.Font.GothamBold
	coordTitle.TextSize = 14
	coordTitle.TextXAlignment = Enum.TextXAlignment.Left
	coordTitle.ZIndex = 201
	coordTitle.Parent = coordPopup

	local function makeCoordBox(label, xOff)
		local box = Instance.new("TextBox")
		box.Size = UDim2.fromOffset(70, 28)
		box.Position = UDim2.new(0, xOff, 0, 38)
		box.BackgroundColor3 = Color3.fromRGB(30, 30, 42)
		box.TextColor3 = Color3.new(1,1,1)
		box.PlaceholderText = label
		box.PlaceholderColor3 = kTextDim
		box.Text = "0"
		box.Font = Enum.Font.Gotham
		box.TextSize = 13
		box.ClearTextOnFocus = false
		box.ZIndex = 201
		box.Parent = coordPopup
		addCorner(box, 6)
		addStroke(box, Color3.fromRGB(60,60,80), 1, 0)
		return box
	end
	local boxX = makeCoordBox("X", 10)
	local boxY = makeCoordBox("Y", 96)
	local boxZ = makeCoordBox("Z", 182)

	local function closePopup() coordPopup.Visible = false end

	local tpBtn = Instance.new("TextButton")
	tpBtn.Size = UDim2.new(1, -20, 0, 28)
	tpBtn.Position = UDim2.new(0, 10, 0, 78)
	tpBtn.BackgroundColor3 = accent
	tpBtn.Text = "Go"
	tpBtn.TextColor3 = Color3.new(1,1,1)
	tpBtn.Font = Enum.Font.GothamBold
	tpBtn.TextSize = 13
	tpBtn.AutoButtonColor = false
	tpBtn.ZIndex = 201
	tpBtn.Parent = coordPopup
	addCorner(tpBtn, 6)
	bindAccent(tpBtn, "BackgroundColor3")
	track(tpBtn.MouseButton1Click:Connect(function()
		local x = tonumber(boxX.Text)
		local y = tonumber(boxY.Text)
		local z = tonumber(boxZ.Text)
		if x and y and z then
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if hrp then
				hrp.CFrame = CFrame.new(x, y, z)
				notify(string.format("TP → (%.0f, %.0f, %.0f)", x, y, z))
				closePopup()
			else
				notify("No character")
			end
		else
			notify("Invalid coords")
		end
	end))

	-- cancel on click outside
	track(UserInputService.InputBegan:Connect(function(input)
		if coordPopup.Visible and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
			-- simple: close if click not inside popup
			local abs = coordPopup.AbsolutePosition
			local sz  = coordPopup.AbsoluteSize
			local pos = input.Position
			if pos.X < abs.X or pos.X > abs.X + sz.X or pos.Y < abs.Y or pos.Y > abs.Y + sz.Y then
				closePopup()
			end
		end
	end))
	onUnload(function() coordPopup:Destroy() end)

	makeButtonRow({ text = "Teleport to Coords", order = 12, parent = miscPage,
		callback = function()
			-- pre-fill with current position
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if hrp then
				local p = hrp.Position
				boxX.Text = tostring(math.floor(p.X + 0.5))
				boxY.Text = tostring(math.floor(p.Y + 0.5))
				boxZ.Text = tostring(math.floor(p.Z + 0.5))
			end
			coordPopup.Visible = true
		end,
	})
end

----------------------------------------------------------------
-- COMBAT (Aimbot / Triggerbot)
----------------------------------------------------------------
makeSection("COMBAT", 30, miscPage)

do
	-- ============ CONFIG ============
	local kAimKey        = Enum.KeyCode.E
	local kDefaultFovPx  = 150
	local kDefaultSmooth = 0.25     -- 0 = instant snap, 1 = never arrives
	local kTriggerMs     = 80
	local kAimBone       = "Head"

	local aimbotOn     = false
	local triggerbotOn = false
	local aimFovPx     = kDefaultFovPx
	local aimSmooth    = kDefaultSmooth
	local useCameraAim = true       -- camera-lock vs mouse-move (toggle row reads saved state; default ON)
	local showFov      = true       -- FIX: was always false on load if not saved; default ON

	local aimConn, triggerConn
	local lastTrigger  = 0
	local savedCamType = nil
	local fovGui, fovFrame, fovStroke

	-- ============ FOV CIRCLE (pure GUI, no Drawing) ============
	do
		fovGui = Instance.new("ScreenGui")
		fovGui.Name = "GhostedAimFov"
		fovGui.ResetOnSpawn = false
		fovGui.IgnoreGuiInset = true
		fovGui.DisplayOrder = 997
		fovGui.Parent = guiParent

		fovFrame = Instance.new("Frame")
		fovFrame.AnchorPoint = Vector2.new(0.5, 0.5)
		fovFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
		fovFrame.BackgroundTransparency = 1
		fovFrame.BorderSizePixel = 0
		fovFrame.Size = UDim2.fromOffset(aimFovPx * 2, aimFovPx * 2)
		fovFrame.Visible = false
		fovFrame.Parent = fovGui
		addCorner(fovFrame, -1)
		fovStroke = addStroke(fovFrame, accent, 1, 0.5)
		bindAccent(fovStroke, "Color")

		onUnload(function() fovGui:Destroy() end)
	end

	local function syncFovCircle()
		if not fovFrame then return end
		fovFrame.Size = UDim2.fromOffset(aimFovPx * 2, aimFovPx * 2)
		fovFrame.Visible = aimbotOn and showFov
	end

	-- ============ TARGET PICKING ============
	local function getBestTarget()
		local cam = workspace.CurrentCamera
		if not cam then return nil, nil, nil end
		local vp     = cam.ViewportSize
		local center = Vector2.new(vp.X / 2, vp.Y / 2)

		local best, bestDist, bestPos = nil, math.huge, nil

		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= player then
				local skip = false
				if espTeamCheck and plr.Team ~= nil and plr.Team == player.Team then
					skip = true
				end
				if not skip then
					local char = plr.Character
					local hum  = char and char:FindFirstChildOfClass("Humanoid")
					local bone = char and (char:FindFirstChild(kAimBone) or char:FindFirstChild("HumanoidRootPart"))
					if hum and hum.Health > 0 and bone then
						local sp, onScreen = cam:WorldToViewportPoint(bone.Position)
						if onScreen then
							local d = (Vector2.new(sp.X, sp.Y) - center).Magnitude
							if d <= aimFovPx and d < bestDist then
								best, bestDist, bestPos = plr, d, bone.Position
							end
						end
					end
				end
			end
		end
		return best, bestPos, bestDist
	end

	-- ============ AIM LOGIC ============
	local function setAimbot(on)
		aimbotOn = on
		disconnect(aimConn)
		aimConn = nil

		if not on then
			-- restore camera type if we hijacked it
			if savedCamType ~= nil then
				local cam = workspace.CurrentCamera
				if cam then cam.CameraType = savedCamType end
				savedCamType = nil
			end
			syncFovCircle()
			return
		end
		syncFovCircle()

		aimConn = RunService.RenderStepped:Connect(function()
			if UserInputService:GetFocusedTextBox() then return end
			if not UserInputService:IsKeyDown(kAimKey) then
				-- release: restore camera type
				if savedCamType ~= nil then
					local cam = workspace.CurrentCamera
					if cam then cam.CameraType = savedCamType end
					savedCamType = nil
				end
				return
			end

			local cam = workspace.CurrentCamera
			if not cam then return end

			local _, targetPos = getBestTarget()
			if not targetPos then return end

			if useCameraAim then
				-- camera-lock: rotate the camera CFrame toward the target
				if savedCamType == nil and cam.CameraType ~= Enum.CameraType.Scriptable then
					savedCamType = cam.CameraType
				end
				cam.CameraType = Enum.CameraType.Scriptable

				local origin = cam.CFrame.Position
				local goal   = CFrame.new(origin, targetPos)
				local t      = 1 - aimSmooth
				cam.CFrame   = cam.CFrame:Lerp(goal, math.clamp(t, 0.02, 1))
			else
				-- mouse-move fallback (executor-dependent)
				local vp     = cam.ViewportSize
				local center = Vector2.new(vp.X / 2, vp.Y / 2)
				local sp     = cam:WorldToViewportPoint(targetPos)
				local delta  = (Vector2.new(sp.X, sp.Y) - center) * (1 - aimSmooth)
				if typeof(mousemoverel) == "function" then
					pcall(mousemoverel, math.floor(delta.X + 0.5), math.floor(delta.Y + 0.5))
				end
			end
		end)
	end

	-- ============ TRIGGERBOT ============
	local function fireClick(vp)
		-- Most reliable across executors:
		local ok = pcall(function()
			local vu = game:GetService("VirtualUser")
			vu:CaptureController()
			vu:ClickButton1(Vector2.new(vp.X / 2, vp.Y / 2))
		end)
		if ok then return end

		-- Fallbacks
		if typeof(mouse1click) == "function" then
			pcall(mouse1click)
			return
		end
		if typeof(mouse1press) == "function" and typeof(mouse1release) == "function" then
			pcall(mouse1press)
			task.delay(0.05, function() pcall(mouse1release) end)
			return
		end
		pcall(function()
			local vim = game:GetService("VirtualInputManager")
			vim:SendMouseButtonEvent(vp.X / 2, vp.Y / 2, 0, true,  game, 1)
			task.delay(0.05, function()
				vim:SendMouseButtonEvent(vp.X / 2, vp.Y / 2, 0, false, game, 1)
			end)
		end)
	end

	local function setTriggerbot(on)
		triggerbotOn = on
		disconnect(triggerConn)
		triggerConn = nil
		if not on then return end

		triggerConn = RunService.Heartbeat:Connect(function()
			if not triggerbotOn then return end
			if UserInputService:GetFocusedTextBox() then return end
			local now = os.clock() * 1000
			if now - lastTrigger < kTriggerMs then return end

			local cam = workspace.CurrentCamera
			if not cam then return end
			local vp     = cam.ViewportSize
			local center = Vector2.new(vp.X / 2, vp.Y / 2)

			for _, plr in ipairs(Players:GetPlayers()) do
				if plr ~= player then
					local skip = espTeamCheck and plr.Team ~= nil and plr.Team == player.Team
					if not skip then
						local char = plr.Character
						local hum  = char and char:FindFirstChildOfClass("Humanoid")
						local hrp  = char and char:FindFirstChild("HumanoidRootPart")
						if hum and hum.Health > 0 and hrp then
							local sp, onScreen = cam:WorldToViewportPoint(hrp.Position)
							if onScreen and (Vector2.new(sp.X, sp.Y) - center).Magnitude < 30 then
								lastTrigger = now
								fireClick(vp)
								break
							end
						end
					end
				end
			end
		end)
	end

	onUnload(function()
		disconnect(aimConn)
		disconnect(triggerConn)
		if savedCamType ~= nil then
			local cam = workspace.CurrentCamera
			if cam then cam.CameraType = savedCamType end
			savedCamType = nil
		end
	end)

	-- ============ UI ============
	makeToggleRow({
		name     = "Aimbot",
		desc     = "Hold E to aim (camera-lock)",
		key      = "aimbot",
		color    = Color3.fromRGB(255, 80, 80),
		order    = 31,
		parent   = miscPage,
		callback = setAimbot,
	})
	makeToggleRow({
		name     = "Triggerbot",
		desc     = "Auto-click when crosshair is on a player",
		key      = "triggerbot",
		color    = Color3.fromRGB(255, 150, 60),
		order    = 32,
		parent   = miscPage,
		callback = setTriggerbot,
	})
	-- FIX: useCameraAim defaults to true, so we default this toggle ON
	-- The toggle row restores saved state, but if no saved state exists it starts OFF → mismatch fixed by
	-- passing the initial callback after build
	local _, setCamAimToggle = makeToggleRow({
		name     = "Camera Aim Mode",
		desc     = "ON = rotate camera. OFF = move mouse (executor dependent)",
		key      = "aimCamMode",
		color    = Color3.fromRGB(255, 80, 80),
		order    = 33,
		parent   = miscPage,
		callback = function(on) useCameraAim = on end,
	})
	-- if no saved preference, default it ON to match useCameraAim=true
	if settings.toggles["aimCamMode"] == nil then
		task.defer(function() if setCamAimToggle then pcall(setCamAimToggle, true, true) end end)
	end
	local _, setFovRingToggle = makeToggleRow({
		name     = "Show FOV Ring",
		desc     = "Draw the aimbot FOV on screen",
		key      = "aimShowFov",
		color    = Color3.fromRGB(255, 80, 80),
		order    = 34,
		parent   = miscPage,
		callback = function(on) showFov = on; syncFovCircle() end,
	})
	if settings.toggles["aimShowFov"] == nil then
		task.defer(function() if setFovRingToggle then pcall(setFovRingToggle, true, true) end end)
	end
	makeSliderRow({
		name     = "Aim FOV (px)",
		key      = "aimFov",
		min      = 30,
		max      = 400,
		default  = kDefaultFovPx,
		order    = 35,
		parent   = miscPage,
		callback = function(v) aimFovPx = v; syncFovCircle() end,
	})
	makeSliderRow({
		name     = "Aim Smooth %",
		key      = "aimSmooth",
		min      = 0,
		max      = 95,
		default  = math.floor(kDefaultSmooth * 100),
		order    = 36,
		parent   = miscPage,
		callback = function(v) aimSmooth = v / 100 end,
	})
end

----------------------------------------------------------------
-- EXTRA TAB
----------------------------------------------------------------
local extraPage = pages.Extra

makeSection("MOVEMENT", 0, extraPage)

-- BUNNY HOP (hold Space)
do
	local conn
	local function setBhop(on)
		disconnect(conn)
		conn = nil
		if not on then return end
		conn = RunService.Heartbeat:Connect(function()
			if UserInputService:GetFocusedTextBox() then return end
			if not UserInputService:IsKeyDown(Enum.KeyCode.Space) then return end
			local hum = getHumanoid()
			if hum and hum.FloorMaterial ~= Enum.Material.Air then
				hum:ChangeState(Enum.HumanoidStateType.Jumping)
			end
		end)
	end
	makeToggleRow({
		name = "Bunny Hop", desc = "Hold Space to keep jumping",
		key = "bhop", color = Color3.fromRGB(90, 230, 150), order = 1, parent = extraPage, callback = setBhop,
	})
end

-- FLOAT / AIR WALK (Ctrl lowers you)
do
	local conn, plat
	local offset = 0
	local function setFloat(on)
		disconnect(conn)
		conn = nil
		if plat then plat:Destroy() plat = nil end
		offset = 0
		if not on then return end
		plat = Instance.new("Part")
		plat.Name = "GhostedFloat"
		plat.Size = Vector3.new(8, 1, 8)
		plat.Anchored = true
		plat.CanCollide = true
		plat.Transparency = 1
		plat.Parent = workspace
		conn = RunService.Heartbeat:Connect(function()
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if not (hrp and hum and plat) then return end
			if not UserInputService:GetFocusedTextBox() then
				if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then offset = offset - 0.25 end
			end
			local y = hrp.Position.Y - (hum.HipHeight + hrp.Size.Y / 2 + 0.5)
			plat.CFrame = CFrame.new(hrp.Position.X, y + offset, hrp.Position.Z)
			if offset < 0 then offset = math.min(0, offset + 0.1) end
		end)
	end
	onUnload(function() if plat then plat:Destroy() end end)
	makeToggleRow({
		name = "Air Walk", desc = "Invisible platform under your feet",
		key = "float", color = Color3.fromRGB(130, 200, 255), order = 2, parent = extraPage, callback = setFloat,
	})
end

-- SPIN
do
	local conn
	local spinSpeed = 20
	local function setSpin(on)
		disconnect(conn)
		conn = nil
		if not on then return end
		conn = RunService.Heartbeat:Connect(function()
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if hrp then hrp.CFrame = hrp.CFrame * CFrame.Angles(0, math.rad(spinSpeed), 0) end
		end)
	end
	makeToggleRow({
		name = "Spin", desc = "Rotate your character",
		key = "spin", color = Color3.fromRGB(255, 150, 200), order = 3, parent = extraPage, callback = setSpin,
	})
	makeSliderRow({
		name = "Spin Speed", key = "spinSpeed", min = 1, max = 60, default = 20,
		order = 4, parent = extraPage, callback = function(v) spinSpeed = v end,
	})
end

-- NO RAGDOLL / ANTI-TRIP
do
	local conn
	local states = {
		Enum.HumanoidStateType.FallingDown,
		Enum.HumanoidStateType.Ragdoll,
	}
	local function setStates(enabled)
		local hum = getHumanoid()
		if hum then
			for _, s in ipairs(states) do pcall(function() hum:SetStateEnabled(s, enabled) end) end
		end
	end
	local function setNoRagdoll(on)
		disconnect(conn)
		conn = nil
		if on then
			conn = RunService.Heartbeat:Connect(function() setStates(false) end)
		else
			setStates(true)
		end
	end
	makeToggleRow({
		name = "No Ragdoll", desc = "Disables falling-down / ragdoll states",
		key = "noragdoll", color = Color3.fromRGB(255, 200, 90), order = 5, parent = extraPage, callback = setNoRagdoll,
	})
end

-- ANTI-FLING (makes other players' bodies non-collidable for you)
do
	local conn
	local touched = setmetatable({}, { __mode = "k" })
	local function setAntiFling(on)
		disconnect(conn)
		conn = nil
		if on then
			conn = RunService.Stepped:Connect(function()
				for _, plr in ipairs(Players:GetPlayers()) do
					if plr ~= player and plr.Character then
						for _, part in ipairs(plr.Character:GetDescendants()) do
							if part:IsA("BasePart") and part.CanCollide then
								touched[part] = true
								part.CanCollide = false
							end
						end
					end
				end
			end)
		else
			for part in pairs(touched) do
				if part.Parent then pcall(function() part.CanCollide = true end) end
				touched[part] = nil
			end
		end
	end
	makeToggleRow({
		name = "Anti-Fling", desc = "Other players can't push or fling you",
		key = "antifling", color = Color3.fromRGB(90, 200, 255), order = 6, parent = extraPage, callback = setAntiFling,
	})
end

-- RESPAWN WHERE YOU DIED
do
	local on_ = false
	local conn
	local lastCF
	local function setRespawnHere(on)
		on_ = on
		disconnect(conn)
		conn = nil
		lastCF = nil
		if not on then return end
		conn = RunService.Heartbeat:Connect(function()
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hrp and hum and hum.Health > 0 then lastCF = hrp.CFrame end
		end)
	end
	track(player.CharacterAdded:Connect(function(char)
		if not (on_ and lastCF) then return end
		local target = lastCF
		local hrp = char:WaitForChild("HumanoidRootPart", 5)
		if hrp then
			task.wait(0.15)
			hrp.CFrame = target
		end
	end))
	makeToggleRow({
		name = "Respawn Here", desc = "Respawn at the spot you died",
		key = "respawnhere", color = Color3.fromRGB(180, 130, 255), order = 7, parent = extraPage, callback = setRespawnHere,
	})
end

----------------------------------------------------------------
makeSection("UTILITY", 10, extraPage)

-- AUTO CLICKER
do
	local conn
	local cps = 10
	local acc = 0
	local function setAutoClick(on)
		disconnect(conn)
		conn = nil
		acc = 0
		if not on then return end
		conn = RunService.Heartbeat:Connect(function(dt)
			if UserInputService:GetFocusedTextBox() then return end
			acc = acc + dt
			local interval = 1 / cps
			if acc < interval then return end
			acc = 0
			local cam = workspace.CurrentCamera
			local vp = cam and cam.ViewportSize or Vector2.new(0, 0)
			local ok = pcall(function()
				local vu = game:GetService("VirtualUser")
				vu:CaptureController()
				vu:ClickButton1(Vector2.new(vp.X / 2, vp.Y / 2))
			end)
			if not ok and typeof(mouse1click) == "function" then pcall(mouse1click) end
		end)
	end
	makeToggleRow({
		name = "Auto Clicker", desc = "Clicks the screen center repeatedly",
		key = "autoclick", color = Color3.fromRGB(255, 150, 60), order = 11, parent = extraPage, callback = setAutoClick,
	})
	makeSliderRow({
		name = "Clicks Per Second", key = "clickCps", min = 1, max = 30, default = 10,
		order = 12, parent = extraPage, callback = function(v) cps = v end,
	})
end

-- CAMERA NOCLIP (camera passes through walls)
do
	local orig = player.DevCameraOcclusionMode
	local function setCamNoclip(on)
		pcall(function()
			player.DevCameraOcclusionMode = on and Enum.DevCameraOcclusionMode.Invisicam or orig
		end)
	end
	onUnload(function() pcall(function() player.DevCameraOcclusionMode = orig end) end)
	makeToggleRow({
		name = "Camera Noclip", desc = "Camera no longer snaps in front of walls",
		key = "camnoclip", color = Color3.fromRGB(190, 190, 255), order = 13, parent = extraPage, callback = setCamNoclip,
	})
end

-- FPS BOOST
do
	local saved
	local function setFpsBoost(on)
		if on then
			saved = { shadows = Lighting.GlobalShadows, fx = {} }
			Lighting.GlobalShadows = false
			for _, v in ipairs(Lighting:GetChildren()) do
				if v:IsA("PostEffect") then
					saved.fx[v] = v.Enabled
					v.Enabled = false
				end
			end
			pcall(function() saved.deco = workspace.Terrain.Decoration; workspace.Terrain.Decoration = false end)
		elseif saved then
			Lighting.GlobalShadows = saved.shadows
			for v, e in pairs(saved.fx) do
				if v.Parent then pcall(function() v.Enabled = e end) end
			end
			if saved.deco ~= nil then pcall(function() workspace.Terrain.Decoration = saved.deco end) end
			saved = nil
		end
	end
	makeToggleRow({
		name = "FPS Boost", desc = "Shadows, post effects and grass off",
		key = "fpsboost", color = Color3.fromRGB(90, 230, 150), order = 14, parent = extraPage, callback = setFpsBoost,
	})
end

----------------------------------------------------------------
makeSection("WAYPOINTS", 20, extraPage)

do
	local points = {}
	local idx = 0

	local function hrpNow()
		return player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	end

	makeButtonRow({
		text = "Save Waypoint", order = 21, parent = extraPage,
		callback = function()
			local hrp = hrpNow()
			if not hrp then notify("No character") return end
			points[#points + 1] = hrp.CFrame
			idx = #points
			notify("Saved waypoint #" .. #points)
		end,
	})
	makeButtonRow({
		text = "Next Waypoint (teleport)", order = 22, parent = extraPage,
		callback = function()
			if #points == 0 then notify("No waypoints saved") return end
			local hrp = hrpNow()
			if not hrp then notify("No character") return end
			idx = idx % #points + 1
			hrp.CFrame = points[idx]
			notify("Waypoint " .. idx .. "/" .. #points)
		end,
	})
	makeButtonRow({
		text = "Clear Waypoints", order = 23, parent = extraPage, color = Color3.fromRGB(120, 40, 50),
		callback = function()
			points = {}
			idx = 0
			notify("Waypoints cleared")
		end,
	})
end

----------------------------------------------------------------
-- FUN TAB
----------------------------------------------------------------
do
	local funPage = pages.Fun

	makeSection("CHARACTER", 0, funPage)

	-- RAINBOW CHARACTER (local only)
	do
		local conn
		local orig = setmetatable({}, { __mode = "k" })
		local function setRainbow(on)
			disconnect(conn)
			conn = nil
			if on then
				conn = RunService.Heartbeat:Connect(function()
					local char = player.Character
					if not char then return end
					local c = Color3.fromHSV((os.clock() * 0.35) % 1, 0.8, 1)
					for _, p in ipairs(char:GetDescendants()) do
						if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
							if orig[p] == nil then orig[p] = p.Color end
							p.Color = c
						end
					end
				end)
			else
				for p, c in pairs(orig) do
					if p.Parent then pcall(function() p.Color = c end) end
					orig[p] = nil
				end
			end
		end
		makeToggleRow({
			name = "Rainbow Character", desc = "Cycles your colors (only you see it)",
			key = "rainbow", color = Color3.fromRGB(255, 120, 200), order = 1, parent = funPage, callback = setRainbow,
		})
	end

	-- GHOST MODE (local transparency)
	do
		local conn
		local touched = setmetatable({}, { __mode = "k" })
		local function setGhost(on)
			disconnect(conn)
			conn = nil
			if on then
				conn = RunService.RenderStepped:Connect(function()
					local char = player.Character
					if not char then return end
					for _, p in ipairs(char:GetDescendants()) do
						if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
							touched[p] = true
							p.LocalTransparencyModifier = 0.7
						end
					end
				end)
			else
				for p in pairs(touched) do
					if p.Parent then pcall(function() p.LocalTransparencyModifier = 0 end) end
					touched[p] = nil
				end
			end
		end
		makeToggleRow({
			name = "See-Through Mode", desc = "Makes your own body translucent",
			key = "seethrough", color = Color3.fromRGB(190, 190, 255), order = 2, parent = funPage, callback = setGhost,
		})
	end

	-- SIT
	makeToggleRow({
		name = "Sit", desc = "Forces your character to sit",
		key = "sitdown", color = Color3.fromRGB(255, 200, 90), order = 3, parent = funPage,
		callback = function(on)
			local hum = getHumanoid()
			if hum then hum.Sit = on end
		end,
	})

	-- TRAIL (local only)
	do
		local trail, a0, a1
		local function setTrail(on)
			if trail then trail:Destroy() trail = nil end
			if a0 then a0:Destroy() a0 = nil end
			if a1 then a1:Destroy() a1 = nil end
			if not on then return end
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if not hrp then return end
			a0 = Instance.new("Attachment")
			a0.Position = Vector3.new(0, 1.2, 0)
			a0.Parent = hrp
			a1 = Instance.new("Attachment")
			a1.Position = Vector3.new(0, -1.2, 0)
			a1.Parent = hrp
			trail = Instance.new("Trail")
			trail.Attachment0 = a0
			trail.Attachment1 = a1
			trail.Lifetime = 0.8
			trail.LightEmission = 1
			trail.Color = ColorSequence.new(accent)
			trail.Transparency = NumberSequence.new(0.1, 1)
			trail.Parent = hrp
		end
		onUnload(function() setTrail(false) end)
		makeToggleRow({
			name = "Trail", desc = "Accent colored trail behind you",
			key = "trail", color = Color3.fromRGB(110, 170, 255), order = 4, parent = funPage, callback = setTrail,
		})
	end

	-- FIRST PERSON LOCK
	makeToggleRow({
		name = "First Person Lock", desc = "Locks the camera to first person",
		key = "firstperson", color = Color3.fromRGB(90, 230, 150), order = 5, parent = funPage,
		callback = function(on)
			pcall(function()
				player.CameraMode = on and Enum.CameraMode.LockFirstPerson or Enum.CameraMode.Classic
			end)
		end,
	})
	onUnload(function() pcall(function() player.CameraMode = Enum.CameraMode.Classic end) end)

	-- CHARACTER SCALE (R15 only)
	do
		local names = { "BodyHeightScale", "BodyWidthScale", "BodyDepthScale", "HeadScale" }
		local function applyScale(v)
			local hum = getHumanoid()
			if not hum then return end
			for _, n in ipairs(names) do
				local nv = hum:FindFirstChild(n)
				if nv and nv:IsA("NumberValue") then nv.Value = v / 100 end
			end
		end
		onUnload(function() applyScale(100) end)
		makeSliderRow({
			name = "Character Scale % (R15)", key = "charScale", min = 50, max = 200, default = 100,
			order = 6, parent = funPage, callback = applyScale,
		})
	end

	----------------------------------------------------------------
	makeSection("MOVEMENT", 10, funPage)

	-- SPRINT (hold Shift)
	do
		local conn, origSpeed
		local sprintSpeed = 40
		local function setSprint(on)
			disconnect(conn)
			conn = nil
			local hum = getHumanoid()
			if on then
				if hum then origSpeed = hum.WalkSpeed end
				conn = RunService.Heartbeat:Connect(function()
					local h = getHumanoid()
					if not h then return end
					if origSpeed == nil then origSpeed = h.WalkSpeed end
					if not UserInputService:GetFocusedTextBox() and UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
						h.WalkSpeed = sprintSpeed
					elseif h.WalkSpeed == sprintSpeed then
						h.WalkSpeed = origSpeed
					end
				end)
			else
				if hum and origSpeed then hum.WalkSpeed = origSpeed end
				origSpeed = nil
			end
		end
		makeToggleRow({
			name = "Sprint", desc = "Hold Shift to run faster",
			key = "sprint", color = Color3.fromRGB(255, 150, 90), order = 11, parent = funPage, callback = setSprint,
		})
		makeSliderRow({
			name = "Sprint Speed", key = "sprintSpeed", min = 20, max = 150, default = 40,
			order = 12, parent = funPage, callback = function(v) sprintSpeed = v end,
		})
	end

	-- DASH (press Q)
	do
		local conn
		local last = 0
		local dashPower = 120
		local function setDash(on)
			disconnect(conn)
			conn = nil
			if not on then return end
			conn = UserInputService.InputBegan:Connect(function(input, processed)
				if processed or input.KeyCode ~= Enum.KeyCode.Q then return end
				if os.clock() - last < 0.8 then return end
				local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if hrp then
					last = os.clock()
					hrp.AssemblyLinearVelocity = hrp.CFrame.LookVector * dashPower + Vector3.new(0, 20, 0)
				end
			end)
		end
		makeToggleRow({
			name = "Dash", desc = "Press Q to dash forward",
			key = "dash", color = Color3.fromRGB(255, 200, 90), order = 13, parent = funPage, callback = setDash,
		})
		makeSliderRow({
			name = "Dash Power", key = "dashPower", min = 50, max = 300, default = 120,
			order = 14, parent = funPage, callback = function(v) dashPower = v end,
		})
	end
end

----------------------------------------------------------------
-- WORLD TAB
----------------------------------------------------------------
do
	local worldPage = pages.World

	makeSection("ENVIRONMENT", 0, worldPage)

	-- NO FOG
	do
		local saved
		local function setNoFog(on)
			if on then
				saved = { FogEnd = Lighting.FogEnd, FogStart = Lighting.FogStart, atm = {} }
				Lighting.FogEnd = 1e6
				Lighting.FogStart = 1e6
				for _, a in ipairs(Lighting:GetDescendants()) do
					if a:IsA("Atmosphere") then
						saved.atm[a] = { a.Density, a.Haze }
						a.Density = 0
						a.Haze = 0
					end
				end
			elseif saved then
				Lighting.FogEnd = saved.FogEnd
				Lighting.FogStart = saved.FogStart
				for a, v in pairs(saved.atm) do
					if a.Parent then pcall(function() a.Density = v[1]; a.Haze = v[2] end) end
				end
				saved = nil
			end
		end
		makeToggleRow({
			name = "No Fog", desc = "Removes fog and atmosphere haze",
			key = "nofog", color = Color3.fromRGB(190, 190, 255), order = 1, parent = worldPage, callback = setNoFog,
		})
	end

	-- X-RAY
	do
		local list = {}
		local token = 0
		local function setXray(on)
			token = token + 1
			local mine = token
			if on then
				task.spawn(function()
					local n = 0
					for _, d in ipairs(workspace:GetDescendants()) do
						if token ~= mine then return end
						if d:IsA("BasePart") then
							local m = d:FindFirstAncestorOfClass("Model")
							if not (m and m:FindFirstChildOfClass("Humanoid")) then
								list[#list + 1] = d
								d.LocalTransparencyModifier = 0.6
							end
						end
						n = n + 1
						if n % 800 == 0 then task.wait() end
					end
				end)
			else
				for i = #list, 1, -1 do
					local d = list[i]
					if d.Parent then pcall(function() d.LocalTransparencyModifier = 0 end) end
					list[i] = nil
				end
			end
		end
		makeToggleRow({
			name = "X-Ray", desc = "See through the map (only you)",
			key = "xray", color = Color3.fromRGB(110, 200, 255), order = 2, parent = worldPage, callback = setXray,
		})
	end

	-- REMOVE PARTICLES
	do
		local list = {}
		local function setParticles(on)
			if on then
				for _, d in ipairs(workspace:GetDescendants()) do
					if d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Smoke") or d:IsA("Fire")
						or d:IsA("Sparkles") or d:IsA("Beam") then
						if d.Enabled then
							list[#list + 1] = d
							d.Enabled = false
						end
					end
				end
			else
				for i = #list, 1, -1 do
					local d = list[i]
					if d.Parent then pcall(function() d.Enabled = true end) end
					list[i] = nil
				end
			end
		end
		makeToggleRow({
			name = "Remove Particles", desc = "Turns off particles, fire, smoke and beams",
			key = "noparticles", color = Color3.fromRGB(255, 150, 60), order = 3, parent = worldPage, callback = setParticles,
		})
	end

	-- TIME CYCLE
	do
		local conn, savedTime
		local speed = 10
		local function setCycle(on)
			disconnect(conn)
			conn = nil
			if on then
				if savedTime == nil then savedTime = Lighting.ClockTime end
				conn = RunService.RenderStepped:Connect(function(dt)
					Lighting.ClockTime = (Lighting.ClockTime + dt * speed / 10) % 24
				end)
			elseif savedTime ~= nil then
				Lighting.ClockTime = savedTime
				savedTime = nil
			end
		end
		makeToggleRow({
			name = "Time Cycle", desc = "Day and night keep moving",
			key = "timecycle", color = Color3.fromRGB(255, 190, 90), order = 4, parent = worldPage, callback = setCycle,
		})
		makeSliderRow({
			name = "Cycle Speed", key = "cycleSpeed", min = 1, max = 100, default = 10,
			order = 5, parent = worldPage, callback = function(v) speed = v end,
		})
	end

	-- WORLD TINT
	do
		local conn, saved
		local hue = 200
		local function setTint(on)
			disconnect(conn)
			conn = nil
			if on then
				if not saved then saved = { Lighting.Ambient, Lighting.OutdoorAmbient } end
				conn = RunService.RenderStepped:Connect(function()
					local c = Color3.fromHSV(hue / 360, 0.6, 0.85)
					Lighting.Ambient = c
					Lighting.OutdoorAmbient = c
				end)
			elseif saved then
				Lighting.Ambient = saved[1]
				Lighting.OutdoorAmbient = saved[2]
				saved = nil
			end
		end
		makeToggleRow({
			name = "World Tint", desc = "Tints the ambient light (pick a hue below)",
			key = "worldtint", color = Color3.fromRGB(255, 120, 200), order = 6, parent = worldPage, callback = setTint,
		})
		makeSliderRow({
			name = "Tint Hue", key = "tintHue", min = 0, max = 360, default = 200,
			order = 7, parent = worldPage, callback = function(v) hue = v end,
		})
	end

	----------------------------------------------------------------
	makeSection("CAMERA", 10, worldPage)

	-- HOLD TO ZOOM (Z)
	do
		local conn, baseFov
		local zoomFov = 20
		local function setZoom(on)
			disconnect(conn)
			conn = nil
			local cam = workspace.CurrentCamera
			if on then
				baseFov = cam and cam.FieldOfView or 70
				conn = RunService.RenderStepped:Connect(function(dt)
					local c = workspace.CurrentCamera
					if not c then return end
					local zooming = not UserInputService:GetFocusedTextBox() and UserInputService:IsKeyDown(Enum.KeyCode.Z)
					local target = zooming and zoomFov or baseFov
					c.FieldOfView = c.FieldOfView + (target - c.FieldOfView) * math.min(1, dt * 12)
				end)
			elseif cam and baseFov then
				cam.FieldOfView = baseFov
			end
		end
		makeToggleRow({
			name = "Hold Z to Zoom", desc = "Smooth zoom while Z is held",
			key = "zoomkey", color = Color3.fromRGB(110, 170, 255), order = 11, parent = worldPage, callback = setZoom,
		})
		makeSliderRow({
			name = "Zoom FOV", key = "zoomFov", min = 5, max = 60, default = 20,
			order = 12, parent = worldPage, callback = function(v) zoomFov = v end,
		})
	end

	-- FREECAM (PC)
	do
		local conn, inputConn, savedType, anchoredHrp
		local speed = 60
		local yaw, pitch = 0, 0
		local pos = Vector3.zero

		local function stopFree()
			disconnect(conn)
			disconnect(inputConn)
			conn, inputConn = nil, nil
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			local cam = workspace.CurrentCamera
			local hum = getHumanoid()
			if cam then
				cam.CameraType = savedType or Enum.CameraType.Custom
				if hum then cam.CameraSubject = hum end
			end
			if anchoredHrp and anchoredHrp.Parent then anchoredHrp.Anchored = false end
			anchoredHrp = nil
			savedType = nil
		end

		local function setFreecam(on)
			stopFree()
			if not on then return end
			local cam = workspace.CurrentCamera
			if not cam then return end
			savedType = cam.CameraType
			local x, y = cam.CFrame:ToOrientation()
			pitch, yaw = x, y
			pos = cam.CFrame.Position
			cam.CameraType = Enum.CameraType.Scriptable

			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if hrp then
				hrp.Anchored = true
				anchoredHrp = hrp
			end

			inputConn = UserInputService.InputChanged:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseMovement
					and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
					yaw = yaw - input.Delta.X * 0.004
					pitch = math.clamp(pitch - input.Delta.Y * 0.004, -1.5, 1.5)
				end
			end)

			conn = RunService.RenderStepped:Connect(function(dt)
				local c = workspace.CurrentCamera
				if not c then return end
				local rotating = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
				UserInputService.MouseBehavior = rotating and Enum.MouseBehavior.LockCurrentPosition or Enum.MouseBehavior.Default
				local rot = CFrame.fromOrientation(pitch, yaw, 0)
				local dir = Vector3.zero
				if not UserInputService:GetFocusedTextBox() then
					if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir = dir + Vector3.new(0, 0, -1) end
					if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir = dir + Vector3.new(0, 0, 1) end
					if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir = dir + Vector3.new(-1, 0, 0) end
					if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir = dir + Vector3.new(1, 0, 0) end
					if UserInputService:IsKeyDown(Enum.KeyCode.E) then dir = dir + Vector3.new(0, 1, 0) end
					if UserInputService:IsKeyDown(Enum.KeyCode.Q) then dir = dir + Vector3.new(0, -1, 0) end
				end
				local mult = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) and 3 or 1
				if dir.Magnitude > 0 then
					pos = pos + (rot * dir.Unit) * speed * mult * dt
				end
				c.CFrame = CFrame.new(pos) * rot
			end)
		end

		onUnload(stopFree)
		makeToggleRow({
			name = "Freecam", desc = "WASD + E/Q, hold right-mouse to look (PC)",
			key = "freecam", color = Color3.fromRGB(90, 200, 255), order = 13, parent = worldPage, callback = setFreecam,
		})
		makeSliderRow({
			name = "Freecam Speed", key = "freecamSpeed", min = 10, max = 300, default = 60,
			order = 14, parent = worldPage, callback = function(v) speed = v end,
		})
	end

	----------------------------------------------------------------
	makeSection("TOOLS", 20, worldPage)

	-- CLICK DELETE (Alt + click, local only)
	do
		local conn
		local deleted = {}
		local function setClickDelete(on)
			disconnect(conn)
			conn = nil
			if not on then return end
			conn = UserInputService.InputBegan:Connect(function(input, processed)
				if processed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
				if not UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt) then return end
				local t = player:GetMouse().Target
				if not t then return end
				local m = t:FindFirstAncestorOfClass("Model")
				if m and m:FindFirstChildOfClass("Humanoid") then return end
				deleted[#deleted + 1] = { part = t, parent = t.Parent }
				t.Parent = nil
				notify("Deleted " .. t.Name)
			end)
		end
		onUnload(function()
			for i = #deleted, 1, -1 do
				local e = deleted[i]
				if e.parent and e.parent.Parent then pcall(function() e.part.Parent = e.parent end) end
				deleted[i] = nil
			end
		end)
		makeToggleRow({
			name = "Click Delete", desc = "Alt+click removes a part (only for you)",
			key = "clickdelete", color = Color3.fromRGB(255, 100, 110), order = 21, parent = worldPage, callback = setClickDelete,
		})
		makeButtonRow({
			text = "Undo Delete", order = 22, parent = worldPage,
			callback = function()
				local e = table.remove(deleted)
				if not e then notify("Nothing to undo") return end
				if e.parent and e.parent.Parent then
					pcall(function() e.part.Parent = e.parent end)
					notify("Restored " .. e.part.Name)
				end
			end,
		})
	end

	makeButtonRow({
		text = "Copy My Position", order = 23, parent = worldPage,
		callback = function()
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if not hrp then notify("No character") return end
			local p = hrp.Position
			copyText(string.format("%.1f, %.1f, %.1f", p.X, p.Y, p.Z), "Position")
		end,
	})
	makeButtonRow({
		text = "Copy Game Link", order = 24, parent = worldPage,
		callback = function() copyText("https://www.roblox.com/games/" .. game.PlaceId, "Game link") end,
	})
	makeButtonRow({
		text = "Teleport to Spawn", order = 25, parent = worldPage,
		callback = function()
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if not hrp then notify("No character") return end
			for _, d in ipairs(workspace:GetDescendants()) do
				if d:IsA("SpawnLocation") then
					hrp.CFrame = d.CFrame + Vector3.new(0, 5, 0)
					notify("Teleported to spawn")
					return
				end
			end
			notify("No spawn found")
		end,
	})
end

----------------------------------------------------------------
-- CHAT TAB
----------------------------------------------------------------
do
	local chatPage = pages.Chat

	local function sendChat(msg)
		local ok = pcall(function()
			local TCS = game:GetService("TextChatService")
			if TCS.ChatVersion == Enum.ChatVersion.TextChatService then
				local ch = TCS.TextChannels:FindFirstChild("RBXGeneral")
				if not ch then error("no channel") end
				ch:SendAsync(msg)
			else
				local ev = game:GetService("ReplicatedStorage"):FindFirstChild("DefaultChatSystemChatEvents")
				ev.SayMessageRequest:FireServer(msg, "All")
			end
		end)
		return ok
	end

	makeSection("SEND A MESSAGE", 0, chatPage)

	local box
	do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 38)
		row.BackgroundColor3 = kRowBg
		row.LayoutOrder = 1
		row.Parent = chatPage
		addCorner(row, 8)

		box = Instance.new("TextBox")
		box.Size = UDim2.new(1, -24, 1, 0)
		box.Position = UDim2.new(0, 12, 0, 0)
		box.BackgroundTransparency = 1
		box.PlaceholderText = "type a message..."
		box.PlaceholderColor3 = kTextDim
		box.Text = ""
		box.TextColor3 = Color3.fromRGB(230, 230, 235)
		box.Font = Enum.Font.Gotham
		box.TextSize = 14
		box.TextXAlignment = Enum.TextXAlignment.Left
		box.ClearTextOnFocus = false
		box.Parent = row
	end

	local function sendBox()
		local msg = box.Text
		if msg == "" then return end
		if sendChat(msg) then
			box.Text = ""
		else
			notify("Couldn't send (chat not available)")
		end
	end
	makeButtonRow({ text = "Send Message", order = 2, parent = chatPage, callback = sendBox })
	track(box.FocusLost:Connect(function(enter) if enter then sendBox() end end))

	----------------------------------------------------------------
	makeSection("EMOTES", 3, chatPage)
	local emotes = {
		{ "Dance", "/e dance" }, { "Dance 2", "/e dance2" }, { "Dance 3", "/e dance3" },
		{ "Wave", "/e wave" }, { "Cheer", "/e cheer" }, { "Laugh", "/e laugh" }, { "Point", "/e point" },
	}
	for i, e in ipairs(emotes) do
		makeButtonRow({
			text = e[1], order = 3 + i, parent = chatPage,
			callback = function()
				if not sendChat(e[2]) then notify("Couldn't send emote") end
			end,
		})
	end

	----------------------------------------------------------------
	makeSection("CHAT LOGGER", 20, chatPage)

	local logLines = {}
	local logRows = {}
	local logOrder = 100

	local function addLog(plr, msg)
		local line = string.format("[%s] %s: %s", os.date("%H:%M"), plr.DisplayName, msg)
		logLines[#logLines + 1] = line
		if #logLines > 200 then table.remove(logLines, 1) end

		logOrder = logOrder + 1
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, 0, 0, 0)
		lbl.AutomaticSize = Enum.AutomaticSize.Y
		lbl.BackgroundColor3 = kRowBg
		lbl.Text = line
		lbl.TextColor3 = Color3.fromRGB(215, 215, 225)
		lbl.Font = Enum.Font.Gotham
		lbl.TextSize = 12
		lbl.TextWrapped = true
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.LayoutOrder = logOrder
		lbl.Parent = chatPage
		addCorner(lbl, 6)
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 8)
		pad.PaddingRight = UDim.new(0, 8)
		pad.PaddingTop = UDim.new(0, 5)
		pad.PaddingBottom = UDim.new(0, 5)
		pad.Parent = lbl
		logRows[#logRows + 1] = lbl
		if #logRows > 40 then
			local old = table.remove(logRows, 1)
			old:Destroy()
		end
	end

	do
		local hooks = {}
		local addedConn
		local function hook(plr)
			if hooks[plr] then return end
			hooks[plr] = plr.Chatted:Connect(function(msg) addLog(plr, msg) end)
		end
		local function setLogger(on)
			disconnect(addedConn)
			addedConn = nil
			for p, c in pairs(hooks) do disconnect(c) hooks[p] = nil end
			if on then
				for _, p in ipairs(Players:GetPlayers()) do hook(p) end
				addedConn = Players.PlayerAdded:Connect(hook)
			end
		end
		onUnload(function() setLogger(false) end)
		makeToggleRow({
			name = "Chat Logger", desc = "Records messages from everyone below",
			key = "chatlog", color = Color3.fromRGB(90, 200, 255), order = 21, parent = chatPage, callback = setLogger,
		})
	end

	makeButtonRow({
		text = "Copy Chat Log", order = 22, parent = chatPage,
		callback = function()
			if #logLines == 0 then notify("Log is empty") return end
			copyText(table.concat(logLines, "\n"), "Chat log")
		end,
	})
	makeButtonRow({
		text = "Clear Chat Log", order = 23, parent = chatPage, color = Color3.fromRGB(120, 40, 50),
		callback = function()
			for _, r in ipairs(logRows) do r:Destroy() end
			logRows = {}
			logLines = {}
			notify("Chat log cleared")
		end,
	})

	-- JOIN / LEAVE ALERTS
	do
		local a, b
		local function setAlerts(on)
			disconnect(a)
			disconnect(b)
			a, b = nil, nil
			if on then
				a = Players.PlayerAdded:Connect(function(p) notify(p.DisplayName .. " joined") end)
				b = Players.PlayerRemoving:Connect(function(p) notify(p.DisplayName .. " left") end)
			end
		end
		makeToggleRow({
			name = "Join / Leave Alerts", desc = "Toast when someone joins or leaves",
			key = "joinleave", color = Color3.fromRGB(90, 230, 150), order = 24, parent = chatPage, callback = setAlerts,
		})
	end
end

----------------------------------------------------------------
-- TOOLS TAB
----------------------------------------------------------------
do
	local toolsPage = pages.Tools

	local function myHrp()
		return player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	end

	local function nearestPlayer()
		local hrp = myHrp()
		if not hrp then return nil end
		local best, bestD
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= player then
				local th = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
				if th then
					local d = (th.Position - hrp.Position).Magnitude
					if not bestD or d < bestD then best, bestD = p, d end
				end
			end
		end
		return best, bestD
	end

	makeSection("INFO", 0, toolsPage)

	-- INFO HUD
	do
		local frame = Instance.new("Frame")
		frame.Name = "InfoHud"
		frame.Position = UDim2.new(0, 8, 0, 8)
		frame.Size = UDim2.new(0, 190, 0, 78)
		frame.BackgroundColor3 = Color3.fromRGB(16, 16, 22)
		frame.BackgroundTransparency = 0.15
		frame.BorderSizePixel = 0
		frame.Visible = false
		frame.Parent = screenGui
		addCorner(frame, 8)
		do
			local s = addStroke(frame, accent, 1, 0.6)
			bindAccent(s, "Color")
		end
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, -16, 1, -8)
		lbl.Position = UDim2.new(0, 8, 0, 4)
		lbl.BackgroundTransparency = 1
		lbl.TextColor3 = Color3.fromRGB(230, 230, 235)
		lbl.Font = Enum.Font.GothamBold
		lbl.TextSize = 12
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.TextYAlignment = Enum.TextYAlignment.Top
		lbl.Text = ""
		lbl.Parent = frame

		local conn
		local function setHud(on)
			disconnect(conn)
			conn = nil
			frame.Visible = on
			if not on then return end
			local acc = 0
			conn = RunService.Heartbeat:Connect(function(dt)
				acc = acc + dt
				if acc < 0.15 then return end
				acc = 0
				local hrp = myHrp()
				local hum = getHumanoid()
				if not hrp then return end
				local p = hrp.Position
				lbl.Text = string.format(
					"XYZ  %.0f, %.0f, %.0f\nSpeed  %.0f st/s\nHealth  %d / %d\nPlayers  %d / %d",
					p.X, p.Y, p.Z,
					hrp.AssemblyLinearVelocity.Magnitude,
					hum and math.floor(hum.Health) or 0, hum and math.floor(hum.MaxHealth) or 0,
					#Players:GetPlayers(), Players.MaxPlayers
				)
			end)
		end
		onUnload(function() frame:Destroy() end)
		makeToggleRow({
			name = "Info HUD", desc = "Position, speed, health and player count",
			key = "infohud", color = Color3.fromRGB(90, 200, 255), order = 1, parent = toolsPage, callback = setHud,
		})
	end

	----------------------------------------------------------------
	makeSection("PLAYERS", 5, toolsPage)

	-- SPECTATE
	do
		local idx = 0
		local function others()
			local list = {}
			for _, p in ipairs(Players:GetPlayers()) do
				if p ~= player and p.Character and p.Character:FindFirstChildOfClass("Humanoid") then
					list[#list + 1] = p
				end
			end
			return list
		end
		local function spectate(step)
			local list = others()
			if #list == 0 then notify("No one to spectate") return end
			idx = (idx - 1 + step) % #list + 1
			local p = list[idx]
			local cam = workspace.CurrentCamera
			local hum = p.Character:FindFirstChildOfClass("Humanoid")
			if cam and hum then
				cam.CameraSubject = hum
				notify("Spectating " .. p.DisplayName)
			end
		end
		makeButtonRow({ text = "Spectate Next", order = 6, parent = toolsPage, callback = function() spectate(1) end })
		makeButtonRow({ text = "Spectate Previous", order = 7, parent = toolsPage, callback = function() spectate(-1) end })
		makeButtonRow({
			text = "Stop Spectating", order = 8, parent = toolsPage,
			callback = function()
				local cam = workspace.CurrentCamera
				local hum = getHumanoid()
				if cam and hum then cam.CameraSubject = hum end
			end,
		})
	end

	makeButtonRow({
		text = "Teleport to Nearest Player", order = 9, parent = toolsPage,
		callback = function()
			local p = nearestPlayer()
			local hrp = myHrp()
			local th = p and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
			if hrp and th then
				hrp.CFrame = th.CFrame * CFrame.new(0, 0, 3)
				notify("Teleported to " .. p.DisplayName)
			else
				notify("No players nearby")
			end
		end,
	})
	makeButtonRow({
		text = "Teleport to Random Player", order = 10, parent = toolsPage,
		callback = function()
			local list = {}
			for _, p in ipairs(Players:GetPlayers()) do
				if p ~= player and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
					list[#list + 1] = p
				end
			end
			local hrp = myHrp()
			if #list == 0 or not hrp then notify("No players") return end
			local p = list[math.random(1, #list)]
			hrp.CFrame = p.Character.HumanoidRootPart.CFrame * CFrame.new(0, 0, 3)
			notify("Teleported to " .. p.DisplayName)
		end,
	})

	-- FOLLOW NEAREST
	do
		local conn
		local function setFollow(on)
			disconnect(conn)
			conn = nil
			if on then
				local acc = 0
				conn = RunService.Heartbeat:Connect(function(dt)
					acc = acc + dt
					if acc < 0.2 then return end
					acc = 0
					local p = nearestPlayer()
					local hum = getHumanoid()
					local th = p and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
					if hum and th then hum:MoveTo(th.Position) end
				end)
			else
				local hum, hrp = getHumanoid(), myHrp()
				if hum and hrp then hum:MoveTo(hrp.Position) end
			end
		end
		makeToggleRow({
			name = "Follow Nearest Player", desc = "Walks toward whoever is closest",
			key = "follownearest", color = Color3.fromRGB(180, 130, 255), order = 11, parent = toolsPage, callback = setFollow,
		})
	end

	----------------------------------------------------------------
	makeSection("TOOLS & PROMPTS", 20, toolsPage)

	makeButtonRow({
		text = "Equip All Tools", order = 21, parent = toolsPage,
		callback = function()
			local bp = player:FindFirstChildOfClass("Backpack")
			local char = player.Character
			if not (bp and char) then return end
			local n = 0
			for _, t in ipairs(bp:GetChildren()) do
				if t:IsA("Tool") then t.Parent = char n = n + 1 end
			end
			notify("Equipped " .. n .. " tools")
		end,
	})
	makeButtonRow({
		text = "Unequip All Tools", order = 22, parent = toolsPage,
		callback = function()
			local bp = player:FindFirstChildOfClass("Backpack")
			local char = player.Character
			if not (bp and char) then return end
			for _, t in ipairs(char:GetChildren()) do
				if t:IsA("Tool") then t.Parent = bp end
			end
			notify("Tools put away")
		end,
	})
	makeButtonRow({
		text = "Get Teleport Tool", order = 23, parent = toolsPage,
		callback = function()
			local bp = player:FindFirstChildOfClass("Backpack")
			if not bp then return end
			if bp:FindFirstChild("Teleport Tool") or (player.Character and player.Character:FindFirstChild("Teleport Tool")) then
				notify("You already have it")
				return
			end
			local tool = Instance.new("Tool")
			tool.Name = "Teleport Tool"
			tool.RequiresHandle = false
			tool.CanBeDropped = false
			tool.ToolTip = "Click to teleport"
			tool.Activated:Connect(function()
				local hrp = myHrp()
				local hit = player:GetMouse().Hit
				if hrp and hit then
					hrp.CFrame = CFrame.new(hit.Position + Vector3.new(0, 3.5, 0))
				end
			end)
			tool.Parent = bp
			notify("Teleport Tool added")
		end,
	})

	-- INSTANT PROMPTS
	do
		local conn
		local function setInstant(on)
			disconnect(conn)
			conn = nil
			if not on then return end
			local pps = game:GetService("ProximityPromptService")
			conn = pps.PromptButtonHoldBegan:Connect(function(prompt)
				if typeof(fireproximityprompt) == "function" then
					pcall(fireproximityprompt, prompt)
				else
					pcall(function() prompt.HoldDuration = 0 end)
				end
			end)
		end
		makeToggleRow({
			name = "Instant Prompts", desc = "Holding E triggers prompts immediately",
			key = "instantprompts", color = Color3.fromRGB(255, 200, 90), order = 24, parent = toolsPage, callback = setInstant,
		})
	end

	makeButtonRow({
		text = "Trigger Nearby Prompts / Clicks", order = 25, parent = toolsPage,
		callback = function()
			local hrp = myHrp()
			if not hrp then notify("No character") return end
			local n = 0
			for _, d in ipairs(workspace:GetDescendants()) do
				if d:IsA("ProximityPrompt") and typeof(fireproximityprompt) == "function" then
					local part = d.Parent
					if part and part:IsA("BasePart") and (part.Position - hrp.Position).Magnitude <= 30 then
						pcall(fireproximityprompt, d)
						n = n + 1
					end
				elseif d:IsA("ClickDetector") and typeof(fireclickdetector) == "function" then
					local part = d.Parent
					if part and part:IsA("BasePart") and (part.Position - hrp.Position).Magnitude <= 30 then
						pcall(fireclickdetector, d)
						n = n + 1
					end
				end
			end
			notify(n > 0 and ("Triggered " .. n) or "Nothing nearby (or unsupported executor)")
		end,
	})
end

----------------------------------------------------------------
-- MORE MOVEMENT (Extra tab)
----------------------------------------------------------------
do
	local extra = pages.Extra
	makeSection("MORE MOVEMENT", 30, extra)

	-- GLIDE (hold Space in the air)
	do
		local conn
		local function setGlide(on)
			disconnect(conn)
			conn = nil
			if not on then return end
			conn = RunService.Heartbeat:Connect(function()
				if UserInputService:GetFocusedTextBox() then return end
				if not UserInputService:IsKeyDown(Enum.KeyCode.Space) then return end
				local hum = getHumanoid()
				local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if hum and hrp and hum.FloorMaterial == Enum.Material.Air then
					local v = hrp.AssemblyLinearVelocity
					if v.Y < -12 then hrp.AssemblyLinearVelocity = Vector3.new(v.X, -12, v.Z) end
				end
			end)
		end
		makeToggleRow({
			name = "Glide", desc = "Hold Space in the air to fall slowly",
			key = "glide", color = Color3.fromRGB(130, 200, 255), order = 31, parent = extra, callback = setGlide,
		})
	end

	-- FALL CLAMP
	do
		local conn
		local function setClamp(on)
			disconnect(conn)
			conn = nil
			if not on then return end
			conn = RunService.Heartbeat:Connect(function()
				local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if hrp then
					local v = hrp.AssemblyLinearVelocity
					if v.Y < -50 then hrp.AssemblyLinearVelocity = Vector3.new(v.X, -50, v.Z) end
				end
			end)
		end
		makeToggleRow({
			name = "Fall Clamp", desc = "Caps fall speed (helps against fall damage)",
			key = "fallclamp", color = Color3.fromRGB(90, 230, 150), order = 32, parent = extra, callback = setClamp,
		})
	end

	-- WALL CLIMB
	do
		local conn
		local function setClimb(on)
			disconnect(conn)
			conn = nil
			if not on then return end
			conn = RunService.Heartbeat:Connect(function()
				local char = player.Character
				local hrp = char and char:FindFirstChild("HumanoidRootPart")
				local hum = getHumanoid()
				if not (hrp and hum) or hum.MoveDirection.Magnitude == 0 then return end
				local params = RaycastParams.new()
				params.FilterDescendantsInstances = { char }
				params.FilterType = Enum.RaycastFilterType.Exclude
				local hit = workspace:Raycast(hrp.Position, hrp.CFrame.LookVector * 3, params)
				if hit then
					local v = hrp.AssemblyLinearVelocity
					hrp.AssemblyLinearVelocity = Vector3.new(v.X, 28, v.Z)
				end
			end)
		end
		makeToggleRow({
			name = "Wall Climb", desc = "Walk into a wall to climb it",
			key = "wallclimb", color = Color3.fromRGB(255, 150, 90), order = 33, parent = extra, callback = setClimb,
		})
	end

	-- TP WALK
	do
		local conn
		local tpSpeed = 20
		local function setTpWalk(on)
			disconnect(conn)
			conn = nil
			if not on then return end
			conn = RunService.Heartbeat:Connect(function(dt)
				local hum = getHumanoid()
				local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if hum and hrp and hum.MoveDirection.Magnitude > 0 then
					hrp.CFrame = hrp.CFrame + hum.MoveDirection * tpSpeed * dt
				end
			end)
		end
		makeToggleRow({
			name = "TP Walk", desc = "Extra speed without touching WalkSpeed",
			key = "tpwalk", color = Color3.fromRGB(255, 200, 90), order = 34, parent = extra, callback = setTpWalk,
		})
		makeSliderRow({
			name = "TP Walk Speed", key = "tpWalkSpeed", min = 1, max = 100, default = 20,
			order = 35, parent = extra, callback = function(v) tpSpeed = v end,
		})
	end

	-- AUTO WALK
	do
		local conn
		local function setAutoWalk(on)
			disconnect(conn)
			conn = nil
			if on then
				conn = RunService.Heartbeat:Connect(function()
					local hum = getHumanoid()
					if hum then hum:Move(Vector3.new(0, 0, -1), true) end
				end)
			else
				local hum = getHumanoid()
				if hum then hum:Move(Vector3.zero, true) end
			end
		end
		makeToggleRow({
			name = "Auto Walk", desc = "Keeps walking where the camera faces",
			key = "autowalk", color = Color3.fromRGB(180, 130, 255), order = 36, parent = extra, callback = setAutoWalk,
		})
	end

	makeSection("GRAVITY PRESETS", 40, extra)
	local presets = { { "Moon Gravity (50)", 50 }, { "Low Gravity (100)", 100 }, { "Normal Gravity (196)", 196.2 }, { "Heavy Gravity (400)", 400 } }
	for i, p in ipairs(presets) do
		makeButtonRow({
			text = p[1], order = 40 + i, parent = extra,
			callback = function()
				workspace.Gravity = p[2]
				notify("Gravity " .. p[2])
			end,
		})
	end
end

----------------------------------------------------------------
-- MORE VISUALS (Visuals + World tabs)
----------------------------------------------------------------
do
	local vis = pages.Visuals
	makeSection("EXTRA ESP", 30, vis)

	local flags = { skeleton = false, heads = false }
	local cache = {}
	local conn
	local kMaxDist = 1500

	local function kill(d)
		if not d then return end
		if not pcall(function() d:Remove() end) then pcall(function() d:Destroy() end) end
	end

	local function clearPlayer(plr)
		local c = cache[plr]
		if not c then return end
		for _, l in ipairs(c.lines) do kill(l) end
		kill(c.dot)
		cache[plr] = nil
	end

	local function hideAll(c)
		for _, l in ipairs(c.lines) do l.Visible = false end
		c.dot.Visible = false
	end

	local function render()
		local cam = workspace.CurrentCamera
		if not cam then return end
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= player then
				local char = plr.Character
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				local hrp = char and char:FindFirstChild("HumanoidRootPart")
				local c = cache[plr]
				if not c then
					c = {
						lines = {}, joints = {}, char = nil,
						dot = Drawing.new("Circle"),
					}
					c.dot.Filled = true
					c.dot.NumSides = 20
					c.dot.Color = Color3.fromRGB(255, 80, 90)
					c.dot.Visible = false
					cache[plr] = c
				end

				if hum and hrp and hum.Health > 0 and (hrp.Position - cam.CFrame.Position).Magnitude <= kMaxDist
					and not (espTeamCheck and plr.Team ~= nil and plr.Team == player.Team) then

					-- rebuild joint list when the character changes
					if c.char ~= char then
						c.char = char
						c.joints = {}
						for _, m in ipairs(char:GetDescendants()) do
							if m:IsA("Motor6D") and m.Part0 and m.Part1 then
								c.joints[#c.joints + 1] = { m.Part0, m.Part1 }
							end
						end
						while #c.lines < #c.joints do
							local l = Drawing.new("Line")
							l.Thickness = 1.5
							l.Color = Color3.fromRGB(255, 255, 255)
							l.Visible = false
							c.lines[#c.lines + 1] = l
						end
					end

					if flags.skeleton then
						for i, j in ipairs(c.joints) do
							local l = c.lines[i]
							if j[1].Parent and j[2].Parent then
								local a, aOn = cam:WorldToViewportPoint(j[1].Position)
								local b, bOn = cam:WorldToViewportPoint(j[2].Position)
								if aOn and bOn then
									l.From = Vector2.new(a.X, a.Y)
									l.To = Vector2.new(b.X, b.Y)
									l.Visible = true
								else
									l.Visible = false
								end
							else
								l.Visible = false
							end
						end
						for i = #c.joints + 1, #c.lines do c.lines[i].Visible = false end
					else
						for _, l in ipairs(c.lines) do l.Visible = false end
					end

					local head = char:FindFirstChild("Head")
					if flags.heads and head then
						local sp, on = cam:WorldToViewportPoint(head.Position)
						if on then
							local dist = math.max(sp.Z, 1)
							c.dot.Position = Vector2.new(sp.X, sp.Y)
							c.dot.Radius = math.clamp(60 / dist, 2, 14)
							c.dot.Visible = true
						else
							c.dot.Visible = false
						end
					else
						c.dot.Visible = false
					end
				else
					hideAll(c)
				end
			end
		end
	end

	local function refresh()
		if (flags.skeleton or flags.heads) and hasDrawing then
			if not conn then conn = RunService.RenderStepped:Connect(render) end
		else
			disconnect(conn)
			conn = nil
			for plr in pairs(cache) do clearPlayer(plr) end
		end
	end
	onUnload(function()
		disconnect(conn)
		for plr in pairs(cache) do clearPlayer(plr) end
	end)
	track(Players.PlayerRemoving:Connect(clearPlayer))

	makeToggleRow({
		name = "Skeleton ESP", desc = "Lines along every joint (needs Drawing API)",
		key = "skeleton", color = Color3.fromRGB(255, 255, 255), order = 31, parent = vis,
		callback = function(on)
			if on and not hasDrawing then warn("[Ghosted Menu] No Drawing API for Skeleton ESP.") end
			flags.skeleton = on
			refresh()
		end,
	})
	makeToggleRow({
		name = "Head Dots", desc = "Red dot on every head (needs Drawing API)",
		key = "headdots", color = Color3.fromRGB(255, 80, 90), order = 32, parent = vis,
		callback = function(on)
			flags.heads = on
			refresh()
		end,
	})

	----------------------------------------------------------------
	local world = pages.World
	makeSection("SCREEN EFFECTS", 40, world)

	local cc, blur
	local function getCC()
		if not cc or not cc.Parent then
			cc = Instance.new("ColorCorrectionEffect")
			cc.Name = "GhostedCC"
			cc.Parent = Lighting
		end
		return cc
	end
	local function getBlur()
		if not blur or not blur.Parent then
			blur = Instance.new("BlurEffect")
			blur.Name = "GhostedBlur"
			blur.Size = 0
			blur.Parent = Lighting
		end
		return blur
	end
	onUnload(function()
		if cc then cc:Destroy() end
		if blur then blur:Destroy() end
	end)

	local _, setSat = makeSliderRow({
		name = "Saturation", key = "fxSat", min = -100, max = 100, default = 0,
		order = 41, parent = world, callback = function(v) getCC().Saturation = v / 100 end,
	})
	local _, setCon = makeSliderRow({
		name = "Contrast", key = "fxCon", min = -100, max = 100, default = 0,
		order = 42, parent = world, callback = function(v) getCC().Contrast = v / 100 end,
	})
	local _, setBri = makeSliderRow({
		name = "Brightness", key = "fxBri", min = -50, max = 50, default = 0,
		order = 43, parent = world, callback = function(v) getCC().Brightness = v / 100 end,
	})
	local _, setBlur = makeSliderRow({
		name = "Blur", key = "fxBlur", min = 0, max = 40, default = 0,
		order = 44, parent = world, callback = function(v) getBlur().Size = v end,
	})

	local function preset(name, sat, con, tint)
		return function()
			setSat(sat)
			setCon(con)
			getCC().TintColor = tint
			notify(name .. " look")
		end
	end
	makeButtonRow({ text = "Look: Noir",    order = 45, parent = world, callback = preset("Noir", -100, 25, Color3.new(1, 1, 1)) })
	makeButtonRow({ text = "Look: Vibrant", order = 46, parent = world, callback = preset("Vibrant", 60, 10, Color3.new(1, 1, 1)) })
	makeButtonRow({ text = "Look: Warm",    order = 47, parent = world, callback = preset("Warm", 15, 5, Color3.fromRGB(255, 220, 180)) })
	makeButtonRow({ text = "Look: Cold",    order = 48, parent = world, callback = preset("Cold", 10, 5, Color3.fromRGB(180, 215, 255)) })
	makeButtonRow({
		text = "Reset Screen Effects", order = 49, parent = world, color = Color3.fromRGB(120, 40, 50),
		callback = function()
			setSat(0) setCon(0) setBri(0) setBlur(0)
			if cc then cc.TintColor = Color3.new(1, 1, 1) end
			notify("Screen effects reset")
		end,
	})
end

----------------------------------------------------------------
-- MORE CONFIG
----------------------------------------------------------------
do
	local cfg = pages.Config
	makeSection("ADVANCED", 20, cfg)

	local function panic()
		for _, s in ipairs(toggleSetters) do pcall(s, false, true) end
		closeMenu()
		notify("Panic: everything off")
	end

	makeButtonRow({
		text = "Panic: turn everything off  (key: End)", order = 21, parent = cfg,
		color = Color3.fromRGB(120, 40, 50), callback = panic,
	})
	track(UserInputService.InputBegan:Connect(function(input, processed)
		if processed or rebinding or bindingFeature then return end
		if input.KeyCode == Enum.KeyCode.End then panic() end
	end))

	makeButtonRow({
		text = "Reset Menu Position", order = 22, parent = cfg,
		callback = function()
			mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
			toggleBtn.Position = UDim2.new(0, 20, 0.5, -kToggleBtnSize / 2)
			notify("Positions reset")
		end,
	})
	makeButtonRow({
		text = "Copy Settings (JSON)", order = 23, parent = cfg,
		callback = function()
			local ok, json = pcall(function() return HttpService:JSONEncode(settings) end)
			if ok then copyText(json, "Settings") else notify("Couldn't encode settings") end
		end,
	})
	makeButtonRow({
		text = "Delete Saved Settings File", order = 24, parent = cfg, color = Color3.fromRGB(120, 40, 50),
		callback = function()
			if typeof(delfile) == "function" and canFile and isfile(kSaveFile) then
				pcall(delfile, kSaveFile)
				notify("Saved file deleted (reload to reset)")
			else
				notify("Nothing to delete / unsupported")
			end
		end,
	})
end

----------------------------------------------------------------
-- COMBAT TAB
----------------------------------------------------------------
do
	local combatPage = pages.Combat

	local function isEnemy(plr)
		if plr == player then return false end
		if espTeamCheck and plr.Team ~= nil and plr.Team == player.Team then return false end
		return true
	end

	makeSection("HITBOXES", 0, combatPage)

	-- HITBOX EXPANDER
	do
		local conn
		local size = 8
		local orig = setmetatable({}, { __mode = "k" })
		local function restore()
			for part, o in pairs(orig) do
				if part.Parent then
					pcall(function()
						part.Size = o.Size
						part.Transparency = o.Transparency
						part.CanCollide = o.CanCollide
					end)
				end
				orig[part] = nil
			end
		end
		local function setHitbox(on)
			disconnect(conn)
			conn = nil
			restore()
			if not on then return end
			conn = RunService.Heartbeat:Connect(function()
				for _, plr in ipairs(Players:GetPlayers()) do
					local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
					if hrp then
						if isEnemy(plr) then
							if not orig[hrp] then
								orig[hrp] = { Size = hrp.Size, Transparency = hrp.Transparency, CanCollide = hrp.CanCollide }
							end
							hrp.Size = Vector3.new(size, size, size)
							hrp.Transparency = 0.75
							hrp.CanCollide = false
						elseif orig[hrp] then
							local o = orig[hrp]
							hrp.Size, hrp.Transparency, hrp.CanCollide = o.Size, o.Transparency, o.CanCollide
							orig[hrp] = nil
						end
					end
				end
			end)
		end
		onUnload(restore)
		makeToggleRow({
			name = "Hitbox Expander", desc = "Enlarges enemy root parts (client side)",
			key = "hitbox", color = Color3.fromRGB(255, 80, 80), order = 1, parent = combatPage, callback = setHitbox,
		})
		makeSliderRow({
			name = "Hitbox Size", key = "hitboxSize", min = 3, max = 30, default = 8,
			order = 2, parent = combatPage, callback = function(v) size = v end,
		})
	end

	----------------------------------------------------------------
	makeSection("AUTOMATION", 5, combatPage)

	-- AUTO ATTACK (equipped tool)
	do
		local conn
		local range = 12
		local function setAuto(on)
			disconnect(conn)
			conn = nil
			if not on then return end
			local acc = 0
			conn = RunService.Heartbeat:Connect(function(dt)
				acc = acc + dt
				if acc < 0.1 then return end
				acc = 0
				local char = player.Character
				local hrp = char and char:FindFirstChild("HumanoidRootPart")
				local tool = char and char:FindFirstChildOfClass("Tool")
				if not (hrp and tool) then return end
				for _, plr in ipairs(Players:GetPlayers()) do
					if isEnemy(plr) then
						local th = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
						local thm = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
						if th and thm and thm.Health > 0 and (th.Position - hrp.Position).Magnitude <= range then
							pcall(function() tool:Activate() end)
							break
						end
					end
				end
			end)
		end
		makeToggleRow({
			name = "Auto Attack", desc = "Swings your equipped tool when someone is close",
			key = "autoattack", color = Color3.fromRGB(255, 150, 60), order = 6, parent = combatPage, callback = setAuto,
		})
		makeSliderRow({
			name = "Attack Range", key = "attackRange", min = 4, max = 40, default = 12,
			order = 7, parent = combatPage, callback = function(v) range = v end,
		})
	end

	-- LOW HEALTH ALERT
	do
		local conn
		local threshold = 30
		local lastAlert = 0
		local function setAlert(on)
			disconnect(conn)
			conn = nil
			if not on then return end
			conn = RunService.Heartbeat:Connect(function()
				local hum = getHumanoid()
				if not hum or hum.MaxHealth <= 0 or hum.Health <= 0 then return end
				if hum.Health / hum.MaxHealth * 100 < threshold and os.clock() - lastAlert > 5 then
					lastAlert = os.clock()
					notify("Low health: " .. math.floor(hum.Health))
				end
			end)
		end
		makeToggleRow({
			name = "Low Health Alert", desc = "Toast when your health drops",
			key = "lowhealth", color = Color3.fromRGB(255, 100, 110), order = 8, parent = combatPage, callback = setAlert,
		})
		makeSliderRow({
			name = "Alert Below %", key = "lowHealthPct", min = 5, max = 90, default = 30,
			order = 9, parent = combatPage, callback = function(v) threshold = v end,
		})
	end

	----------------------------------------------------------------
	makeSection("TARGET", 15, combatPage)

	-- TARGET INFO HUD
	do
		local frame = Instance.new("Frame")
		frame.Name = "TargetHud"
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.new(0.5, 0, 0.72, 0)
		frame.Size = UDim2.new(0, 210, 0, 54)
		frame.BackgroundColor3 = Color3.fromRGB(16, 16, 22)
		frame.BackgroundTransparency = 0.15
		frame.BorderSizePixel = 0
		frame.Visible = false
		frame.Parent = screenGui
		addCorner(frame, 8)
		do
			local s = addStroke(frame, accent, 1, 0.5)
			bindAccent(s, "Color")
		end

		local nameLbl = Instance.new("TextLabel")
		nameLbl.Size = UDim2.new(1, -16, 0, 20)
		nameLbl.Position = UDim2.new(0, 8, 0, 4)
		nameLbl.BackgroundTransparency = 1
		nameLbl.TextColor3 = Color3.new(1, 1, 1)
		nameLbl.Font = Enum.Font.GothamBold
		nameLbl.TextSize = 13
		nameLbl.TextXAlignment = Enum.TextXAlignment.Left
		nameLbl.Text = ""
		nameLbl.Parent = frame

		local infoLbl = Instance.new("TextLabel")
		infoLbl.Size = UDim2.new(1, -16, 0, 14)
		infoLbl.Position = UDim2.new(0, 8, 0, 22)
		infoLbl.BackgroundTransparency = 1
		infoLbl.TextColor3 = kTextDim
		infoLbl.Font = Enum.Font.Gotham
		infoLbl.TextSize = 11
		infoLbl.TextXAlignment = Enum.TextXAlignment.Left
		infoLbl.Text = ""
		infoLbl.Parent = frame

		local barBack = Instance.new("Frame")
		barBack.Position = UDim2.new(0, 8, 1, -11)
		barBack.Size = UDim2.new(1, -16, 0, 5)
		barBack.BackgroundColor3 = kSwitchOff
		barBack.BorderSizePixel = 0
		barBack.Parent = frame
		addCorner(barBack, -1)
		local bar = Instance.new("Frame")
		bar.Size = UDim2.new(1, 0, 1, 0)
		bar.BackgroundColor3 = Color3.fromRGB(80, 255, 120)
		bar.BorderSizePixel = 0
		bar.Parent = barBack
		addCorner(bar, -1)

		local conn
		local function setHud(on)
			disconnect(conn)
			conn = nil
			frame.Visible = false
			if not on then return end
			local acc = 0
			conn = RunService.Heartbeat:Connect(function(dt)
				acc = acc + dt
				if acc < 0.08 then return end
				acc = 0
				local cam = workspace.CurrentCamera
				if not cam then return end
				local vp = cam.ViewportSize
				local center = Vector2.new(vp.X / 2, vp.Y / 2)
				local best, bestD
				for _, plr in ipairs(Players:GetPlayers()) do
					if plr ~= player then
						local head = plr.Character and (plr.Character:FindFirstChild("Head") or plr.Character:FindFirstChild("HumanoidRootPart"))
						local hum = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
						if head and hum and hum.Health > 0 then
							local sp, onScreen = cam:WorldToViewportPoint(head.Position)
							if onScreen then
								local d = (Vector2.new(sp.X, sp.Y) - center).Magnitude
								if d < 250 and (not bestD or d < bestD) then best, bestD = plr, d end
							end
						end
					end
				end
				if best then
					local hum = best.Character:FindFirstChildOfClass("Humanoid")
					local hrp = best.Character:FindFirstChild("HumanoidRootPart")
					local pct = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
					local dist = hrp and (hrp.Position - cam.CFrame.Position).Magnitude or 0
					nameLbl.Text = best.DisplayName
					infoLbl.Text = string.format("%d / %d HP   -   %d studs", hum.Health, hum.MaxHealth, dist)
					bar.Size = UDim2.new(pct, 0, 1, 0)
					bar.BackgroundColor3 = Color3.fromRGB(255 * (1 - pct), 255 * pct, 60)
					frame.Visible = true
				else
					frame.Visible = false
				end
			end)
		end
		onUnload(function() frame:Destroy() end)
		makeToggleRow({
			name = "Target Info", desc = "Name, health and distance of who you aim at",
			key = "targetinfo", color = Color3.fromRGB(90, 200, 255), order = 16, parent = combatPage, callback = setHud,
		})
	end
end

----------------------------------------------------------------
-- SERVER TAB
----------------------------------------------------------------
do
	local serverPage = pages.Server
	local MarketplaceService = game:GetService("MarketplaceService")

	makeSection("THIS SERVER", 0, serverPage)

	local function infoRow(order, title)
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 30)
		row.BackgroundColor3 = kRowBg
		row.LayoutOrder = order
		row.Parent = serverPage
		addCorner(row, 8)

		local a = Instance.new("TextLabel")
		a.Size = UDim2.new(0, 100, 1, 0)
		a.Position = UDim2.new(0, 12, 0, 0)
		a.BackgroundTransparency = 1
		a.Text = title
		a.TextColor3 = kTextDim
		a.Font = Enum.Font.GothamBold
		a.TextSize = 12
		a.TextXAlignment = Enum.TextXAlignment.Left
		a.Parent = row

		local b = Instance.new("TextLabel")
		b.Size = UDim2.new(1, -120, 1, 0)
		b.Position = UDim2.new(0, 112, 0, 0)
		b.BackgroundTransparency = 1
		b.Text = "..."
		b.TextColor3 = Color3.fromRGB(230, 230, 235)
		b.Font = Enum.Font.Gotham
		b.TextSize = 12
		b.TextXAlignment = Enum.TextXAlignment.Left
		b.TextTruncate = Enum.TextTruncate.AtEnd
		b.Parent = row
		return b
	end

	local gameLbl   = infoRow(1, "Game")
	local placeLbl  = infoRow(2, "Place ID")
	local jobLbl    = infoRow(3, "Job ID")
	local playerLbl = infoRow(4, "Players")
	local upLbl     = infoRow(5, "Server Uptime")
	local pingLbl   = infoRow(6, "Ping")

	placeLbl.Text = tostring(game.PlaceId)
	jobLbl.Text = (game.JobId ~= "" and game.JobId) or "(studio / none)"
	task.spawn(function()
		local ok, info = pcall(function() return MarketplaceService:GetProductInfo(game.PlaceId) end)
		gameLbl.Text = (ok and info and info.Name) or "unknown"
	end)

	do
		local acc = 1
		track(RunService.Heartbeat:Connect(function(dt)
			if not serverPage.Visible then return end
			acc = acc + dt
			if acc < 1 then return end
			acc = 0
			playerLbl.Text = #Players:GetPlayers() .. " / " .. Players.MaxPlayers
			local t = math.floor(workspace.DistributedGameTime)
			upLbl.Text = string.format("%dh %dm %ds", math.floor(t / 3600), math.floor(t / 60) % 60, t % 60)
			local ping = 0
			pcall(function() ping = math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue() + 0.5) end)
			pingLbl.Text = ping .. " ms"
		end))
	end

	----------------------------------------------------------------
	makeSection("ACTIONS", 10, serverPage)

	makeButtonRow({
		text = "Copy Join Script", order = 11, parent = serverPage,
		callback = function()
			copyText(string.format(
				'game:GetService("TeleportService"):TeleportToPlaceInstance(%d, "%s", game.Players.LocalPlayer)',
				game.PlaceId, game.JobId), "Join script")
		end,
	})

	local hopBusy = false
	local function hop(order, label)
		if hopBusy then return end
		hopBusy = true
		notify("Searching for " .. label .. " server...")
		task.spawn(function()
			local picked
			local ok, body = pcall(function()
				return game:HttpGet("https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=" .. order .. "&limit=100")
			end)
			if ok and type(body) == "string" then
				local okJ, data = pcall(function() return HttpService:JSONDecode(body) end)
				if okJ and type(data) == "table" and type(data.data) == "table" then
					for _, srv in ipairs(data.data) do
						if srv.id ~= game.JobId and type(srv.playing) == "number"
							and type(srv.maxPlayers) == "number" and srv.playing < srv.maxPlayers then
							picked = srv.id
							break
						end
					end
				end
			end
			if picked then
				notify("Hopping...")
				pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, picked, player) end)
			else
				notify("No server found (executor needs HttpGet)")
			end
			task.wait(2)
			hopBusy = false
		end)
	end
	makeButtonRow({ text = "Hop to Smallest Server", order = 12, parent = serverPage, callback = function() hop("Asc", "smallest") end })
	makeButtonRow({ text = "Hop to Fullest Server",  order = 13, parent = serverPage, callback = function() hop("Desc", "fullest") end })
end

----------------------------------------------------------------
-- QUICK SLOTS (Tools tab)
----------------------------------------------------------------
do
	local tools = pages.Tools
	makeSection("QUICK SLOTS  (Alt+1/2/3 to go)", 40, tools)

	local slots = {}
	local function hrpNow()
		return player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	end
	local function save(i)
		local hrp = hrpNow()
		if not hrp then notify("No character") return end
		slots[i] = hrp.CFrame
		notify("Slot " .. i .. " saved")
	end
	local function go(i)
		local hrp = hrpNow()
		if not hrp then notify("No character") return end
		if not slots[i] then notify("Slot " .. i .. " is empty") return end
		hrp.CFrame = slots[i]
		notify("Slot " .. i)
	end
	for i = 1, 3 do
		makeButtonRow({ text = "Save Slot " .. i, order = 40 + i * 2 - 1, parent = tools, callback = function() save(i) end })
		makeButtonRow({ text = "Go to Slot " .. i, order = 40 + i * 2,     parent = tools, callback = function() go(i) end })
	end

	local keys = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three }
	track(UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt) then return end
		for i, k in ipairs(keys) do
			if input.KeyCode == k then go(i) end
		end
	end))
end

----------------------------------------------------------------
-- PRESETS TAB
----------------------------------------------------------------
do
	local presetPage = pages.Presets

	local function applyKeys(keys, label)
		for _, e in pairs(featureToggles) do pcall(e.set, false, true) end
		local n = 0
		for _, key in ipairs(keys) do
			local e = featureToggles[key]
			if e then pcall(e.set, true, true) n = n + 1 end
		end
		saveSettings()
		notify(label .. ": " .. n .. " features on")
	end

	makeSection("QUICK PROFILES", 0, presetPage)

	local profiles = {
		{ "PvP", { "espBoxes", "espNames", "espHealth", "espDistance", "chams", "teamCheck", "aimbot", "triggerbot",
			"crosshair", "antifling", "noragdoll", "targetinfo", "hitbox" } },
		{ "Explorer", { "fly", "noclip", "fullbright", "stats", "infohud", "antiafk", "infjump", "fallclamp" } },
		{ "Speedrun", { "speed", "highjump", "infjump", "bhop", "sprint", "dash", "fallclamp", "antivoid", "glide" } },
		{ "ESP Only", { "espBoxes", "espNames", "espHealth", "espDistance", "espTracers", "chams", "skeleton", "headdots", "teamCheck" } },
		{ "AFK / Chill", { "antiafk", "fpsboost", "stats", "antivoid" } },
		{ "Photo Mode", { "freecam", "fullbright", "nofog", "hidechat", "hidelist", "hidebackpack", "hidehealth" } },
		{ "Grinding", { "antiafk", "autoclick", "glide", "fallclamp", "antivoid", "fpsboost", "instantprompts" } },
	}
	for i, p in ipairs(profiles) do
		makeButtonRow({
			text = "Load: " .. p[1], order = i, parent = presetPage,
			callback = function() applyKeys(p[2], p[1]) end,
		})
	end
	makeButtonRow({
		text = "Everything Off", order = 10, parent = presetPage, color = Color3.fromRGB(120, 40, 50),
		callback = function() applyKeys({}, "All off") end,
	})

	----------------------------------------------------------------
	makeSection("MY PRESETS", 20, presetPage)
	for i = 1, 3 do
		local id = tostring(i)
		makeButtonRow({
			text = "Save Current Setup to Slot " .. i, order = 20 + i * 2 - 1, parent = presetPage,
			callback = function()
				local list = {}
				for key, e in pairs(featureToggles) do
					if e.get() then list[#list + 1] = key end
				end
				settings.presets[id] = list
				saveSettings()
				notify("Saved " .. #list .. " features to slot " .. i)
			end,
		})
		makeButtonRow({
			text = "Load My Slot " .. i, order = 20 + i * 2, parent = presetPage,
			callback = function()
				local list = settings.presets[id]
				if type(list) ~= "table" then notify("Slot " .. i .. " is empty") return end
				applyKeys(list, "Slot " .. i)
			end,
		})
	end
end

----------------------------------------------------------------
-- KEYBINDS TAB
----------------------------------------------------------------
do
	local bindPage = pages.Keybinds

	makeSection("ACTIVE KEYBINDS", 0, bindPage)

	local rows = {}
	local lastSnap = ""

	local function snapshot()
		local t = {}
		for key, k in pairs(settings.binds) do t[#t + 1] = key .. "=" .. k end
		table.sort(t)
		return table.concat(t, ";")
	end

	local function rebuild()
		for _, r in ipairs(rows) do r:Destroy() end
		rows = {}
		local keys = {}
		for key in pairs(settings.binds) do keys[#keys + 1] = key end
		table.sort(keys)
		if #keys == 0 then
			local lbl = Instance.new("TextLabel")
			lbl.Size = UDim2.new(1, 0, 0, 40)
			lbl.BackgroundTransparency = 1
			lbl.Text = "No keybinds yet. Right-click any toggle (PC) and press a key."
			lbl.TextColor3 = kTextDim
			lbl.Font = Enum.Font.Gotham
			lbl.TextSize = 12
			lbl.TextWrapped = true
			lbl.LayoutOrder = 10
			lbl.Parent = bindPage
			rows[1] = lbl
			return
		end
		for i, key in ipairs(keys) do
			local e = featureToggles[key]
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, 0, 0, 36)
			row.BackgroundColor3 = kRowBg
			row.LayoutOrder = 10 + i
			row.Parent = bindPage
			addCorner(row, 8)
			rows[#rows + 1] = row

			local keyLbl = Instance.new("TextLabel")
			keyLbl.Size = UDim2.new(0, 70, 1, 0)
			keyLbl.Position = UDim2.new(0, 12, 0, 0)
			keyLbl.BackgroundTransparency = 1
			keyLbl.Text = "[" .. settings.binds[key] .. "]"
			keyLbl.TextColor3 = accent
			keyLbl.Font = Enum.Font.GothamBold
			keyLbl.TextSize = 13
			keyLbl.TextXAlignment = Enum.TextXAlignment.Left
			keyLbl.Parent = row

			local nameLbl = Instance.new("TextLabel")
			nameLbl.Size = UDim2.new(1, -150, 1, 0)
			nameLbl.Position = UDim2.new(0, 84, 0, 0)
			nameLbl.BackgroundTransparency = 1
			nameLbl.Text = (e and e.name) or key
			nameLbl.TextColor3 = Color3.fromRGB(230, 230, 235)
			nameLbl.Font = Enum.Font.Gotham
			nameLbl.TextSize = 13
			nameLbl.TextXAlignment = Enum.TextXAlignment.Left
			nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
			nameLbl.Parent = row

			local clear = Instance.new("TextButton")
			clear.AnchorPoint = Vector2.new(1, 0.5)
			clear.Position = UDim2.new(1, -8, 0.5, 0)
			clear.Size = UDim2.new(0, 52, 0, 24)
			clear.BackgroundColor3 = Color3.fromRGB(120, 40, 50)
			clear.Text = "Clear"
			clear.TextColor3 = Color3.new(1, 1, 1)
			clear.Font = Enum.Font.GothamBold
			clear.TextSize = 11
			clear.AutoButtonColor = false
			clear.Parent = row
			addCorner(clear, 6)
			track(clear.MouseButton1Click:Connect(function()
				settings.binds[key] = nil
				saveSettings()
				refreshBindTag(key)
				rebuild()
				lastSnap = snapshot()
			end))
		end
	end
	rebuild()
	lastSnap = snapshot()

	do
		local acc = 0
		track(RunService.Heartbeat:Connect(function(dt)
			if not bindPage.Visible then return end
			acc = acc + dt
			if acc < 0.4 then return end
			acc = 0
			local s = snapshot()
			if s ~= lastSnap then
				lastSnap = s
				rebuild()
			end
		end))
	end

	makeButtonRow({
		text = "Clear All Keybinds", order = 5, parent = bindPage, color = Color3.fromRGB(120, 40, 50),
		callback = function()
			settings.binds = {}
			for key in pairs(featureToggles) do refreshBindTag(key) end
			saveSettings()
			rebuild()
			lastSnap = snapshot()
			notify("All keybinds cleared")
		end,
	})

	----------------------------------------------------------------
	-- ON-SCREEN OVERLAY
	local frame = Instance.new("Frame")
	frame.Name = "BindHud"
	frame.AnchorPoint = Vector2.new(1, 0)
	frame.Position = UDim2.new(1, -8, 0, 8)
	frame.Size = UDim2.new(0, 200, 0, 24)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundColor3 = Color3.fromRGB(16, 16, 22)
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = screenGui
	addCorner(frame, 8)
	do
		local s = addStroke(frame, accent, 1, 0.6)
		bindAccent(s, "Color")
		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, 6)
		pad.PaddingBottom = UDim.new(0, 6)
		pad.PaddingLeft = UDim.new(0, 8)
		pad.PaddingRight = UDim.new(0, 8)
		pad.Parent = frame
	end
	local hudLbl = Instance.new("TextLabel")
	hudLbl.Size = UDim2.new(1, 0, 0, 0)
	hudLbl.AutomaticSize = Enum.AutomaticSize.Y
	hudLbl.BackgroundTransparency = 1
	hudLbl.RichText = true
	hudLbl.TextColor3 = Color3.fromRGB(230, 230, 235)
	hudLbl.Font = Enum.Font.GothamBold
	hudLbl.TextSize = 12
	hudLbl.TextXAlignment = Enum.TextXAlignment.Left
	hudLbl.TextYAlignment = Enum.TextYAlignment.Top
	hudLbl.Text = ""
	hudLbl.Parent = frame

	local conn
	local function setHud(on)
		disconnect(conn)
		conn = nil
		frame.Visible = on
		if not on then return end
		local acc = 1
		conn = RunService.Heartbeat:Connect(function(dt)
			acc = acc + dt
			if acc < 0.25 then return end
			acc = 0
			local keys = {}
			for key in pairs(settings.binds) do keys[#keys + 1] = key end
			table.sort(keys)
			if #keys == 0 then
				hudLbl.Text = "no keybinds set"
				return
			end
			local lines = {}
			for _, key in ipairs(keys) do
				local e = featureToggles[key]
				local state = e and e.get()
				lines[#lines + 1] = string.format('[%s] %s  <font color="%s">%s</font>',
					settings.binds[key], (e and e.name) or key,
					state and "#50e880" or "#888899", state and "ON" or "off")
			end
			hudLbl.Text = table.concat(lines, "\n")
		end)
	end
	onUnload(function() frame:Destroy() end)
	makeToggleRow({
		name = "Keybind Overlay", desc = "Shows your keybinds and their state on screen",
		opt = "bindHud", color = Color3.fromRGB(190, 190, 255), order = 2, parent = bindPage, callback = setHud,
	})
end

----------------------------------------------------------------
-- THEMES TAB
----------------------------------------------------------------
do
	local themePage = pages.Themes

	local function applyAccentColor(c, full)
		accent = c
		for _, e in ipairs(accentTargets) do pcall(function() e[1][e[2]] = accent end) end
		if full then
			for _, cb in ipairs(accentCallbacks) do pcall(cb, accent) end
		end
	end

	local function restorePreset()
		local t = themes[settings.accent] or themes[1]
		applyAccentColor(t.color, true)
	end

	makeSection("CUSTOM ACCENT", 0, themePage)

	local rgb = { 160, 150, 255 }
	local customOn = false
	local function applyCustom()
		if customOn then applyAccentColor(Color3.fromRGB(rgb[1], rgb[2], rgb[3]), true) end
	end

	makeToggleRow({
		name = "Use Custom Accent", desc = "Overrides the swatches with the RGB below",
		key = "customaccent", color = Color3.fromRGB(255, 120, 200), order = 1, parent = themePage,
		callback = function(on)
			customOn = on
			if on then applyCustom() else restorePreset() end
		end,
	})
	makeSliderRow({
		name = "Red", key = "themeR", min = 0, max = 255, default = 160, order = 2, parent = themePage,
		callback = function(v) rgb[1] = v applyCustom() end,
	})
	makeSliderRow({
		name = "Green", key = "themeG", min = 0, max = 255, default = 150, order = 3, parent = themePage,
		callback = function(v) rgb[2] = v applyCustom() end,
	})
	makeSliderRow({
		name = "Blue", key = "themeB", min = 0, max = 255, default = 255, order = 4, parent = themePage,
		callback = function(v) rgb[3] = v applyCustom() end,
	})

	makeSection("EFFECTS", 10, themePage)

	-- RAINBOW ACCENT
	do
		local conn
		local function setRainbow(on)
			disconnect(conn)
			conn = nil
			if on then
				local acc = 0
				conn = RunService.Heartbeat:Connect(function(dt)
					acc = acc + dt
					local full = false
					if acc >= 0.5 then acc = 0 full = true end
					applyAccentColor(Color3.fromHSV((os.clock() * 0.15) % 1, 0.65, 1), full)
				end)
			elseif customOn then
				applyCustom()
			else
				restorePreset()
			end
		end
		onUnload(function() disconnect(conn) end)
		makeToggleRow({
			name = "Rainbow Accent", desc = "Menu color slowly cycles",
			key = "rainbowaccent", color = Color3.fromRGB(255, 120, 200), order = 11, parent = themePage, callback = setRainbow,
		})
	end

	makeButtonRow({
		text = "Random Accent", order = 12, parent = themePage,
		callback = function()
			local c = Color3.fromHSV(math.random(), 0.6 + math.random() * 0.3, 1)
			rgb = { math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255) }
			applyAccentColor(c, true)
			notify("Random accent")
		end,
	})
	makeButtonRow({
		text = "Back to Preset Accent", order = 13, parent = themePage,
		callback = function()
			restorePreset()
			notify("Preset accent restored")
		end,
	})

	makeSection("MENU TITLE", 20, themePage)
	do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 38)
		row.BackgroundColor3 = kRowBg
		row.LayoutOrder = 21
		row.Parent = themePage
		addCorner(row, 8)

		local box = Instance.new("TextBox")
		box.Size = UDim2.new(1, -24, 1, 0)
		box.Position = UDim2.new(0, 12, 0, 0)
		box.BackgroundTransparency = 1
		box.PlaceholderText = "custom menu title..."
		box.PlaceholderColor3 = kTextDim
		box.Text = ""
		box.TextColor3 = Color3.fromRGB(230, 230, 235)
		box.Font = Enum.Font.Gotham
		box.TextSize = 14
		box.TextXAlignment = Enum.TextXAlignment.Left
		box.ClearTextOnFocus = false
		box.Parent = row
		track(box.FocusLost:Connect(function()
			if box.Text ~= "" then titleLabel.Text = box.Text end
		end))
	end
	makeButtonRow({
		text = "Reset Title", order = 22, parent = themePage,
		callback = function() titleLabel.Text = "Ghosted Menu" end,
	})
end

----------------------------------------------------------------
-- NOTES TAB
----------------------------------------------------------------
do
	local notesPage = pages.Notes
	makeSection("SCRATCHPAD  (saved with your settings)", 0, notesPage)

	local holder = Instance.new("Frame")
	holder.Size = UDim2.new(1, 0, 0, 240)
	holder.BackgroundColor3 = kRowBg
	holder.LayoutOrder = 1
	holder.Parent = notesPage
	addCorner(holder, 8)

	local box = Instance.new("TextBox")
	box.Size = UDim2.new(1, -20, 1, -16)
	box.Position = UDim2.new(0, 10, 0, 8)
	box.BackgroundTransparency = 1
	box.MultiLine = true
	box.TextWrapped = true
	box.ClearTextOnFocus = false
	box.PlaceholderText = "write anything here..."
	box.PlaceholderColor3 = kTextDim
	box.Name = "NotesBox"
	box.Text = settings.notes or ""
	box.TextColor3 = Color3.fromRGB(230, 230, 235)
	box.Font = Enum.Font.Gotham
	box.TextSize = 13
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.TextYAlignment = Enum.TextYAlignment.Top
	box.Parent = holder

	track(box.FocusLost:Connect(function()
		settings.notes = box.Text
		saveSettings()
	end))

	makeButtonRow({
		text = "Copy Notes", order = 2, parent = notesPage,
		callback = function()
			if box.Text == "" then notify("Notes are empty") return end
			copyText(box.Text, "Notes")
		end,
	})
	makeButtonRow({
		text = "Clear Notes", order = 3, parent = notesPage, color = Color3.fromRGB(120, 40, 50),
		callback = function()
			box.Text = ""
			settings.notes = ""
			saveSettings()
			notify("Notes cleared")
		end,
	})
end

----------------------------------------------------------------
-- EXTRAS FOR EXISTING TABS (part 1: Move, Visuals, Players, Misc)
----------------------------------------------------------------
local StarterGui = game:GetService("StarterGui")

-- MOVE
do
	local page = pages.Move
	makeSection("MORE MOVEMENT", 20, page)

	-- AUTO JUMP
	do
		local conn
		local function setAutoJump(on)
			disconnect(conn)
			conn = nil
			if not on then return end
			conn = RunService.Heartbeat:Connect(function()
				local hum = getHumanoid()
				if hum and hum.MoveDirection.Magnitude > 0 and hum.FloorMaterial ~= Enum.Material.Air then
					hum:ChangeState(Enum.HumanoidStateType.Jumping)
				end
			end)
		end
		makeToggleRow({
			name = "Auto Jump", desc = "Jumps automatically while you move",
			key = "autojump", color = Color3.fromRGB(90, 230, 150), order = 21, parent = page, callback = setAutoJump,
		})
	end

	local speeds = { { "Set Walk Speed: 16 (default)", 16 }, { "Set Walk Speed: 32", 32 }, { "Set Walk Speed: 64", 64 }, { "Set Walk Speed: 100", 100 } }
	for i, s in ipairs(speeds) do
		makeButtonRow({
			text = s[1], order = 21 + i, parent = page,
			callback = function()
				local hum = getHumanoid()
				if hum then hum.WalkSpeed = s[2] notify("WalkSpeed " .. s[2]) end
			end,
		})
	end
	makeButtonRow({
		text = "Teleport Up 50 Studs", order = 30, parent = page,
		callback = function()
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if hrp then hrp.CFrame = hrp.CFrame + Vector3.new(0, 50, 0) end
		end,
	})
	makeButtonRow({
		text = "Teleport Down 50 Studs", order = 31, parent = page,
		callback = function()
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if hrp then hrp.CFrame = hrp.CFrame - Vector3.new(0, 50, 0) end
		end,
	})
	makeButtonRow({
		text = "Reset Speed & Jump to Default", order = 32, parent = page, color = Color3.fromRGB(120, 40, 50),
		callback = function()
			local hum = getHumanoid()
			if hum then
				hum.WalkSpeed = 16
				pcall(function() hum.UseJumpPower = true end)
				hum.JumpPower = 50
				notify("Speed and jump reset")
			end
		end,
	})
end

-- VISUALS
do
	local page = pages.Visuals
	makeSection("LIGHTS & HELPERS", 60, page)

	-- SPOTLIGHT
	do
		local light
		local on_ = false
		local brightness = 3
		local function build()
			if light then light:Destroy() light = nil end
			if not on_ then return end
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if not hrp then return end
			light = Instance.new("PointLight")
			light.Range = 45
			light.Brightness = brightness
			light.Shadows = false
			light.Parent = hrp
		end
		track(player.CharacterAdded:Connect(function()
			if on_ then task.wait(0.5) build() end
		end))
		onUnload(function() on_ = false build() end)
		makeToggleRow({
			name = "Personal Light", desc = "A light that follows you",
			key = "personallight", color = Color3.fromRGB(255, 240, 150), order = 61, parent = page,
			callback = function(on) on_ = on build() end,
		})
		makeSliderRow({
			name = "Light Brightness", key = "lightBrightness", min = 1, max = 10, default = 3,
			order = 62, parent = page,
			callback = function(v)
				brightness = v
				if light then light.Brightness = v end
			end,
		})
	end

	-- NIGHT VISION
	do
		local fx
		local function setNV(on)
			if fx then fx:Destroy() fx = nil end
			if not on then return end
			fx = Instance.new("ColorCorrectionEffect")
			fx.Name = "GhostedNV"
			fx.TintColor = Color3.fromRGB(150, 255, 160)
			fx.Brightness = 0.18
			fx.Contrast = 0.25
			fx.Saturation = -0.3
			fx.Parent = Lighting
		end
		onUnload(function() setNV(false) end)
		makeToggleRow({
			name = "Night Vision", desc = "Green tint and brighter image",
			key = "nightvision", color = Color3.fromRGB(110, 255, 140), order = 63, parent = page, callback = setNV,
		})
	end

	-- HIGHLIGHT SELF
	do
		local hl, conn
		local function build()
			if hl then hl:Destroy() hl = nil end
			local char = player.Character
			if not char then return end
			hl = Instance.new("Highlight")
			hl.FillTransparency = 1
			hl.OutlineColor = accent
			hl.OutlineTransparency = 0
			hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			hl.Adornee = char
			hl.Parent = chamsFolder
		end
		local function setSelf(on)
			disconnect(conn)
			conn = nil
			if hl then hl:Destroy() hl = nil end
			if on then
				build()
				conn = player.CharacterAdded:Connect(function() task.wait(0.3) build() end)
			end
		end
		onUnload(function() setSelf(false) end)
		makeToggleRow({
			name = "Highlight Self", desc = "Outline around your own character",
			key = "highlightself", color = Color3.fromRGB(160, 150, 255), order = 64, parent = page, callback = setSelf,
		})
	end

	-- TOOL ESP
	do
		local conn
		local tags = {}
		local function clear()
			for tool, bb in pairs(tags) do bb:Destroy() tags[tool] = nil end
		end
		local function scan()
			local seen = {}
			for _, d in ipairs(workspace:GetDescendants()) do
				if d:IsA("Tool") then
					local handle = d:FindFirstChild("Handle")
					local m = d:FindFirstAncestorOfClass("Model")
					if handle and not (m and m:FindFirstChildOfClass("Humanoid")) then
						seen[d] = true
						if not tags[d] then
							local bb = Instance.new("BillboardGui")
							bb.Size = UDim2.fromOffset(110, 20)
							bb.AlwaysOnTop = true
							bb.StudsOffset = Vector3.new(0, 2, 0)
							bb.Adornee = handle
							bb.Parent = chamsFolder
							local lbl = Instance.new("TextLabel")
							lbl.Size = UDim2.new(1, 0, 1, 0)
							lbl.BackgroundTransparency = 1
							lbl.Text = d.Name
							lbl.TextColor3 = Color3.fromRGB(255, 220, 90)
							lbl.TextStrokeTransparency = 0.4
							lbl.Font = Enum.Font.GothamBold
							lbl.TextSize = 12
							lbl.Parent = bb
							tags[d] = bb
						end
					end
				end
			end
			for tool, bb in pairs(tags) do
				if not seen[tool] then bb:Destroy() tags[tool] = nil end
			end
		end
		local function setToolEsp(on)
			disconnect(conn)
			conn = nil
			clear()
			if not on then return end
			local acc = 10
			conn = RunService.Heartbeat:Connect(function(dt)
				acc = acc + dt
				if acc < 4 then return end
				acc = 0
				pcall(scan)
			end)
		end
		onUnload(function() setToolEsp(false) end)
		makeToggleRow({
			name = "Tool ESP", desc = "Labels tools lying around the map",
			key = "toolesp", color = Color3.fromRGB(255, 220, 90), order = 65, parent = page, callback = setToolEsp,
		})
	end
end

-- PLAYERS
do
	local page = pages.Players
	makeSection("FRIENDS & LISTS", 5000, page)

	-- FRIEND ALERT
	do
		local conn
		makeToggleRow({
			name = "Friend Alert", desc = "Toast when a friend joins the server",
			key = "friendalert", color = Color3.fromRGB(90, 230, 150), order = 5001, parent = page,
			callback = function(on)
				disconnect(conn)
				conn = nil
				if not on then return end
				conn = Players.PlayerAdded:Connect(function(p)
					task.spawn(function()
						local ok, isF = pcall(function() return player:IsFriendsWith(p.UserId) end)
						if ok and isF then notify("Friend joined: " .. p.DisplayName) end
					end)
				end)
			end,
		})
	end

	-- HIGHLIGHT FRIENDS
	do
		local conn
		local friends = {}
		local marks = {}
		local function clear()
			for plr, h in pairs(marks) do h:Destroy() marks[plr] = nil end
		end
		makeToggleRow({
			name = "Highlight Friends", desc = "Green outline on your friends",
			key = "highlightfriends", color = Color3.fromRGB(80, 255, 120), order = 5002, parent = page,
			callback = function(on)
				disconnect(conn)
				conn = nil
				clear()
				if not on then return end
				local acc = 5
				conn = RunService.Heartbeat:Connect(function(dt)
					acc = acc + dt
					if acc < 2 then return end
					acc = 0
					for _, p in ipairs(Players:GetPlayers()) do
						if p ~= player then
							if friends[p.UserId] == nil then
								friends[p.UserId] = false
								task.spawn(function()
									local ok, isF = pcall(function() return player:IsFriendsWith(p.UserId) end)
									friends[p.UserId] = ok and isF or false
								end)
							end
							if friends[p.UserId] and p.Character then
								local h = marks[p]
								if not h then
									h = Instance.new("Highlight")
									h.FillTransparency = 0.7
									h.FillColor = Color3.fromRGB(80, 255, 120)
									h.OutlineColor = Color3.fromRGB(80, 255, 120)
									h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
									h.Parent = chamsFolder
									marks[p] = h
								end
								if h.Adornee ~= p.Character then h.Adornee = p.Character end
							end
						end
					end
				end)
			end,
		})
		onUnload(function() disconnect(conn) clear() end)
	end

	makeButtonRow({
		text = "Copy All Usernames", order = 5003, parent = page,
		callback = function()
			local t = {}
			for _, p in ipairs(Players:GetPlayers()) do t[#t + 1] = p.Name end
			copyText(table.concat(t, "\n"), #t .. " usernames")
		end,
	})
	makeButtonRow({
		text = "Copy All Display Names", order = 5004, parent = page,
		callback = function()
			local t = {}
			for _, p in ipairs(Players:GetPlayers()) do t[#t + 1] = p.DisplayName end
			copyText(table.concat(t, "\n"), #t .. " display names")
		end,
	})
end

-- MISC
do
	local page = pages.Misc
	makeSection("INTERFACE & SAFETY", 100, page)

	local defs = {
		{ "Hide Chat", "hidechat", Enum.CoreGuiType.Chat },
		{ "Hide Player List", "hidelist", Enum.CoreGuiType.PlayerList },
		{ "Hide Backpack", "hidebackpack", Enum.CoreGuiType.Backpack },
		{ "Hide Health Bar", "hidehealth", Enum.CoreGuiType.Health },
	}
	for i, d in ipairs(defs) do
		makeToggleRow({
			name = d[1], desc = "Hides the default Roblox " .. string.lower(string.sub(d[1], 6)),
			key = d[2], color = Color3.fromRGB(190, 190, 255), order = 100 + i, parent = page,
			callback = function(on) pcall(function() StarterGui:SetCoreGuiEnabled(d[3], not on) end) end,
		})
	end
	onUnload(function()
		for _, d in ipairs(defs) do pcall(function() StarterGui:SetCoreGuiEnabled(d[3], true) end) end
	end)

	-- AUTO REJOIN ON KICK
	do
		local conn
		makeToggleRow({
			name = "Auto Rejoin", desc = "Rejoins the game if you get disconnected",
			key = "autorejoin", color = Color3.fromRGB(255, 200, 90), order = 110, parent = page,
			callback = function(on)
				disconnect(conn)
				conn = nil
				if not on then return end
				local GuiService = game:GetService("GuiService")
				conn = GuiService.ErrorMessageChanged:Connect(function()
					if GuiService:GetErrorMessage() ~= "" then
						task.wait(1)
						pcall(function() TeleportService:Teleport(game.PlaceId, player) end)
					end
				end)
			end,
		})
	end

	-- UNLOCK MOUSE
	do
		local conn
		makeToggleRow({
			name = "Unlock Mouse", desc = "Frees the cursor in games that lock it",
			key = "unlockmouse", color = Color3.fromRGB(130, 200, 255), order = 111, parent = page,
			callback = function(on)
				disconnect(conn)
				conn = nil
				if not on then return end
				conn = RunService.RenderStepped:Connect(function()
					UserInputService.MouseBehavior = Enum.MouseBehavior.Default
					UserInputService.MouseIconEnabled = true
				end)
			end,
		})
	end
end

----------------------------------------------------------------
-- EXTRAS FOR EXISTING TABS (part 2: Extra, Fun, World, Chat)
----------------------------------------------------------------
-- EXTRA
do
	local page = pages.Extra
	makeSection("BOOSTS", 60, page)

	-- ROCKET BOOST (hold R)
	do
		local conn
		local power = 60
		makeToggleRow({
			name = "Rocket Boost", desc = "Hold R to fly upward",
			key = "rocket", color = Color3.fromRGB(255, 120, 90), order = 61, parent = page,
			callback = function(on)
				disconnect(conn)
				conn = nil
				if not on then return end
				conn = RunService.Heartbeat:Connect(function()
					if UserInputService:GetFocusedTextBox() then return end
					if not UserInputService:IsKeyDown(Enum.KeyCode.R) then return end
					local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
					if hrp then
						local v = hrp.AssemblyLinearVelocity
						hrp.AssemblyLinearVelocity = Vector3.new(v.X, power, v.Z)
					end
				end)
			end,
		})
		makeSliderRow({
			name = "Rocket Power", key = "rocketPower", min = 20, max = 200, default = 60,
			order = 62, parent = page, callback = function(v) power = v end,
		})
	end

	makeButtonRow({ text = "Zero Gravity", order = 63, parent = page,
		callback = function() workspace.Gravity = 0 notify("Gravity 0") end })
	makeButtonRow({ text = "Reverse Gravity (float up)", order = 64, parent = page,
		callback = function() workspace.Gravity = -50 notify("Gravity -50") end })
end

-- FUN
do
	local page = pages.Fun
	makeSection("SILLY STUFF", 30, page)

	-- LOOK AT CURSOR
	do
		local conn
		makeToggleRow({
			name = "Face Cursor", desc = "Your character turns toward the mouse",
			key = "facecursor", color = Color3.fromRGB(255, 200, 90), order = 31, parent = page,
			callback = function(on)
				disconnect(conn)
				conn = nil
				local hum = getHumanoid()
				if hum then hum.AutoRotate = not on end
				if not on then return end
				local mouse = player:GetMouse()
				conn = RunService.Heartbeat:Connect(function()
					local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
					local hit = mouse.Hit
					if hrp and hit then
						local p = hit.Position
						hrp.CFrame = CFrame.lookAt(hrp.Position, Vector3.new(p.X, hrp.Position.Y, p.Z))
					end
				end)
			end,
		})
	end

	-- RAGDOLL SELF
	do
		local conn
		makeToggleRow({
			name = "Ragdoll Self", desc = "Go limp (PlatformStand)",
			key = "ragdollself", color = Color3.fromRGB(255, 120, 150), order = 32, parent = page,
			callback = function(on)
				disconnect(conn)
				conn = nil
				if on then
					conn = RunService.Heartbeat:Connect(function()
						local hum = getHumanoid()
						if hum then hum.PlatformStand = true end
					end)
				else
					local hum = getHumanoid()
					if hum then hum.PlatformStand = false end
				end
			end,
		})
	end

	-- RANDOM COLORS
	do
		local orig = setmetatable({}, { __mode = "k" })
		makeButtonRow({
			text = "Randomize Body Colors", order = 33, parent = page,
			callback = function()
				local char = player.Character
				if not char then return end
				for _, p in ipairs(char:GetDescendants()) do
					if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
						if orig[p] == nil then orig[p] = p.Color end
						p.Color = Color3.fromHSV(math.random(), 0.7, 1)
					end
				end
			end,
		})
		makeButtonRow({
			text = "Restore Body Colors", order = 34, parent = page,
			callback = function()
				for p, c in pairs(orig) do
					if p.Parent then pcall(function() p.Color = c end) end
					orig[p] = nil
				end
			end,
		})
	end
end

-- WORLD
do
	local page = pages.World
	makeSection("MORE WORLD", 60, page)

	-- SHADOWS OFF
	do
		local saved
		makeToggleRow({
			name = "Shadows Off", desc = "Turns global shadows off",
			key = "noshadows", color = Color3.fromRGB(190, 190, 255), order = 61, parent = page,
			callback = function(on)
				if on then
					saved = Lighting.GlobalShadows
					Lighting.GlobalShadows = false
				elseif saved ~= nil then
					Lighting.GlobalShadows = saved
					saved = nil
				end
			end,
		})
	end

	-- REMOVE CLOUDS
	do
		local saved
		makeToggleRow({
			name = "Remove Clouds", desc = "Hides the terrain clouds",
			key = "noclouds", color = Color3.fromRGB(190, 220, 255), order = 62, parent = page,
			callback = function(on)
				local clouds = workspace.Terrain:FindFirstChildOfClass("Clouds")
				if not clouds then return end
				if on then
					saved = clouds.Enabled
					clouds.Enabled = false
				elseif saved ~= nil then
					clouds.Enabled = saved
					saved = nil
				end
			end,
		})
	end

	local sun, bloom
	local function getSun()
		if not sun or not sun.Parent then
			sun = Instance.new("SunRaysEffect")
			sun.Name = "GhostedSunRays"
			sun.Parent = Lighting
		end
		return sun
	end
	local function getBloom()
		if not bloom or not bloom.Parent then
			bloom = Instance.new("BloomEffect")
			bloom.Name = "GhostedBloom"
			bloom.Size = 24
			bloom.Threshold = 0.8
			bloom.Intensity = 0
			bloom.Parent = Lighting
		end
		return bloom
	end
	onUnload(function()
		if sun then sun:Destroy() end
		if bloom then bloom:Destroy() end
	end)
	makeSliderRow({
		name = "Sun Rays", key = "sunRays", min = 0, max = 100, default = 0,
		order = 63, parent = page, callback = function(v) getSun().Intensity = v / 100 end,
	})
	makeSliderRow({
		name = "Bloom", key = "bloomAmt", min = 0, max = 100, default = 0,
		order = 64, parent = page, callback = function(v) getBloom().Intensity = v / 25 end,
	})
	makeSliderRow({
		name = "Water Transparency %", key = "waterTrans",
		min = 0, max = 100, default = math.clamp(math.floor(workspace.Terrain.WaterTransparency * 100 + 0.5), 0, 100),
		order = 65, parent = page,
		callback = function(v) workspace.Terrain.WaterTransparency = v / 100 end,
	})
end

-- CHAT
do
	local page = pages.Chat
	makeSection("ALERTS", 30, page)

	local keyword = ""
	do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 38)
		row.BackgroundColor3 = kRowBg
		row.LayoutOrder = 31
		row.Parent = page
		addCorner(row, 8)
		local box = Instance.new("TextBox")
		box.Size = UDim2.new(1, -24, 1, 0)
		box.Position = UDim2.new(0, 12, 0, 0)
		box.BackgroundTransparency = 1
		box.PlaceholderText = "alert keyword (optional)..."
		box.PlaceholderColor3 = kTextDim
		box.Text = ""
		box.TextColor3 = Color3.fromRGB(230, 230, 235)
		box.Font = Enum.Font.Gotham
		box.TextSize = 14
		box.TextXAlignment = Enum.TextXAlignment.Left
		box.ClearTextOnFocus = false
		box.Parent = row
		track(box.FocusLost:Connect(function() keyword = string.lower(box.Text) end))
	end

	do
		local hooks = {}
		local addedConn
		local function hook(plr)
			if plr == player or hooks[plr] then return end
			hooks[plr] = plr.Chatted:Connect(function(msg)
				local m = string.lower(msg)
				local hit = string.find(m, string.lower(player.Name), 1, true)
					or string.find(m, string.lower(player.DisplayName), 1, true)
					or (keyword ~= "" and string.find(m, keyword, 1, true))
				if hit then notify(plr.DisplayName .. ": " .. string.sub(msg, 1, 40)) end
			end)
		end
		makeToggleRow({
			name = "Mention Alert", desc = "Toast when your name or keyword is said",
			key = "mentionalert", color = Color3.fromRGB(255, 200, 90), order = 32, parent = page,
			callback = function(on)
				disconnect(addedConn)
				addedConn = nil
				for p, c in pairs(hooks) do disconnect(c) hooks[p] = nil end
				if on then
					for _, p in ipairs(Players:GetPlayers()) do hook(p) end
					addedConn = Players.PlayerAdded:Connect(hook)
				end
			end,
		})
	end
end

----------------------------------------------------------------
-- EXTRAS FOR EXISTING TABS (part 3: Tools, Combat, Server, Keybinds, Themes, Notes, Config)
----------------------------------------------------------------
-- TOOLS
do
	local page = pages.Tools
	makeSection("MORE TOOLS", 60, page)

	local function myHrp() return player.Character and player.Character:FindFirstChild("HumanoidRootPart") end

	makeButtonRow({
		text = "Grab Nearby Tools", order = 61, parent = page,
		callback = function()
			local hrp = myHrp()
			if not hrp then notify("No character") return end
			if typeof(firetouchinterest) ~= "function" then notify("Executor has no firetouchinterest") return end
			local n = 0
			for _, d in ipairs(workspace:GetDescendants()) do
				if d:IsA("Tool") then
					local handle = d:FindFirstChild("Handle")
					local m = d:FindFirstAncestorOfClass("Model")
					if handle and not (m and m:FindFirstChildOfClass("Humanoid"))
						and (handle.Position - hrp.Position).Magnitude <= 40 then
						pcall(firetouchinterest, hrp, handle, 0)
						task.wait()
						pcall(firetouchinterest, hrp, handle, 1)
						n = n + 1
					end
				end
			end
			notify(n > 0 and ("Touched " .. n .. " tools") or "No tools nearby")
		end,
	})
	makeButtonRow({
		text = "Drop All Tools", order = 62, parent = page,
		callback = function()
			local hrp = myHrp()
			local char = player.Character
			local bp = player:FindFirstChildOfClass("Backpack")
			if not (hrp and char) then return end
			local n = 0
			local function drop(container)
				if not container then return end
				for _, t in ipairs(container:GetChildren()) do
					if t:IsA("Tool") then
						t.Parent = workspace
						local h = t:FindFirstChild("Handle")
						if h then pcall(function() h.CFrame = hrp.CFrame * CFrame.new(0, 0, -4) end) end
						n = n + 1
					end
				end
			end
			drop(char)
			drop(bp)
			notify("Dropped " .. n .. " tools")
		end,
	})
	makeButtonRow({
		text = "Delete All My Tools (local)", order = 63, parent = page, color = Color3.fromRGB(120, 40, 50),
		callback = function()
			local n = 0
			for _, c in ipairs({ player.Character, player:FindFirstChildOfClass("Backpack") }) do
				for _, t in ipairs(c:GetChildren()) do
					if t:IsA("Tool") then t:Destroy() n = n + 1 end
				end
			end
			notify("Deleted " .. n .. " tools")
		end,
	})
	makeButtonRow({
		text = "Teleport to Camera Position", order = 64, parent = page,
		callback = function()
			local hrp, cam = myHrp(), workspace.CurrentCamera
			if hrp and cam then hrp.CFrame = cam.CFrame end
		end,
	})
end

-- COMBAT
do
	local page = pages.Combat
	makeSection("AWARENESS", 30, page)

	-- RADAR
	do
		local frame = Instance.new("Frame")
		frame.Name = "Radar"
		frame.AnchorPoint = Vector2.new(0, 1)
		frame.Position = UDim2.new(0, 12, 1, -12)
		frame.Size = UDim2.fromOffset(150, 150)
		frame.BackgroundColor3 = Color3.fromRGB(16, 16, 22)
		frame.BackgroundTransparency = 0.25
		frame.BorderSizePixel = 0
		frame.Visible = false
		frame.Parent = screenGui
		addCorner(frame, -1)
		do
			local s = addStroke(frame, accent, 1.5, 0.3)
			bindAccent(s, "Color")
		end
		local me = Instance.new("Frame")
		me.AnchorPoint = Vector2.new(0.5, 0.5)
		me.Position = UDim2.new(0.5, 0, 0.5, 0)
		me.Size = UDim2.fromOffset(7, 7)
		me.BackgroundColor3 = Color3.new(1, 1, 1)
		me.BorderSizePixel = 0
		me.Parent = frame
		addCorner(me, -1)

		local dots = {}
		local range = 150
		local conn
		local function setRadar(on)
			disconnect(conn)
			conn = nil
			frame.Visible = on
			if not on then return end
			conn = RunService.Heartbeat:Connect(function()
				local cam = workspace.CurrentCamera
				local myH = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if not (cam and myH) then return end
				local look = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z)
				if look.Magnitude < 0.01 then return end
				look = look.Unit
				local right = look:Cross(Vector3.yAxis)
				local radius = 70
				local used = 0
				for _, plr in ipairs(Players:GetPlayers()) do
					if plr ~= player then
						local th = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
						local hum = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
						if th and hum and hum.Health > 0 then
							used = used + 1
							local d = dots[used]
							if not d then
								d = Instance.new("Frame")
								d.AnchorPoint = Vector2.new(0.5, 0.5)
								d.Size = UDim2.fromOffset(6, 6)
								d.BorderSizePixel = 0
								d.Parent = frame
								addCorner(d, -1)
								dots[used] = d
							end
							local rel = th.Position - myH.Position
							local x = rel:Dot(right) / range * radius
							local y = -rel:Dot(look) / range * radius
							local v = Vector2.new(x, y)
							if v.Magnitude > radius then v = v.Unit * radius end
							d.Position = UDim2.new(0.5, v.X, 0.5, v.Y)
							local friendly = espTeamCheck and plr.Team ~= nil and plr.Team == player.Team
							d.BackgroundColor3 = friendly and Color3.fromRGB(90, 160, 255) or Color3.fromRGB(255, 80, 90)
							d.Visible = true
						end
					end
				end
				for i = used + 1, #dots do dots[i].Visible = false end
			end)
		end
		onUnload(function() frame:Destroy() end)
		makeToggleRow({
			name = "Radar", desc = "Mini-map of nearby players (bottom left)",
			key = "radar", color = Color3.fromRGB(90, 200, 255), order = 31, parent = page, callback = setRadar,
		})
		makeSliderRow({
			name = "Radar Range", key = "radarRange", min = 50, max = 500, default = 150,
			order = 32, parent = page, callback = function(v) range = v end,
		})
	end

	-- DEATH NOTIFIER
	do
		local conns = {}
		local function clear()
			for i = #conns, 1, -1 do disconnect(conns[i]) conns[i] = nil end
		end
		local function hookChar(plr, char)
			local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 5)
			if hum then
				conns[#conns + 1] = hum.Died:Connect(function() notify(plr.DisplayName .. " died") end)
			end
		end
		local function hookPlayer(plr)
			if plr == player then return end
			conns[#conns + 1] = plr.CharacterAdded:Connect(function(c) hookChar(plr, c) end)
			if plr.Character then task.spawn(hookChar, plr, plr.Character) end
		end
		makeToggleRow({
			name = "Death Notifier", desc = "Toast whenever someone dies",
			key = "deathnotify", color = Color3.fromRGB(255, 100, 110), order = 33, parent = page,
			callback = function(on)
				clear()
				if not on then return end
				for _, p in ipairs(Players:GetPlayers()) do hookPlayer(p) end
				conns[#conns + 1] = Players.PlayerAdded:Connect(hookPlayer)
			end,
		})
		onUnload(clear)
	end
end

-- SERVER
do
	local page = pages.Server
	makeSection("MORE", 20, page)
	makeButtonRow({
		text = "Copy Player List", order = 21, parent = page,
		callback = function()
			local lines = {}
			for _, p in ipairs(Players:GetPlayers()) do
				lines[#lines + 1] = string.format("%s (@%s)%s", p.DisplayName, p.Name, p.Team and (" - " .. p.Team.Name) or "")
			end
			copyText(table.concat(lines, "\n"), #lines .. " players")
		end,
	})
	makeButtonRow({
		text = "Copy Server Info", order = 22, parent = page,
		callback = function()
			copyText(string.format("PlaceId: %d\nJobId: %s\nPlayers: %d/%d",
				game.PlaceId, game.JobId, #Players:GetPlayers(), Players.MaxPlayers), "Server info")
		end,
	})
end

-- KEYBINDS
makeButtonRow({
	text = "Copy Keybind List", order = 6, parent = pages.Keybinds,
	callback = function()
		local t = {}
		for key, k in pairs(settings.binds) do
			local e = featureToggles[key]
			t[#t + 1] = "[" .. k .. "] " .. ((e and e.name) or key)
		end
		table.sort(t)
		if #t == 0 then notify("No keybinds") return end
		copyText(table.concat(t, "\n"), "Keybinds")
	end,
})

-- THEMES
do
	local page = pages.Themes
	makeSection("LOOK & FEEL", 30, page)

	local fonts = {
		Enum.Font.GothamBold, Enum.Font.Arcade, Enum.Font.SciFi, Enum.Font.Fantasy,
		Enum.Font.Code, Enum.Font.Bangers, Enum.Font.Cartoon, Enum.Font.Highway,
	}
	local fontIdx = 1
	makeButtonRow({
		text = "Cycle Title Font", order = 31, parent = page,
		callback = function()
			fontIdx = fontIdx % #fonts + 1
			titleLabel.Font = fonts[fontIdx]
			notify("Font: " .. fonts[fontIdx].Name)
		end,
	})

	local mainCorner = mainFrame:FindFirstChildOfClass("UICorner")
	local mainStroke = mainFrame:FindFirstChildOfClass("UIStroke")
	makeSliderRow({
		name = "Corner Roundness", key = "menuCorner", min = 0, max = 30, default = 14,
		order = 32, parent = page,
		callback = function(v) if mainCorner then mainCorner.CornerRadius = UDim.new(0, v) end end,
	})
	makeSliderRow({
		name = "Border Thickness", key = "menuBorder", min = 0, max = 6, default = 1,
		order = 33, parent = page,
		callback = function(v) if mainStroke then mainStroke.Thickness = v end end,
	})
	makeSliderRow({
		name = "Floating Ghost Size", key = "ghostBtnSize", min = 40, max = 100, default = kToggleBtnSize,
		order = 34, parent = page,
		callback = function(v) toggleBtn.Size = UDim2.new(0, v, 0, v) end,
	})
	makeToggleRow({
		name = "Hide Credit Line", desc = "Hides the 'made by' text in the title bar",
		key = "hidecredit", color = Color3.fromRGB(190, 190, 255), order = 35, parent = page,
		callback = function(on) creditLabel.Visible = not on end,
	})
end

-- NOTES
do
	local page = pages.Notes
	local function noteBox() return page:FindFirstChild("NotesBox", true) end
	makeSection("QUICK INSERT", 10, page)
	makeButtonRow({
		text = "Insert Timestamp", order = 11, parent = page,
		callback = function()
			local b = noteBox()
			if b then
				b.Text = b.Text .. (b.Text ~= "" and "\n" or "") .. os.date("[%Y-%m-%d %H:%M] ")
				settings.notes = b.Text
				saveSettings()
			end
		end,
	})
	makeButtonRow({
		text = "Insert My Coordinates", order = 12, parent = page,
		callback = function()
			local b = noteBox()
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if b and hrp then
				local p = hrp.Position
				b.Text = b.Text .. (b.Text ~= "" and "\n" or "") .. string.format("(%.0f, %.0f, %.0f) ", p.X, p.Y, p.Z)
				settings.notes = b.Text
				saveSettings()
			end
		end,
	})
	makeButtonRow({
		text = "Count Words", order = 13, parent = page,
		callback = function()
			local b = noteBox()
			if not b then return end
			local n = 0
			for _ in string.gmatch(b.Text, "%S+") do n = n + 1 end
			notify(n .. " words, " .. #b.Text .. " characters")
		end,
	})
end

-- CONFIG
do
	local page = pages.Config
	makeSection("EXTRA OPTIONS", 40, page)
	makeToggleRow({
		name = "Notification Sound", desc = "Soft ping with every toast",
		opt = "sounds", color = Color3.fromRGB(190, 190, 255), order = 41, parent = page, callback = function() end,
	})
	makeButtonRow({
		text = "Save Settings Now", order = 42, parent = page,
		callback = function()
			if not canFile then notify("Executor can't save files") return end
			pcall(function() writefile(kSaveFile, HttpService:JSONEncode(settings)) end)
			notify("Settings saved")
		end,
	})
end

----------------------------------------------------------------
-- CAMERA TAB
----------------------------------------------------------------
do
	local page = pages.Camera
	makeSection("VIEW", 0, page)

	-- ORBIT CAMERA
	do
		local conn, savedType
		local speed, dist, angle = 30, 15, 0
		local function stopOrbit()
			disconnect(conn)
			conn = nil
			local cam = workspace.CurrentCamera
			if cam and savedType then
				cam.CameraType = savedType
				local hum = getHumanoid()
				if hum then cam.CameraSubject = hum end
			end
			savedType = nil
		end
		local function setOrbit(on)
			stopOrbit()
			if not on then return end
			local cam = workspace.CurrentCamera
			if not cam then return end
			savedType = cam.CameraType
			cam.CameraType = Enum.CameraType.Scriptable
			conn = RunService.RenderStepped:Connect(function(dt)
				local c = workspace.CurrentCamera
				local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if not (c and hrp) then return end
				angle = angle + math.rad(speed) * dt
				local center = hrp.Position + Vector3.new(0, 2, 0)
				local offset = Vector3.new(math.sin(angle) * dist, dist * 0.3, math.cos(angle) * dist)
				c.CFrame = CFrame.lookAt(center + offset, center)
			end)
		end
		onUnload(stopOrbit)
		makeToggleRow({
			name = "Orbit Camera", desc = "Camera circles around your character",
			key = "orbitcam", color = Color3.fromRGB(110, 170, 255), order = 1, parent = page, callback = setOrbit,
		})
		makeSliderRow({
			name = "Orbit Speed", key = "orbitSpeed", min = 5, max = 120, default = 30,
			order = 2, parent = page, callback = function(v) speed = v end,
		})
		makeSliderRow({
			name = "Orbit Distance", key = "orbitDist", min = 5, max = 60, default = 15,
			order = 3, parent = page, callback = function(v) dist = v end,
		})
	end

	-- CINEMATIC BARS
	do
		local gui = Instance.new("ScreenGui")
		gui.Name = "GhostedBars"
		gui.ResetOnSpawn = false
		gui.IgnoreGuiInset = true
		gui.DisplayOrder = 10
		gui.Enabled = false
		gui.Parent = guiParent

		local top = Instance.new("Frame")
		top.Size = UDim2.new(1, 0, 0.12, 0)
		top.BackgroundColor3 = Color3.new(0, 0, 0)
		top.BorderSizePixel = 0
		top.Parent = gui
		local bottom = Instance.new("Frame")
		bottom.AnchorPoint = Vector2.new(0, 1)
		bottom.Position = UDim2.new(0, 0, 1, 0)
		bottom.Size = UDim2.new(1, 0, 0.12, 0)
		bottom.BackgroundColor3 = Color3.new(0, 0, 0)
		bottom.BorderSizePixel = 0
		bottom.Parent = gui

		onUnload(function() gui:Destroy() end)
		makeToggleRow({
			name = "Cinematic Bars", desc = "Black letterbox bars top and bottom",
			key = "cinebars", color = Color3.fromRGB(190, 190, 255), order = 4, parent = page,
			callback = function(on) gui.Enabled = on end,
		})
		makeSliderRow({
			name = "Bar Height %", key = "barHeight", min = 5, max = 25, default = 12,
			order = 5, parent = page,
			callback = function(v)
				top.Size = UDim2.new(1, 0, v / 100, 0)
				bottom.Size = UDim2.new(1, 0, v / 100, 0)
			end,
		})
	end

	-- FORCE SHIFT LOCK
	do
		local conn
		makeToggleRow({
			name = "Force Shift Lock", desc = "Locks the mouse to the center of the screen",
			key = "forceshiftlock", color = Color3.fromRGB(255, 200, 90), order = 6, parent = page,
			callback = function(on)
				disconnect(conn)
				conn = nil
				if on then
					conn = RunService.RenderStepped:Connect(function()
						UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
					end)
				else
					UserInputService.MouseBehavior = Enum.MouseBehavior.Default
				end
			end,
		})
	end

	----------------------------------------------------------------
	makeSection("POSITION", 10, page)

	do
		local off = { 0, 0, 0 }
		local function apply()
			local hum = getHumanoid()
			if hum then hum.CameraOffset = Vector3.new(off[1], off[2], off[3]) end
		end
		track(player.CharacterAdded:Connect(function() task.wait(0.5) apply() end))
		onUnload(function() off = { 0, 0, 0 } apply() end)
		makeSliderRow({ name = "Camera Offset X", key = "camX", min = -10, max = 10, default = 0, order = 11, parent = page,
			callback = function(v) off[1] = v apply() end })
		makeSliderRow({ name = "Camera Offset Y", key = "camY", min = -10, max = 10, default = 0, order = 12, parent = page,
			callback = function(v) off[2] = v apply() end })
		makeSliderRow({ name = "Camera Offset Z", key = "camZ", min = -10, max = 10, default = 0, order = 13, parent = page,
			callback = function(v) off[3] = v apply() end })
	end

	do
		local origMin = player.CameraMinZoomDistance
		makeSliderRow({
			name = "Min Zoom", key = "minZoom", min = 0, max = 50,
			default = math.clamp(math.floor(origMin + 0.5), 0, 50),
			order = 14, parent = page,
			callback = function(v) pcall(function() player.CameraMinZoomDistance = math.max(v, 0.5) end) end,
		})
		onUnload(function() pcall(function() player.CameraMinZoomDistance = origMin end) end)
	end

	makeButtonRow({
		text = "Force Third Person", order = 15, parent = page,
		callback = function()
			pcall(function() player.CameraMode = Enum.CameraMode.Classic end)
			notify("Third person")
		end,
	})
	makeButtonRow({
		text = "Reset Camera", order = 16, parent = page, color = Color3.fromRGB(120, 40, 50),
		callback = function()
			local cam = workspace.CurrentCamera
			local hum = getHumanoid()
			if cam then
				cam.CameraType = Enum.CameraType.Custom
				if hum then cam.CameraSubject = hum end
				cam.FieldOfView = 70
			end
			notify("Camera reset")
		end,
	})
end

----------------------------------------------------------------
-- AUDIO TAB
----------------------------------------------------------------
do
	local page = pages.Audio
	local SoundService = game:GetService("SoundService")

	local function eachSound(fn)
		for _, s in ipairs(workspace:GetDescendants()) do
			if s:IsA("Sound") then fn(s) end
		end
		for _, s in ipairs(SoundService:GetDescendants()) do
			if s:IsA("Sound") and s.Name ~= "GhostedSound" then fn(s) end
		end
	end

	makeSection("GAME AUDIO", 0, page)

	-- MUTE
	do
		local conn
		local saved = setmetatable({}, { __mode = "k" })
		local function sweep()
			eachSound(function(s)
				if saved[s] == nil then saved[s] = s.Volume end
				s.Volume = 0
			end)
		end
		makeToggleRow({
			name = "Mute Game Sounds", desc = "Sets every in-game sound to silent",
			key = "mutegame", color = Color3.fromRGB(255, 120, 150), order = 1, parent = page,
			callback = function(on)
				disconnect(conn)
				conn = nil
				if on then
					sweep()
					local acc = 0
					conn = RunService.Heartbeat:Connect(function(dt)
						acc = acc + dt
						if acc >= 3 then acc = 0 pcall(sweep) end
					end)
				else
					for s, v in pairs(saved) do
						if s.Parent then pcall(function() s.Volume = v end) end
						saved[s] = nil
					end
				end
			end,
		})
	end

	makeButtonRow({
		text = "Stop All Sounds", order = 2, parent = page,
		callback = function()
			local n = 0
			eachSound(function(s) pcall(function() s:Stop() end) n = n + 1 end)
			notify("Stopped " .. n .. " sounds")
		end,
	})

	----------------------------------------------------------------
	makeSection("PLAY AN AUDIO ID", 10, page)

	local snd
	local volume, pitch, looped = 50, 100, false
	local function getSnd()
		if not snd or not snd.Parent then
			snd = Instance.new("Sound")
			snd.Name = "GhostedSound"
			snd.Parent = SoundService
		end
		return snd
	end
	onUnload(function() if snd then snd:Destroy() end end)

	local idBox
	do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 38)
		row.BackgroundColor3 = kRowBg
		row.LayoutOrder = 11
		row.Parent = page
		addCorner(row, 8)
		idBox = Instance.new("TextBox")
		idBox.Size = UDim2.new(1, -24, 1, 0)
		idBox.Position = UDim2.new(0, 12, 0, 0)
		idBox.BackgroundTransparency = 1
		idBox.PlaceholderText = "audio asset id (numbers)..."
		idBox.PlaceholderColor3 = kTextDim
		idBox.Text = ""
		idBox.TextColor3 = Color3.fromRGB(230, 230, 235)
		idBox.Font = Enum.Font.Gotham
		idBox.TextSize = 14
		idBox.TextXAlignment = Enum.TextXAlignment.Left
		idBox.ClearTextOnFocus = false
		idBox.Parent = row
	end

	makeButtonRow({
		text = "Play", order = 12, parent = page,
		callback = function()
			local digits = string.match(idBox.Text, "%d+")
			if not digits then notify("Type an audio ID first") return end
			local s = getSnd()
			s:Stop()
			s.SoundId = "rbxassetid://" .. digits
			s.Looped = looped
			s.Volume = volume / 100
			s.PlaybackSpeed = pitch / 100
			s:Play()
			notify("Playing " .. digits)
			task.delay(3, function()
				if s.Parent and not s.IsPlaying and not s.IsLoaded then notify("That ID didn't load") end
			end)
		end,
	})
	makeButtonRow({
		text = "Stop", order = 13, parent = page,
		callback = function() if snd then snd:Stop() end end,
	})
	makeToggleRow({
		name = "Loop", desc = "Repeat the sound",
		key = "audioLoop", color = Color3.fromRGB(110, 170, 255), order = 14, parent = page,
		callback = function(on)
			looped = on
			if snd then snd.Looped = on end
		end,
	})
	makeSliderRow({
		name = "Volume %", key = "audioVol", min = 0, max = 100, default = 50,
		order = 15, parent = page,
		callback = function(v) volume = v if snd then snd.Volume = v / 100 end end,
	})
	makeSliderRow({
		name = "Pitch / Speed %", key = "audioPitch", min = 50, max = 200, default = 100,
		order = 16, parent = page,
		callback = function(v) pitch = v if snd then snd.PlaybackSpeed = v / 100 end end,
	})
end

----------------------------------------------------------------
-- SESSION TAB
----------------------------------------------------------------
do
	local page = pages.Session
	makeSection("THIS SESSION", 0, page)

	local function infoRow(order, title)
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 30)
		row.BackgroundColor3 = kRowBg
		row.LayoutOrder = order
		row.Parent = page
		addCorner(row, 8)
		local a = Instance.new("TextLabel")
		a.Size = UDim2.new(0, 120, 1, 0)
		a.Position = UDim2.new(0, 12, 0, 0)
		a.BackgroundTransparency = 1
		a.Text = title
		a.TextColor3 = kTextDim
		a.Font = Enum.Font.GothamBold
		a.TextSize = 12
		a.TextXAlignment = Enum.TextXAlignment.Left
		a.Parent = row
		local b = Instance.new("TextLabel")
		b.Size = UDim2.new(1, -140, 1, 0)
		b.Position = UDim2.new(0, 132, 0, 0)
		b.BackgroundTransparency = 1
		b.Text = "0"
		b.TextColor3 = Color3.fromRGB(230, 230, 235)
		b.Font = Enum.Font.Gotham
		b.TextSize = 12
		b.TextXAlignment = Enum.TextXAlignment.Left
		b.Parent = row
		return b
	end

	local timeLbl   = infoRow(1, "Time in Game")
	local distLbl   = infoRow(2, "Distance Walked")
	local jumpLbl   = infoRow(3, "Jumps")
	local deathLbl  = infoRow(4, "Deaths")
	local topLbl    = infoRow(5, "Top Speed")
	local metLbl    = infoRow(6, "Players Met")
	local peakLbl   = infoRow(7, "Peak Players")

	local start = os.clock()
	local dist, jumps, deaths, topSpeed, peak = 0, 0, 0, 0, 0
	local met, metCount = {}, 0
	local lastPos

	local function hookChar(char)
		local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 5)
		if hum then
			hum.Died:Connect(function() deaths = deaths + 1 end)
		end
	end
	if player.Character then task.spawn(hookChar, player.Character) end
	track(player.CharacterAdded:Connect(hookChar))
	track(UserInputService.JumpRequest:Connect(function() jumps = jumps + 1 end))

	local acc = 1
	track(RunService.Heartbeat:Connect(function(dt)
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if hrp then
			local p = hrp.Position
			if lastPos then
				local d = (p - lastPos).Magnitude
				if d < 50 then dist = dist + d end
			end
			lastPos = p
			local spd = hrp.AssemblyLinearVelocity.Magnitude
			if spd > topSpeed and spd < 1000 then topSpeed = spd end
		else
			lastPos = nil
		end

		acc = acc + dt
		if acc < 1 then return end
		acc = 0
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= player and not met[p.UserId] then
				met[p.UserId] = true
				metCount = metCount + 1
			end
		end
		peak = math.max(peak, #Players:GetPlayers())
		if not page.Visible then return end
		local t = math.floor(os.clock() - start)
		timeLbl.Text = string.format("%dh %dm %ds", math.floor(t / 3600), math.floor(t / 60) % 60, t % 60)
		distLbl.Text = string.format("%.0f studs", dist)
		jumpLbl.Text = tostring(jumps)
		deathLbl.Text = tostring(deaths)
		topLbl.Text = string.format("%.0f studs/s", topSpeed)
		metLbl.Text = tostring(metCount)
		peakLbl.Text = tostring(peak)
	end))

	makeButtonRow({
		text = "Copy Session Stats", order = 10, parent = page,
		callback = function()
			local t = math.floor(os.clock() - start)
			copyText(string.format(
				"Time: %dm %ds\nDistance: %.0f studs\nJumps: %d\nDeaths: %d\nTop speed: %.0f\nPlayers met: %d\nPeak players: %d",
				math.floor(t / 60), t % 60, dist, jumps, deaths, topSpeed, metCount, peak), "Stats")
		end,
	})
	makeButtonRow({
		text = "Reset Stats", order = 11, parent = page, color = Color3.fromRGB(120, 40, 50),
		callback = function()
			start = os.clock()
			dist, jumps, deaths, topSpeed, peak = 0, 0, 0, 0, 0
			met, metCount = {}, 0
			notify("Stats reset")
		end,
	})
end

----------------------------------------------------------------
-- AUTOMATION TAB
----------------------------------------------------------------
do
	local page = pages.Automation
	local VIM = game:GetService("VirtualInputManager")

	local function myHrp() return player.Character and player.Character:FindFirstChild("HumanoidRootPart") end

	makeSection("TIMED ACTIONS", 0, page)

	-- AUTO RESET
	do
		local conn
		local interval = 60
		makeToggleRow({
			name = "Auto Reset Character", desc = "Respawns you on a timer",
			key = "autoreset", color = Color3.fromRGB(255, 100, 110), order = 1, parent = page,
			callback = function(on)
				disconnect(conn)
				conn = nil
				if not on then return end
				local t = 0
				conn = RunService.Heartbeat:Connect(function(dt)
					t = t + dt
					if t >= interval then
						t = 0
						local hum = getHumanoid()
						if hum then hum.Health = 0 end
					end
				end)
			end,
		})
		makeSliderRow({
			name = "Reset Every (sec)", key = "autoResetSec", min = 10, max = 300, default = 60,
			order = 2, parent = page, callback = function(v) interval = v end,
		})
	end

	-- TIMED JUMP
	do
		local conn
		local interval = 5
		makeToggleRow({
			name = "Timed Jump", desc = "Jumps every few seconds",
			key = "timedjump", color = Color3.fromRGB(90, 230, 150), order = 3, parent = page,
			callback = function(on)
				disconnect(conn)
				conn = nil
				if not on then return end
				local t = 0
				conn = RunService.Heartbeat:Connect(function(dt)
					t = t + dt
					if t >= interval then
						t = 0
						local hum = getHumanoid()
						if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
					end
				end)
			end,
		})
		makeSliderRow({
			name = "Jump Every (sec)", key = "timedJumpSec", min = 1, max = 30, default = 5,
			order = 4, parent = page, callback = function(v) interval = v end,
		})
	end

	-- AUTO PRESS E
	do
		local conn
		local interval = 10
		makeToggleRow({
			name = "Auto Press E", desc = "Taps the E key on a timer",
			key = "autoE", color = Color3.fromRGB(255, 200, 90), order = 5, parent = page,
			callback = function(on)
				disconnect(conn)
				conn = nil
				if not on then return end
				local t = 0
				conn = RunService.Heartbeat:Connect(function(dt)
					t = t + dt
					if t >= interval / 10 then
						t = 0
						pcall(function()
							VIM:SendKeyEvent(true, Enum.KeyCode.E, false, game)
							task.delay(0.05, function() VIM:SendKeyEvent(false, Enum.KeyCode.E, false, game) end)
						end)
					end
				end)
			end,
		})
		makeSliderRow({
			name = "Press Interval (x0.1 sec)", key = "autoEInterval", min = 2, max = 100, default = 10,
			order = 6, parent = page, callback = function(v) interval = v end,
		})
	end

	----------------------------------------------------------------
	makeSection("MOVEMENT PATTERNS", 10, page)

	-- RANDOM WALK
	do
		local conn
		makeToggleRow({
			name = "Random Walk", desc = "Wanders around (good anti-AFK)",
			key = "randomwalk", color = Color3.fromRGB(130, 200, 255), order = 11, parent = page,
			callback = function(on)
				disconnect(conn)
				conn = nil
				if on then
					local t, walking = 0, false
					conn = RunService.Heartbeat:Connect(function(dt)
						t = t + dt
						if t < 2.5 then return end
						t = 0
						local hum = getHumanoid()
						if not hum then return end
						walking = not walking
						if walking then
							local a = math.random() * math.pi * 2
							hum:Move(Vector3.new(math.cos(a), 0, math.sin(a)), false)
						else
							hum:Move(Vector3.zero, false)
						end
					end)
				else
					local hum = getHumanoid()
					if hum then hum:Move(Vector3.zero, false) end
				end
			end,
		})
	end

	-- WALK IN CIRCLES
	do
		local conn
		makeToggleRow({
			name = "Walk in Circles", desc = "Keeps turning while walking",
			key = "circlewalk", color = Color3.fromRGB(180, 130, 255), order = 12, parent = page,
			callback = function(on)
				disconnect(conn)
				conn = nil
				if on then
					local a = 0
					conn = RunService.Heartbeat:Connect(function(dt)
						a = a + dt * 1.5
						local hum = getHumanoid()
						if hum then hum:Move(Vector3.new(math.cos(a), 0, math.sin(a)), false) end
					end)
				else
					local hum = getHumanoid()
					if hum then hum:Move(Vector3.zero, false) end
				end
			end,
		})
	end

	----------------------------------------------------------------
	makeSection("AUTO COLLECT", 20, page)

	-- AUTO COLLECT TOOLS
	do
		local conn
		makeToggleRow({
			name = "Auto Collect Tools", desc = "Touches loose tools within 40 studs",
			key = "autocollect", color = Color3.fromRGB(255, 220, 90), order = 21, parent = page,
			callback = function(on)
				disconnect(conn)
				conn = nil
				if not on then return end
				if typeof(firetouchinterest) ~= "function" then notify("Executor has no firetouchinterest") end
				local t = 0
				conn = RunService.Heartbeat:Connect(function(dt)
					t = t + dt
					if t < 1 then return end
					t = 0
					local hrp = myHrp()
					if not hrp or typeof(firetouchinterest) ~= "function" then return end
					for _, d in ipairs(workspace:GetDescendants()) do
						if d:IsA("Tool") then
							local h = d:FindFirstChild("Handle")
							local m = d:FindFirstAncestorOfClass("Model")
							if h and not (m and m:FindFirstChildOfClass("Humanoid"))
								and (h.Position - hrp.Position).Magnitude <= 40 then
								pcall(firetouchinterest, hrp, h, 0)
								pcall(firetouchinterest, hrp, h, 1)
							end
						end
					end
				end)
			end,
		})
	end

	-- AUTO FIRE PROMPTS
	do
		local conn
		local radius = 15
		makeToggleRow({
			name = "Auto Fire Prompts", desc = "Triggers nearby proximity prompts",
			key = "autoprompts", color = Color3.fromRGB(255, 150, 60), order = 22, parent = page,
			callback = function(on)
				disconnect(conn)
				conn = nil
				if not on then return end
				if typeof(fireproximityprompt) ~= "function" then notify("Executor has no fireproximityprompt") end
				local t = 0
				conn = RunService.Heartbeat:Connect(function(dt)
					t = t + dt
					if t < 0.5 then return end
					t = 0
					local hrp = myHrp()
					if not hrp or typeof(fireproximityprompt) ~= "function" then return end
					for _, d in ipairs(workspace:GetDescendants()) do
						if d:IsA("ProximityPrompt") then
							local part = d.Parent
							if part and part:IsA("BasePart") and (part.Position - hrp.Position).Magnitude <= radius then
								pcall(fireproximityprompt, d)
							end
						end
					end
				end)
			end,
		})
		makeSliderRow({
			name = "Prompt Radius", key = "promptRadius", min = 5, max = 40, default = 15,
			order = 23, parent = page, callback = function(v) radius = v end,
		})
	end
end

----------------------------------------------------------------
-- TELEPORTS TAB
----------------------------------------------------------------
do
	local page = pages.Teleports
	local placeKey = tostring(game.PlaceId)
	settings.places = settings.places or {}
	settings.places[placeKey] = settings.places[placeKey] or {}
	local list = settings.places[placeKey]
	local lastCF

	local function myHrp() return player.Character and player.Character:FindFirstChild("HumanoidRootPart") end
	local function remember()
		local h = myHrp()
		if h then lastCF = h.CFrame end
	end

	makeSection("SAVED LOCATIONS  (per game)", 0, page)

	local nameBox
	do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 38)
		row.BackgroundColor3 = kRowBg
		row.LayoutOrder = 1
		row.Parent = page
		addCorner(row, 8)
		nameBox = Instance.new("TextBox")
		nameBox.Size = UDim2.new(1, -24, 1, 0)
		nameBox.Position = UDim2.new(0, 12, 0, 0)
		nameBox.BackgroundTransparency = 1
		nameBox.PlaceholderText = "name for this spot..."
		nameBox.PlaceholderColor3 = kTextDim
		nameBox.Text = ""
		nameBox.TextColor3 = Color3.fromRGB(230, 230, 235)
		nameBox.Font = Enum.Font.Gotham
		nameBox.TextSize = 14
		nameBox.TextXAlignment = Enum.TextXAlignment.Left
		nameBox.ClearTextOnFocus = false
		nameBox.Parent = row
	end

	local rows = {}
	local rebuild
	rebuild = function()
		for _, r in ipairs(rows) do r:Destroy() end
		rows = {}
		for i, loc in ipairs(list) do
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, 0, 0, 38)
			row.BackgroundColor3 = kRowBg
			row.LayoutOrder = 10 + i
			row.Parent = page
			addCorner(row, 8)
			rows[#rows + 1] = row

			local lbl = Instance.new("TextLabel")
			lbl.Size = UDim2.new(1, -130, 1, 0)
			lbl.Position = UDim2.new(0, 12, 0, 0)
			lbl.BackgroundTransparency = 1
			lbl.Text = loc.name
			lbl.TextColor3 = Color3.fromRGB(230, 230, 235)
			lbl.Font = Enum.Font.Gotham
			lbl.TextSize = 13
			lbl.TextXAlignment = Enum.TextXAlignment.Left
			lbl.TextTruncate = Enum.TextTruncate.AtEnd
			lbl.Parent = row

			local function small(text, xOff, color, fn)
				local b = Instance.new("TextButton")
				b.AnchorPoint = Vector2.new(1, 0.5)
				b.Position = UDim2.new(1, xOff, 0.5, 0)
				b.Size = UDim2.new(0, 46, 0, 26)
				b.BackgroundColor3 = color
				b.Text = text
				b.TextColor3 = Color3.new(1, 1, 1)
				b.Font = Enum.Font.GothamBold
				b.TextSize = 11
				b.AutoButtonColor = false
				b.Parent = row
				addCorner(b, 6)
				track(b.MouseButton1Click:Connect(fn))
				return b
			end
			local go = small("Go", -58, accent, function()
				local h = myHrp()
				if not h then notify("No character") return end
				remember()
				h.CFrame = CFrame.new(loc.x, loc.y, loc.z)
				notify("Teleported to " .. loc.name)
			end)
			bindAccent(go, "BackgroundColor3")
			small("Del", -8, Color3.fromRGB(120, 40, 50), function()
				table.remove(list, i)
				saveSettings()
				rebuild()
			end)
		end
	end
	rebuild()

	makeButtonRow({
		text = "Save Current Position", order = 2, parent = page,
		callback = function()
			local h = myHrp()
			if not h then notify("No character") return end
			local name = nameBox.Text ~= "" and nameBox.Text or ("Spot " .. (#list + 1))
			local p = h.Position
			list[#list + 1] = { name = name, x = p.X, y = p.Y, z = p.Z }
			nameBox.Text = ""
			saveSettings()
			rebuild()
			notify("Saved " .. name)
		end,
	})

	----------------------------------------------------------------
	makeSection("QUICK TELEPORTS", 100, page)

	local playerBox
	do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 38)
		row.BackgroundColor3 = kRowBg
		row.LayoutOrder = 101
		row.Parent = page
		addCorner(row, 8)
		playerBox = Instance.new("TextBox")
		playerBox.Size = UDim2.new(1, -24, 1, 0)
		playerBox.Position = UDim2.new(0, 12, 0, 0)
		playerBox.BackgroundTransparency = 1
		playerBox.PlaceholderText = "player name (partial is fine)..."
		playerBox.PlaceholderColor3 = kTextDim
		playerBox.Text = ""
		playerBox.TextColor3 = Color3.fromRGB(230, 230, 235)
		playerBox.Font = Enum.Font.Gotham
		playerBox.TextSize = 14
		playerBox.TextXAlignment = Enum.TextXAlignment.Left
		playerBox.ClearTextOnFocus = false
		playerBox.Parent = row
	end
	makeButtonRow({
		text = "Teleport to That Player", order = 102, parent = page,
		callback = function()
			local q = string.lower(playerBox.Text)
			if q == "" then notify("Type a name first") return end
			local hrp = myHrp()
			if not hrp then notify("No character") return end
			for _, p in ipairs(Players:GetPlayers()) do
				if p ~= player and (string.sub(string.lower(p.Name), 1, #q) == q
					or string.sub(string.lower(p.DisplayName), 1, #q) == q) then
					local th = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
					if th then
						remember()
						hrp.CFrame = th.CFrame * CFrame.new(0, 0, 3)
						notify("Teleported to " .. p.DisplayName)
						return
					end
				end
			end
			notify("No matching player")
		end,
	})

	local radius = 100
	makeSliderRow({
		name = "Random Teleport Radius", key = "tpRadius", min = 10, max = 500, default = 100,
		order = 103, parent = page, callback = function(v) radius = v end,
	})
	makeButtonRow({
		text = "Random Teleport Nearby", order = 104, parent = page,
		callback = function()
			local hrp = myHrp()
			if not hrp then notify("No character") return end
			remember()
			local a = math.random() * math.pi * 2
			local d = math.random() * radius
			local target = hrp.Position + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d)
			local params = RaycastParams.new()
			params.FilterDescendantsInstances = { player.Character }
			params.FilterType = Enum.RaycastFilterType.Exclude
			local hit = workspace:Raycast(target + Vector3.new(0, 300, 0), Vector3.new(0, -1000, 0), params)
			if hit then
				hrp.CFrame = CFrame.new(hit.Position + Vector3.new(0, 3.5, 0))
			else
				hrp.CFrame = CFrame.new(target)
			end
		end,
	})
	makeButtonRow({
		text = "Return to Previous Spot", order = 105, parent = page,
		callback = function()
			local hrp = myHrp()
			if not hrp then notify("No character") return end
			if not lastCF then notify("Nothing to return to") return end
			local cur = hrp.CFrame
			hrp.CFrame = lastCF
			lastCF = cur
			notify("Swapped back")
		end,
	})
end

----------------------------------------------------------------
-- CREDITS TAB
----------------------------------------------------------------
do
	local page = pages.Credits
	makeSection("ABOUT", 0, page)

	local function card(order, title, body)
		local f = Instance.new("Frame")
		f.Size = UDim2.new(1, 0, 0, 0)
		f.AutomaticSize = Enum.AutomaticSize.Y
		f.BackgroundColor3 = kRowBg
		f.LayoutOrder = order
		f.Parent = page
		addCorner(f, 8)
		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, 10)
		pad.PaddingBottom = UDim.new(0, 10)
		pad.PaddingLeft = UDim.new(0, 12)
		pad.PaddingRight = UDim.new(0, 12)
		pad.Parent = f
		local l = Instance.new("UIListLayout")
		l.Padding = UDim.new(0, 4)
		l.SortOrder = Enum.SortOrder.LayoutOrder
		l.Parent = f

		local t = Instance.new("TextLabel")
		t.Size = UDim2.new(1, 0, 0, 20)
		t.BackgroundTransparency = 1
		t.Text = title
		t.TextColor3 = Color3.new(1, 1, 1)
		t.Font = Enum.Font.GothamBold
		t.TextSize = 15
		t.TextXAlignment = Enum.TextXAlignment.Left
		t.LayoutOrder = 1
		t.Parent = f
		bindAccent(t, "TextColor3")

		local b = Instance.new("TextLabel")
		b.Size = UDim2.new(1, 0, 0, 0)
		b.AutomaticSize = Enum.AutomaticSize.Y
		b.BackgroundTransparency = 1
		b.Text = body
		b.TextColor3 = Color3.fromRGB(200, 200, 215)
		b.Font = Enum.Font.Gotham
		b.TextSize = 12
		b.TextWrapped = true
		b.TextXAlignment = Enum.TextXAlignment.Left
		b.TextYAlignment = Enum.TextYAlignment.Top
		b.LayoutOrder = 2
		b.Parent = f
	end

	card(1, "Ghosted Menu", "A universal menu for PC and mobile. Open it with the floating ghost or your menu key (RightShift by default).")
	card(2, "Made by", "Dani & Elixir & Hade")
	card(3, "Tips", "Right-click any toggle on PC to give it a key. Press End to switch everything off at once. Your settings, presets, notes and saved locations are stored in " .. kSaveFile .. ".")

	makeButtonRow({
		text = "Copy Discord Link", order = 10, parent = page,
		callback = function() copyText(kDiscordLink, "Discord link") end,
	})
	makeButtonRow({
		text = "Count Features", order = 11, parent = page,
		callback = function()
			local n = 0
			for _ in pairs(featureToggles) do n = n + 1 end
			local s = 0
			for _ in pairs(sliderResets) do s = s + 1 end
			notify(n .. " toggles, " .. s .. " sliders, " .. #tabNames .. " tabs")
		end,
	})
end

----------------------------------------------------------------
-- UPDATES TAB
----------------------------------------------------------------
do
	local updatesPage = pages.Updates
	local kVersion = "1.7"

	local header = makeSection("CURRENT VERSION  v" .. kVersion, 0, updatesPage)

	local updates = {
		{
			version = "v1.7", title = "Every tab filled in", latest = true,
			items = {
				"New Camera tab: Orbit Camera, Cinematic Bars, Force Shift Lock, camera offsets, Min Zoom, Reset Camera",
				"New Audio tab: Mute Game Sounds, Stop All Sounds, play any audio ID with volume, pitch and loop",
				"New Session tab: time, distance, jumps, deaths, top speed and players met",
				"New Automation tab: Auto Reset, Timed Jump, Auto Press E, Random Walk, Walk in Circles, Auto Collect, Auto Fire Prompts",
				"New Teleports tab: named saved locations per game, teleport to player by name, random teleport, return",
				"New Credits tab",
				"More in older tabs: Auto Jump and speed presets (Move), Personal Light, Night Vision, Tool ESP, Highlight Self (Visuals), Friend Alert and Highlight Friends (Players), Hide Roblox UI, Auto Rejoin, Unlock Mouse (Misc)",
				"More in older tabs: Rocket Boost (Extra), Face Cursor and Ragdoll Self (Fun), Bloom, Sun Rays, Water Transparency (World), Mention Alert (Chat), Radar and Death Notifier (Combat)",
				"Themes: title font, corner roundness, border thickness, ghost size. Config: notification sound, Save Now",
			},
		},
		{
			version = "v1.6", title = "Six new tabs",
			items = {
				"New Combat tab: Hitbox Expander, Auto Attack, Low Health Alert, Target Info",
				"New Server tab: live server info, Copy Join Script, Hop to Smallest / Fullest Server",
				"New Presets tab: PvP, Explorer, Speedrun, ESP Only and AFK profiles plus 3 save slots of your own",
				"New Keybinds tab: list and clear your binds, plus an on-screen Keybind Overlay",
				"New Themes tab: custom RGB accent, Rainbow Accent, Random Accent, custom menu title",
				"New Notes tab: a scratchpad that saves with your settings",
				"Tools: three Quick Slots to save and return to spots (Alt+1/2/3)",
				"Fly can now be keybound and saved",
			},
		},
		{
			version = "v1.5", title = "Chat, Tools and lots more",
			items = {
				"New Chat tab: send messages, emotes, Chat Logger with copy/clear, Join / Leave Alerts",
				"New Tools tab: Info HUD, Spectate Next/Previous, teleport to nearest/random player, Follow Nearest Player",
				"Tools: Equip/Unequip All Tools, Teleport Tool, Instant Prompts, Trigger Nearby Prompts / Clicks",
				"Extra tab: Glide, Fall Clamp, Wall Climb, TP Walk, Auto Walk and gravity presets",
				"Visuals: Skeleton ESP and Head Dots",
				"World: Saturation, Contrast, Brightness and Blur sliders plus Noir / Vibrant / Warm / Cold looks",
				"Config: Panic key (End), Reset Menu Position, Copy Settings, Delete Saved Settings",
			},
		},
		{
			version = "v1.4", title = "New tabs and features",
			items = {
				"New Fun tab: Rainbow Character, See-Through Mode, Sit, Trail, First Person Lock, Character Scale",
				"Fun movement: Sprint (hold Shift) and Dash (press Q) with sliders",
				"New World tab: No Fog, X-Ray, Remove Particles, Time Cycle, World Tint",
				"Camera tools: Hold Z to Zoom and Freecam (PC)",
				"Tools: Click Delete (Alt+click) with Undo, Copy Position, Copy Game Link, Teleport to Spawn",
				"New Updates tab with this changelog",
			},
		},
		{
			version = "v1.3", title = "Fling and credits",
			items = {
				"Fling rewritten: it now uses your own character to collide with the target, so it actually affects them",
				"Credits now read: made by Dani & Elixir & Hade",
			},
		},
		{
			version = "v1.2", title = "Extra tab and scrolling",
			items = {
				"New Extra tab: Bunny Hop, Air Walk, Spin, No Ragdoll, Anti-Fling, Respawn Here",
				"Extra utilities: Auto Clicker, Camera Noclip, FPS Boost and Waypoints",
				"Tab bar scrolls sideways and keeps the selected tab in view",
				"Page scrolling made more reliable",
			},
		},
		{
			version = "v1.1", title = "Fixes and polish",
			items = {
				"Fixed the white flash when opening the menu",
				"Fixed the Menu Opacity slider",
				"Fly now uses LinearVelocity with a legacy fallback",
				"Anti-Void, Speed Boost and Camera Aim Mode fixes",
				"Added God Mode, Teleport to Coords, team colors, ping colors and server uptime",
			},
		},
		{
			version = "v1.0", title = "First release",
			items = {
				"Move, Visuals, Players, Misc and Config tabs",
				"Fly, Noclip, Speed, ESP, Chams, Aimbot, Triggerbot and more",
				"Accent themes, keybinds and saved settings",
			},
		},
	}

	for idx, u in ipairs(updates) do
		local card = Instance.new("Frame")
		card.Size = UDim2.new(1, 0, 0, 0)
		card.AutomaticSize = Enum.AutomaticSize.Y
		card.BackgroundColor3 = kRowBg
		card.LayoutOrder = idx
		card.Parent = updatesPage
		addCorner(card, 8)

		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, 10)
		pad.PaddingBottom = UDim.new(0, 10)
		pad.PaddingLeft = UDim.new(0, 12)
		pad.PaddingRight = UDim.new(0, 12)
		pad.Parent = card

		local list = Instance.new("UIListLayout")
		list.Padding = UDim.new(0, 4)
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Parent = card

		local title = Instance.new("TextLabel")
		title.Size = UDim2.new(1, 0, 0, 20)
		title.BackgroundTransparency = 1
		title.Text = u.version .. "  -  " .. u.title .. (u.latest and "   [LATEST]" or "")
		title.TextColor3 = Color3.new(1, 1, 1)
		title.Font = Enum.Font.GothamBold
		title.TextSize = 14
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.LayoutOrder = 0
		title.Parent = card
		if u.latest then bindAccent(title, "TextColor3") end

		for i, text in ipairs(u.items) do
			local line = Instance.new("TextLabel")
			line.Size = UDim2.new(1, 0, 0, 0)
			line.AutomaticSize = Enum.AutomaticSize.Y
			line.BackgroundTransparency = 1
			line.Text = "•  " .. text
			line.TextColor3 = Color3.fromRGB(190, 190, 205)
			line.Font = Enum.Font.Gotham
			line.TextSize = 12
			line.TextWrapped = true
			line.TextXAlignment = Enum.TextXAlignment.Left
			line.TextYAlignment = Enum.TextYAlignment.Top
			line.LayoutOrder = i
			line.Parent = card
		end
	end
end

----------------------------------------------------------------
-- CONFIG TAB
----------------------------------------------------------------
makeSection("APPEARANCE", 0, configPage)

do
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 44)
	row.BackgroundColor3 = kRowBg
	row.LayoutOrder = 1
	row.Parent = configPage
	addCorner(row, 8)

	local lbl = Instance.new("TextLabel")
	lbl.Position = UDim2.new(0, 12, 0, 0)
	lbl.Size = UDim2.new(0, 70, 1, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text = "Accent"
	lbl.TextColor3 = Color3.fromRGB(230, 230, 235)
	lbl.Font = Enum.Font.Gotham
	lbl.TextSize = 15
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Parent = row

	local swatchStrokes = {}
	for i, t in ipairs(themes) do
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(0, 22, 0, 22)
		b.AnchorPoint = Vector2.new(1, 0.5)
		b.Position = UDim2.new(1, -10 - (#themes - i) * 28, 0.5, 0)
		b.BackgroundColor3 = t.color
		b.Text = ""
		b.AutoButtonColor = false
		b.Parent = row
		addCorner(b, -1)
		-- white ring = active
		local sw = addStroke(b, Color3.new(1,1,1), 2, (settings.accent == i) and 0 or 1)
		swatchStrokes[i] = sw
		track(b.MouseButton1Click:Connect(function()
			setAccent(i)
			for j, s in ipairs(swatchStrokes) do
				s.Transparency = (j == i) and 0 or 1
			end
			notify("Accent: " .. t.name)
		end))
	end
end

makeSliderRow({
	name = "Menu Scale", key = "menuScale", min = 60, max = 130, default = 100,
	order = 2, parent = configPage,
	callback = function(v)
		menuScale.Scale = v / 100
		if isOpen then mainFrame.Size = getMenuSize() end
	end,
})
makeSliderRow({
	name = "Menu Opacity", key = "menuOpacity", min = 40, max = 100, default = 100,
	order = 3, parent = configPage,
	callback = function(v)
		-- FIX: UIGradient overrides BackgroundColor3 but not transparency on the frame itself;
		-- we set both the frame background transparency AND tween the gradient colors' alpha
		local t = 1 - v / 100
		mainFrame.BackgroundTransparency = t
		-- darken via BackgroundColor tint so the frame bg bleeds through at low opacity
		local base = (1 - t) * 0.9
		mainFrame.BackgroundColor3 = Color3.fromRGB(
			math.floor(22 * base), math.floor(22 * base), math.floor(30 * base)
		)
	end,
})

makeSection("STARTUP", 4, configPage)
makeToggleRow({ name = "Startup Splash",  desc = "Ghost intro animation when the menu loads", opt = "splash",      color = Color3.fromRGB(190,190,255), order = 5, parent = configPage, callback = function() end })
makeToggleRow({ name = "Open On Load",    desc = "Show the menu right after loading",          opt = "openOnLoad",  color = Color3.fromRGB(190,190,255), order = 6, parent = configPage, callback = function() end })
makeToggleRow({ name = "Notifications",   desc = "Toast messages at the bottom",               opt = "notifs",      color = Color3.fromRGB(190,190,255), order = 7, parent = configPage, callback = function() end })
makeToggleRow({ name = "Floating Ghost",  desc = "Hide it and use the menu key instead",       opt = "showButton",  color = Color3.fromRGB(190,190,255), order = 8, parent = configPage,
	callback = function(on) toggleBtn.Visible = on end })

makeSection("CONTROLS", 9, configPage)

local rebindBtn
rebindBtn = makeButtonRow({
	text = "Menu key: " .. toggleKey.Name .. "  (tap to rebind)", order = 10, parent = configPage,
	callback = function(btn)
		local prev = bindingFeature
		bindingFeature = nil
		if prev then refreshBindTag(prev) end
		rebinding = true
		btn.Text = "Press a key...  (Esc cancels)"
	end,
})

do
	local tip = Instance.new("TextLabel")
	tip.Size = UDim2.new(1, 0, 0, 30)
	tip.BackgroundTransparency = 1
	tip.Text = "PC: right-click any toggle to bind a key to it. Esc clears the bind."
	tip.TextColor3 = kTextDim
	tip.Font = Enum.Font.Gotham
	tip.TextSize = 11
	tip.TextWrapped = true
	tip.LayoutOrder = 11
	tip.Parent = configPage
end

track(UserInputService.InputBegan:Connect(function(input, processed)
	if rebinding then
		if input.UserInputType == Enum.UserInputType.Keyboard then
			rebinding = false
			if input.KeyCode ~= Enum.KeyCode.Escape then
				toggleKey = input.KeyCode
				settings.menuKey = input.KeyCode.Name
				saveSettings()
				notify("Menu key: " .. toggleKey.Name)
			end
			rebindBtn.Text = "Menu key: " .. toggleKey.Name .. "  (tap to rebind)"
		end
		return
	end
	if bindingFeature then
		if input.UserInputType == Enum.UserInputType.Keyboard then
			local key = bindingFeature
			bindingFeature = nil
			if input.KeyCode == Enum.KeyCode.Escape then
				settings.binds[key] = nil
				notify("Bind cleared")
			else
				settings.binds[key] = input.KeyCode.Name
				notify("Bound to " .. input.KeyCode.Name)
			end
			saveSettings()
			refreshBindTag(key)
		end
		return
	end
	if processed then return end
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
	if input.KeyCode == toggleKey then toggleMenu(); return end
	local name = input.KeyCode.Name
	for key, bound in pairs(settings.binds) do
		if bound == name then
			local e = featureToggles[key]
			if e then e.set(not e.get()) end
		end
	end
end))

makeSection("DATA", 12, configPage)

makeButtonRow({
	text = "Reset All", order = 13, parent = configPage,
	callback = function()
		for _, s in ipairs(toggleSetters) do pcall(s, false, true) end
		for _, r in ipairs(sliderResets)  do pcall(r) end
		settings.toggles = {}
		settings.sliders = {}
		settings.binds   = {}
		for key in pairs(featureToggles) do refreshBindTag(key) end
		saveSettings()
		notify("Everything reset")
	end,
})

local function unload()
	alive = false
	for _, s in ipairs(toggleSetters) do pcall(s, false, true) end
	for _, fn in ipairs(cleanups)     do pcall(fn) end
	pcall(function() workspace.Gravity = origGravity end)
	pcall(function()
		if workspace.CurrentCamera then workspace.CurrentCamera.FieldOfView = origFov end
	end)
	for _, c in ipairs(conns) do disconnect(c) end
	pcall(function() chamsFolder:Destroy() end)
	pcall(function() screenGui:Destroy() end)
	if env.GhostedMenuUnload == unload then env.GhostedMenuUnload = nil end
end
env.GhostedMenuUnload = unload

makeButtonRow({
	text = "Unload Menu", color = Color3.fromRGB(120, 40, 50), order = 14, parent = configPage,
	callback = unload,
})

do
	local credit = Instance.new("TextLabel")
	credit.Size = UDim2.new(1, 0, 0, 20)
	credit.BackgroundTransparency = 1
	credit.Text = "Ghosted Menu - made by Dani & Elixir & Hade"
	credit.TextColor3 = kTextDim
	credit.Font = Enum.Font.Gotham
	credit.TextSize = 12
	credit.LayoutOrder = 15
	credit.Parent = configPage
end

----------------------------------------------------------------
-- STARTUP SPLASH
----------------------------------------------------------------
local function finishLoad()
	notify("Loaded - press " .. toggleKey.Name .. " or tap the ghost")
	if opts.openOnLoad then openMenu() end
end

local function runSplash()
	local cam = workspace.CurrentCamera
	local vp  = cam and cam.ViewportSize or Vector2.new(1280, 720)
	local px  = math.clamp(math.floor(math.min(vp.X, vp.Y) / 150), 2, 4)
	local gw, gh = kGhostW * px, kGhostH * px
	local skipped = false

	local overlay = Instance.new("TextButton")
	overlay.Name = "Splash"
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3 = Color3.fromRGB(8, 8, 12)
	overlay.BackgroundTransparency = 1
	overlay.BorderSizePixel = 0
	overlay.Text = ""
	overlay.AutoButtonColor = false
	overlay.ZIndex = 200
	overlay.Parent = screenGui
	track(overlay.MouseButton1Click:Connect(function() skipped = true end))

	local okCanvas, holder = pcall(Instance.new, "CanvasGroup")
	if not okCanvas or typeof(holder) ~= "Instance" then holder = Instance.new("Frame") end
	local isCanvas = holder:IsA("CanvasGroup")

	local blockH = gh + 92
	local top    = -math.floor(blockH / 2)
	local ghostY = top + math.floor(gh / 2)
	local titleY = top + gh + 14

	holder.Name = "GhostHolder"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.Size = UDim2.fromOffset(gw, gh)
	holder.Position = UDim2.new(0.5, 0, 0.5, ghostY + 26)
	holder.Parent = overlay
	if isCanvas then holder.GroupTransparency = 1 end

	local holderScale = Instance.new("UIScale")
	holderScale.Parent = holder

	local ghost = createGhost(holder, px)

	local title = Instance.new("TextLabel")
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.Position = UDim2.new(0.5, 0, 0.5, titleY)
	title.Size = UDim2.fromOffset(360, 32)
	title.BackgroundTransparency = 1
	title.Text = ""
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 28
	title.ZIndex = 201
	title.Parent = overlay

	local sub = Instance.new("TextLabel")
	sub.AnchorPoint = Vector2.new(0.5, 0)
	sub.Position = UDim2.new(0.5, 0, 0.5, titleY + 32)
	sub.Size = UDim2.fromOffset(360, 18)
	sub.BackgroundTransparency = 1
	sub.Text = "made by Dani & Elixir & Hade"
	sub.TextColor3 = kTextDim
	sub.TextTransparency = 1
	sub.Font = Enum.Font.Gotham
	sub.TextSize = 13
	sub.ZIndex = 201
	sub.Parent = overlay

	local barBack = Instance.new("Frame")
	barBack.AnchorPoint = Vector2.new(0.5, 0)
	barBack.Position = UDim2.new(0.5, 0, 0.5, titleY + 62)
	barBack.Size = UDim2.fromOffset(180, 4)
	barBack.BackgroundColor3 = Color3.fromRGB(40, 40, 54)
	barBack.BorderSizePixel = 0
	barBack.ZIndex = 201
	barBack.Parent = overlay
	addCorner(barBack, -1)

	local barFill = Instance.new("Frame")
	barFill.Size = UDim2.new(0, 0, 1, 0)
	barFill.BackgroundColor3 = accent
	barFill.BorderSizePixel = 0
	barFill.ZIndex = 202
	barFill.Parent = barBack
	addCorner(barFill, -1)

	local function pause(t)
		local t0 = os.clock()
		while os.clock() - t0 < t and not skipped and alive do task.wait() end
	end

	local running = true
	task.spawn(function()
		local i = 1
		while running and alive and holder.Parent do
			ghost:setFrame(i)
			i = i % #ghostFrames + 1
			task.wait(0.05)
		end
	end)

	TweenService:Create(overlay, TweenInfo.new(0.25), { BackgroundTransparency = 0.08 }):Play()
	if isCanvas then TweenService:Create(holder, TweenInfo.new(0.5), { GroupTransparency = 0 }):Play() end
	TweenService:Create(holder, TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0.5, ghostY),
	}):Play()
	pause(0.5)

	local text = "ghosted menu"
	for n = 1, #text do
		if skipped or not alive then break end
		title.Text = string.sub(text, 1, n)
		task.wait(0.045)
	end
	title.Text = text
	TweenService:Create(sub, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()

	for _, frac in ipairs({ 0.35, 0.7, 1 }) do
		if skipped or not alive then break end
		TweenService:Create(barFill, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { Size = UDim2.new(frac, 0, 1, 0) }):Play()
		pause(0.3)
	end
	pause(0.25)

	running = false
	local outInfo = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	if alive and toggleBtn.Visible then
		local target = toggleBtn.AbsolutePosition + toggleBtn.AbsoluteSize / 2 - overlay.AbsolutePosition
		TweenService:Create(holder, outInfo, { Position = UDim2.fromOffset(target.X, target.Y) }):Play()
		TweenService:Create(holderScale, outInfo, { Scale = 0.3 }):Play()
	end
	if isCanvas then TweenService:Create(holder, TweenInfo.new(0.45), { GroupTransparency = 1 }):Play() end
	TweenService:Create(title,   TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
	TweenService:Create(sub,     TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
	TweenService:Create(barBack, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
	TweenService:Create(barFill, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
	TweenService:Create(overlay, TweenInfo.new(0.45), { BackgroundTransparency = 1 }):Play()
	task.wait(0.5)
	overlay:Destroy()
	if alive then finishLoad() end
end

----------------------------------------------------------------
-- READY
----------------------------------------------------------------
if opts.splash then
	task.spawn(function()
		local ok, err = pcall(runSplash)
		if not ok then
			warn("[Ghosted Menu] splash failed: " .. tostring(err))
			local o = screenGui:FindFirstChild("Splash")
			if o then o:Destroy() end
			if alive then finishLoad() end
		end
	end)
else
	finishLoad()
end

