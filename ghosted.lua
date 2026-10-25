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
local settings = { toggles = {}, sliders = {}, binds = {}, opts = {}, accent = 1, menuKey = "RightShift" }
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
	end
end

local opts = settings.opts
do
	local defaults = { splash = true, openOnLoad = true, notifs = true, showButton = true }
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

local tabNames = { "Move", "Visuals", "Players", "Misc", "Extra", "Fun", "World", "Updates", "Config" }
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
		featureToggles[o.key] = { tag = bindTag, set = setState, get = function() return state end }
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
		color = Color3.fromRGB(110, 170, 255), order = 1, parent = movePage, callback = setFly,
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
-- UPDATES TAB
----------------------------------------------------------------
do
	local updatesPage = pages.Updates
	local kVersion = "1.4"

	local header = makeSection("CURRENT VERSION  v" .. kVersion, 0, updatesPage)

	local updates = {
		{
			version = "v1.4", title = "New tabs and features", latest = true,
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
