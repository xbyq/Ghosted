--[[
	Ghosted Menu - universal executor script (PC + mobile)


	Tabs:   Move / Visuals / Players / Misc / Config
	Open:   RightShift (rebindable in Config) or tap the floating ghost
	Binds:  right-click any toggle (PC), press a key to bind it, Esc clears it
	Saves:  toggles, sliders, binds, options, accent color and menu key -> GhostedMenu_settings.json
			(needs writefile/readfile/isfile; works fine without them, just doesn't persist)
	Reload: re-running the script cleanly unloads the previous copy first
]]

if not game:IsLoaded() then game.Loaded:Wait() end

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local Stats = game:GetService("Stats")
local TeleportService = game:GetService("TeleportService")

if not Players.LocalPlayer then Players:GetPropertyChangedSignal("LocalPlayer"):Wait() end
local player = Players.LocalPlayer

-- unload any previous copy before building a new one
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
-- CONNECTION TRACKING (so Unload can clean up everything)
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
-- SETTINGS (persisted to disk when the executor allows it)
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
		if type(data.accent) == "number" then settings.accent = data.accent end
		if type(data.menuKey) == "string" then settings.menuKey = data.menuKey end
		if type(data.binds) == "table" then settings.binds = data.binds end
		if type(data.opts) == "table" then settings.opts = data.opts end
	end
end

-- menu options (default-on settings live here, separate from feature toggles)
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
		pcall(function()
			writefile(kSaveFile, HttpService:JSONEncode(settings))
		end)
	end)
end

local toggleKey = kDefaultToggleKey
do
	local ok, key = pcall(function() return Enum.KeyCode[settings.menuKey] end)
	if ok and key then toggleKey = key end
end

----------------------------------------------------------------
-- ACCENT THEME (live-recolors every bound element)
----------------------------------------------------------------
local accent = (themes[settings.accent] or themes[1]).color
local accentTargets = {}
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
	for _, e in ipairs(accentTargets) do
		pcall(function() e[1][e[2]] = accent end)
	end
	for _, cb in ipairs(accentCallbacks) do
		pcall(cb, accent)
	end
	saveSettings()
end

----------------------------------------------------------------
-- SMALL UI HELPERS
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

-- generic drag helper: drag `handle` to move `target`; a short press without movement calls onTap
local function makeDraggable(handle, target, onTap)
	local dragging = false
	local moved = false
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
-- GHOST ICON (pixel art drawn with frames, so no image api is needed)
----------------------------------------------------------------
local kGhostData = "e51,e51,e51,e51,e51,e51,e27k12e12,e24k4w10k3e10,e23k2w16k2e8,e21k2w19k3e6,e19k2w23k2e5,e18k2w25k3e3,e17k2w28k1e3,e16k2w29k2e2,e15k2w31k1e2,e15k1w32k2e1,e15k1w33k1e1,e14k2w9k5w3k1w3k1w2k5w4k1e1,e14k1w10k5w3k5w2k5w4k1e1,e14k1w18k1w3k1w11k1e1,e13k2w34k1e1,e13k1w35k1e1,e13k1w35k1e1,e12k2w35k1e1,e12k1w36k1e1,e12k1w36k1e1,e11k2w36k1e1,e11k1w37k1e1,e11k1w37k1e1,e10k2w36k2e1,e10k1w37k1e2,e9k2w37k1e2,e9k1w38k1e2,e8k1w38k2e2,e8k1w38k1e3,e7k1w39k1e3,e6k2w39k1e3,e6k1w39k1e4,e6k1w39k1e4,e5k1w40k1e4,e4k2w8k3w29k1e4,e4k1w8k2g1k1w28k1e5,e3k2w6k3g2k1w27k2e5,e3k1w5k3g4k1w27k1e6,e3k1w3k4g5k1w26k2e6,e3k4e3k2g3k1w27k1e7,e11k1g3k1w13k5w9k1e7,e11k1g3k1w12k2g2k2w8k2e7,e12k4w11k2g2k3w8k1e8,e15k1w10k1g3k2e2k1w6k2e8,e15k1w8k2g3k2e3k1w6k1e9,e15k2w4k4g3k2e4k1w5k2e9,e16k6e2k2g1k2e5k1w4k2e10,e25k2e7k2w2k2e11,e35k4e12,e51,e51,e51/e51,e51,e51,e51,e51,e27k11e13,e24k3w10k4e10,e22k3w15k3e8,e20k3w19k3e6,e19k2w23k2e5,e18k2w25k2e4,e17k2w27k2e3,e16k2w29k1e3,e15k2w30k2e2,e15k1w32k2e1,e15k1w33k1e1,e14k2w9k5w3k1w3k1w2k5w4k1e1,e14k1w10k5w3k5w2k5w4k1e1,e14k1w18k1w3k1w11k1e1,e14k1w34k1e1,e14k1w34k1e1,e14k1w34k1e1,e13k2w34k1e1,e13k1w35k1e1,e13k1w35k1e1,e12k2w35k1e1,e12k1w36k1e1,e11k2w36k1e1,e11k1w37k1e1,e10k2w36k1e2,e10k1w37k1e2,e9k1w38k1e2,e8k2w38k1e2,e7k2w38k1e3,e6k2w39k1e3,e6k1w40k1e3,e5k1w40k2e3,e4k2w40k1e4,e3k2w5k2w34k1e4,e2k2w3k3e1k2w33k1e4,e2k1w2k3e4k2w31k2e4,e1k1w2k2e5k1g1k1w31k1e5,e1k1w1k2e6k1g1k1w30k2e5,e2k2e7k1g1k1w30k1e6,e11k1g1k1w12k5w12k2e6,e11k1g1k1w10k3g3k2w11k1e7,e11k3w9k2g6k2w10k1e7,e11k2w10k2g7k1w9k1e8,e12k1w9k1e1k1g6k2w8k2e8,e12k2w7k2e1k2g5k2w8k1e9,e13k2w4k3e3k1g4k1e1k1w7k2e9,e14k6e6k2g1k2e1k2w5k3e9,e27k3e3k1w4k2e11,e33k6e12,e51,e51,e51,e51/e51,e51,e51,e51,e27k11e13,e24k4w9k4e10,e22k3w15k3e8,e21k2w19k3e6,e20k2w22k2e5,e18k2w25k2e4,e17k2w27k2e3,e16k2w29k2e2,e16k1w31k1e2,e15k2w31k2e1,e15k1w33k1e1,e15k1w9k5w3k1w3k1w2k5w4k1e1,e15k1w9k5w3k5w2k5w4k1e1,e14k2w17k1w3k1w11k1e1,e14k1w34k1e1,e14k1w34k1e1,e14k1w34k1e1,e13k2w34k1e1,e13k1w35k1e1,e13k1w35k1e1,e12k1w36k1e1,e12k1w36k1e1,e11k1w37k1e1,e11k1w37k1e1,e10k1w37k1e2,e9k2w37k1e2,e9k1w38k1e2,e8k2w38k1e2,e8k1w38k1e3,e7k1w39k1e3,e6k2w38k1e4,e6k1w39k1e4,e5k2w39k1e4,e4k2g1k4w34k1e5,e4k3g3k2w33k1e5,e3k3g2k2e1k1w33k1e5,e3k2g2k2e2k1w32k1e6,e2k2g2k2e3k1w32k1e6,e2k1g1k3e4k1w31k2e6,e2k3e6k1w13k6w12k1e7,e11k1w11k2e1k1g2k2w12k1e7,e10k1w11k2e2k1g3k1w11k2e7,e10k1w10k2e3k1g3k1w10k1e9,e10k1w9k2e4k1g3k1w9k2e9,e10k2w7k2e5k1g3k2w8k1e10,e11k2w4k2e7k1g3k2w7k2e10,e12k6e8k1g2k3w6k2e11,e27k3e1k2w3k3e12,e32k5e14,e51,e51,e51,e51,e51/e51,e51,e32k4e15,e26k6w3k5e11,e23k4w12k3e9,e21k3w17k2e8,e20k2w21k2e6,e18k2w24k2e5,e17k2w26k2e4,e17k1w28k2e3,e16k1w30k1e3,e15k2w30k2e2,e15k1w32k2e1,e15k1w33k1e1,e15k1w9k5w3k1w3k1w2k5w4k1e1,e15k1w9k5w3k5w2k5w4k1e1,e14k1w18k1w3k1w11k2,e14k1w35k1,e14k1w35k1,e13k2w35k1,e13k1w36k1,e13k1w36k1,e12k1w37k1,e12k1w36k2,e12k1w36k1e1,e11k1w37k1e1,e11k1w37k1e1,e10k1w38k1e1,e9k2w37k2e1,e9k1w38k1e2,e8k1w38k2e2,e7k2w38k1e3,e7k1w39k1e3,e6k2w38k2e3,e6k1w39k1e4,e5k2w39k1e4,e4k6w35k1e5,e4k1g4k1w35k1e5,e3k1g5k1w35k1e5,e3k1g4k2w34k1e6,e2k1g4k3w34k1e6,e2k1g2k3e1k1w15k3w16k1e6,e2k4e3k1w14k2e1k2w14k1e7,e9k1w13k2e3k1w14k1e7,e9k1w12k2e4k1w13k2e7,e9k1w10k3e5k1w12k1e9,e10k1w8k3e6k1w12k1e9,e10k2w4k3g1k2e6k1w10k2e10,e11k9e8k1w10k1e11,e28k2w8k1e12,e28k3w5k2e13,e30k7e14,e51,e51,e51,e51,e51,e51/e51,e51,e51,e27k13e11,e23k5w11k2e10,e22k2w17k2e8,e20k3w19k3e6,e19k2w23k2e5,e18k2w25k2e4,e17k2w27k2e3,e16k2w29k1e3,e16k1w31k1e2,e15k1w32k2e1,e15k1w9k5w3k1w3k1w2k5w4k1e1,e14k2w9k5w3k5w2k5w4k1e1,e14k1w18k1w3k1w11k2,e14k1w35k1,e14k1w35k1,e14k1w35k1,e13k1w36k1,e13k1w36k1,e13k1w36k1,e12k2w36k1,e12k1w37k1,e11k2w36k1e1,e11k1w37k1e1,e10k1w38k1e1,e10k1w37k2e1,e9k1w38k1e2,e8k2w37k2e2,e8k1w38k1e3,e7k1w38k1e4,e6k2w38k1e4,e6k1w39k1e4,e5k3w38k1e4,e5k1g1k1w37k1e5,e4k1g3k1w36k1e5,e3k2g4k1w35k1e5,e3k1g4k2w34k1e6,e3k1g3k2w35k1e6,e2k2g2k3w34k2e6,e2k6w16k4w15k1e7,e3k2e2k1w14k3e2k1w15k1e7,e7k1w12k3g1k1e2k1w15k1e7,e7k1w11k2g2k2e2k1w12k1w1k2e7,e7k2w8k2g4k1e3k1w11k1g1k2e8,e8k2w5k3g4k2e3k1w10k2g1k2e8,e9k7e2k1g2k2e4k1w10k1g2k1e9,e18k4e5k2w8k2g1k2e9,e28k2w6k2g1k2e10,e29k1w5k5e11,e30k9e12,e51,e51,e51,e51,e51,e51/e51,e51,e51,e29k8e14,e26k4w6k4e11,e24k3w12k3e9,e22k2w17k3e7,e20k2w21k2e6,e19k2w23k2e5,e17k2w26k2e4,e16k2w28k1e4,e16k1w29k2e3,e15k2w30k1e3,e15k1w31k2e2,e14k1w10k5w3k1w3k1w2k5w3k1e2,e14k1w10k5w3k5w2k5w3k2e1,e14k1w18k1w3k1w11k1e1,e14k1w34k1e1,e14k1w34k1e1,e13k1w35k1e1,e13k1w36k1,e13k1w36k1,e12k2w36k1,e12k1w36k2,e12k1w36k1e1,e11k1w37k1e1,e11k1w37k1e1,e10k1w38k1e1,e9k2w37k1e2,e9k1w37k2e2,e8k1w38k1e3,e7k2w37k2e3,e7k1w38k1e4,e6k1w39k1e4,e5k1w40k1e4,e5k2w39k1e4,e5k1g1k1w37k1e5,e4k2g1k1w37k1e5,e4k1g3k1w36k1e5,e3k1g4k1w36k1e5,e3k1g3k1w36k1e6,e2k2g2k2w14k3w19k1e6,e2k1g3k1w13k3g2k1w17k1e7,e2k5w11k3g5k1w16k1e7,e6k1w10k2g7k1w16k1e7,e5k2w8k4g6k2w11k3w2k1e7,e5k2w7k2e2k1g5k3w9k2g2k4e7,e6k2w3k3e4k1g4k2e1k1w9k1g4k2e8,e8k4e6k2g2k2e2k1w8k2g4k2e8,e19k3e4k1w7k3g4k1e9,e27k1w5k2e1k1g3k2e9,e27k2w2k3e2k1g2k2e10,e28k4e4k4e11,e51,e51,e51,e51,e51/e51,e51,e51,e51,e30k4e17,e27k4w2k6e12,e23k4w11k3e10,e21k3w16k2e9,e19k3w20k2e7,e18k2w23k2e6,e17k2w25k2e5,e16k2w27k2e4,e15k2w29k1e4,e15k1w30k2e3,e15k1w9k5w3k1w3k1w2k5w2k2e2,e14k1w10k5w3k5w2k5w3k1e2,e14k1w18k1w3k1w10k2e1,e14k1w34k1e1,e14k1w34k1e1,e13k1w35k1e1,e13k1w35k1e1,e13k1w35k2,e13k1w36k1,e12k2w36k1,e12k1w36k2,e12k1w36k1e1,e11k2w36k1e1,e10k1w38k1e1,e10k1w37k2e1,e10k1w37k1e2,e9k1w37k2e2,e8k2w37k1e3,e8k1w38k1e3,e7k2w38k1e3,e6k1w39k1e4,e6k1w39k1e4,e6k1w39k1e4,e6k1w38k1e5,e5k2w38k1e5,e5k2w38k1e5,e4k3w37k1e6,e4k2w38k1e6,e4k2w15k4w19k1e6,e4k2w13k2g3k2w17k1e7,e4k1w12k3g5k1w17k1e7,e4k1w10k3e1k1g5k1w17k1e7,e4k2w7k3e3k1g5k1w10k4w2k1e8,e6k8e5k1g4k1w10k2g3k1w1k1e8,e19k1g4k1w10k2g3k1w1k1e8,e19k2g2k3w7k4g3k1w1k1e8,e20k4e1k1w6k2e2k1g3k1w1k1e8,e25k1w5k2e4k1g2k3e8,e25k6e6k2g1k2e9,e38k4e9,e51,e51,e51,e51/e51,e51,e51,e51,e51,e51,e51,e25k10e16,e23k3w8k5e12,e21k3w14k3e10,e19k3w18k2e9,e18k2w21k3e7,e17k2w24k2e6,e16k2w26k2e5,e16k1w28k2e4,e15k1w30k2e3,e14k2w9k5w3k1w3k1w2k5w2k1e3,e14k1w10k5w3k5w2k5w2k2e2,e14k1w18k1w3k1w10k1e2,e14k1w33k2e1,e13k1w35k1e1,e13k1w35k1e1,e13k1w35k1e1,e13k1w35k1e1,e13k1w35k1e1,e12k2w35k1e1,e12k1w36k1e1,e12k1w36k1e1,e11k1w37k1e1,e10k2w36k2e1,e10k1w37k1e2,e9k1w38k1e2,e9k1w37k1e3,e8k1w38k1e3,e8k1w38k1e3,e7k1w39k1e3,e7k1w38k1e4,e6k1w39k1e4,e6k1w39k1e4,e5k1w40k1e4,e4k1w40k1e5,e4k1w40k1e5,e3k1w41k1e5,e3k1w15k5w20k1e6,e3k1w14k2e1k1g1k2w19k1e6,e3k1w11k3e3k1g2k1w18k1e7,e3k1w9k3e4k1g3k1w18k1e7,e4k2w5k3e6k1g2k2w18k1e7,e5k6e9k1g2k1w10k5w3k2e7,e20k1g2k1w10k1e1k1g1k2w2k1e8,e20k1g2k1w9k1e3k1g1k1w2k1e8,e20k1g2k1w8k2e3k3w2k1e8,e20k2g1k2w6k1e6k2w2k1e8,e21k4w4k2e8k1w1k2e8,e24k6e9k1w1k1e9,e39k3e9,e51,e51/e51,e51,e51,e51,e51,e51,e51,e51,e26k12e13,e23k4w10k3e11,e21k3w16k2e9,e19k3w19k3e7,e18k2w23k2e6,e17k2w25k2e5,e16k2w27k2e4,e15k2w29k1e4,e15k1w31k1e3,e14k2w31k2e2,e14k1w10k5w3k1w3k1w2k5w3k1e2,e14k1w10k5w3k5w2k5w3k1e2,e13k2w18k1w3k1w10k2e1,e13k1w35k1e1,e13k1w35k1e1,e13k1w35k1e1,e13k1w35k1e1,e12k2w35k1e1,e12k1w36k1e1,e12k1w36k1e1,e12k1w36k1e1,e11k1w37k1e1,e10k1w37k2e1,e10k1w37k1e2,e10k1w37k1e2,e9k1w37k1e3,e8k1w38k1e3,e8k1w38k1e3,e7k1w39k1e3,e7k1w38k1e4,e6k1w39k1e4,e6k1w39k1e4,e5k1w40k1e4,e4k1w40k1e5,e3k1w41k1e5,e3k1w13k5w23k1e5,e2k2w11k2e4k2w21k1e6,e2k1w10k3e6k1w21k1e6,e2k1w7k3g1k1e6k2w20k1e7,e2k3w2k4g2k2e6k1w21k1e7,e4k4e1k1g1k3e7k1w21k1e7,e9k3e8k1w11k5w5k2e7,e20k1w10k2e3k2w5k1e7,e20k1w9k2e5k1w4k1e8,e20k1w8k2e6k1w4k1e8,e20k2w6k2e7k2w3k1e8,e21k2w2k4e9k1w2k2e8,e22k3e13k1w2k1e9,e38k4e9,e39k2e10/e51,e51,e51,e51,e51,e51,e51,e27k11e13,e24k4w10k3e10,e21k3w16k3e8,e19k3w20k2e7,e18k2w23k2e6,e17k2w25k2e5,e16k2w27k2e4,e15k2w29k1e4,e14k2w30k2e3,e14k1w32k1e3,e13k2w32k2e2,e13k1w11k5w3k1w3k1w2k5w3k1e2,e13k1w11k5w3k5w2k5w3k1e2,e13k1w19k1w3k1w11k1e1,e12k1w36k1e1,e12k1w36k1e1,e12k1w36k1e1,e12k1w36k1e1,e12k1w36k1e1,e11k1w36k2e1,e11k1w36k1e2,e10k1w37k1e2,e10k1w37k1e2,e9k1w38k1e2,e9k1w37k2e2,e8k1w38k1e3,e8k1w38k1e3,e7k1w39k1e3,e7k1w39k1e3,e6k1w39k1e4,e5k2w39k1e4,e4k2w40k1e4,e3k1w41k1e5,e2k1w42k1e5,e1k2w11k5w26k1e5,e1k1w11k2g3k2w24k1e6,e1k1w8k3g4k3w24k1e6,e1k1w6k3g6k1e1k1w24k1e6,e1k1w3k5g6k1e1k1w24k1e7,e1k5e3k1g5k1e2k1w24k1e7,e9k1g3k2e3k1w23k2e7,e10k4e3k2w14k4w5k1e8,e17k1w14k2e2k2w4k1e8,e17k1w12k2e5k1w4k1e8,e17k2w10k2e6k1w3k2e8,e18k2w7k3e7k1w3k1e9,e19k2w3k3g1k1e8k1w3k1e9,e20k9e8k1w2k2e9,e37k4e10,e38k2e11,e51"
local kGhostW, kGhostH = 51, 58
local ghostPalette = {
	k = Color3.fromRGB(10, 10, 14),
	w = Color3.fromRGB(255, 255, 255),
	g = Color3.fromRGB(157, 157, 157),
}

-- frames split by "/", rows by ",", each row is run-length pairs like k12w30e9 (e = empty)
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

-- px = screen pixels per ghost pixel (whole numbers keep the edges crisp)
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

	-- plays the animation `cycles` times and blocks, so call it from task.spawn
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
mainFrame.BackgroundColor3 = Color3.new(1, 1, 1) -- gradient below supplies the real color
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
-- TOAST NOTIFICATIONS
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
creditLabel.Text = "made by Dani"
creditLabel.TextColor3 = kTextDim
creditLabel.Font = Enum.Font.Gotham
creditLabel.TextSize = 13
creditLabel.TextXAlignment = Enum.TextXAlignment.Left
creditLabel.TextTransparency = 1
creditLabel.Parent = titleBar

-- live "N active" badge
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
closeBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 54)
closeBtn.Text = "X"
closeBtn.TextColor3 = Color3.fromRGB(200, 200, 215)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 13
closeBtn.AutoButtonColor = false
closeBtn.Parent = titleBar
addCorner(closeBtn, -1)

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
local tabBar = Instance.new("Frame")
tabBar.Name = "TabBar"
tabBar.Size = UDim2.new(1, -20, 0, 32)
tabBar.Position = UDim2.new(0, 10, 0, 62)
tabBar.BackgroundTransparency = 1
tabBar.Parent = mainFrame

do
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Horizontal
	l.Padding = UDim.new(0, 8)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = tabBar
end

local pagesHolder = Instance.new("Frame")
pagesHolder.Name = "Pages"
pagesHolder.Size = UDim2.new(1, -20, 1, -164)
pagesHolder.Position = UDim2.new(0, 10, 0, 102)
pagesHolder.BackgroundTransparency = 1
pagesHolder.Parent = mainFrame

local tabNames = { "Move", "Visuals", "Players", "Misc", "Config" }
local tabButtons = {}
local pages = {}
local currentTab = "Move"

local function selectTab(name)
	currentTab = name
	for pname, page in pairs(pages) do
		page.Visible = (pname == name)
	end
	for bname, btn in pairs(tabButtons) do
		local active = (bname == name)
		TweenService:Create(btn, TweenInfo.new(0.15), {
			BackgroundColor3 = active and accent or kRowBg,
		}):Play()
		btn.TextColor3 = active and Color3.new(1, 1, 1) or Color3.fromRGB(150, 150, 165)
	end
end
accentCallbacks[#accentCallbacks + 1] = function() selectTab(currentTab) end

for i, name in ipairs(tabNames) do
	local btn = Instance.new("TextButton")
	btn.Name = name .. "Tab"
	btn.Size = UDim2.new(1 / #tabNames, -(8 * (#tabNames - 1)) / #tabNames, 1, 0)
	btn.LayoutOrder = i
	btn.BackgroundColor3 = kRowBg
	btn.Text = name
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 12
	btn.TextColor3 = Color3.fromRGB(150, 150, 165)
	btn.AutoButtonColor = false
	btn.Parent = tabBar
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

local movePage = pages.Move
local visualsPage = pages.Visuals
local miscPage = pages.Misc
local configPage = pages.Config
local playersPage = pages.Players

----------------------------------------------------------------
-- ROW BUILDERS
----------------------------------------------------------------
local toggleSetters = {} -- every toggle's setState, used by Reset all / Unload
local sliderResets = {}

local function makeSection(text, order, parent)
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, 0, 0, 18)
	lbl.BackgroundTransparency = 1
	lbl.Text = text
	lbl.TextColor3 = Color3.fromRGB(110, 110, 140)
	lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = 12
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.LayoutOrder = order
	lbl.Parent = parent
	return lbl
end

local featureToggles = {} -- key -> { tag, set, get }: lets any toggle be bound to a key
local bindingFeature = nil -- key of the toggle currently waiting for a key press
local rebinding = false -- menu key rebind in progress (Config tab)

local function refreshBindTag(key)
	local e = featureToggles[key]
	if not e then return end
	local bound = settings.binds[key]
	if bindingFeature == key then
		e.tag.Text = "press key"
	else
		e.tag.Text = bound and ("[" .. bound .. "]") or ""
	end
end

-- o = { name, desc, key, opt, color, order, parent, callback }
-- key = saved + bindable toggle, opt = saved menu option (not counted as "active", not reset)
local function makeToggleRow(o)
	local hasDesc = o.desc ~= nil
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
		if not ok then
			warn("[Ghosted Menu] " .. o.name .. ": " .. tostring(err))
		end
		if not silent then
			notify(o.name .. (on and " on" or " off"))
		end
	end

	accentCallbacks[#accentCallbacks + 1] = function(c)
		if state then switchBg.BackgroundColor3 = c end
	end

	track(clickBtn.MouseButton1Click:Connect(function()
		setState(not state)
	end))

	-- right-click (PC): bind this toggle to a key
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

	if not o.opt then
		toggleSetters[#toggleSetters + 1] = setState
	end

	-- restore saved state without a toast
	if o.opt then
		if opts[o.opt] then setState(true, true) end
	elseif o.key and settings.toggles[o.key] == true then
		setState(true, true)
	end

	return row, setState
end

-- o = { name, key, min, max, default, order, parent, callback }
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

-- o = { text, color, order, parent, callback }
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
	track(btn.MouseButton1Click:Connect(function()
		o.callback(btn)
	end))
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

-- floating ghost button: tap to toggle, drag to reposition (the only way to open on mobile)
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

	-- one animation cycle whenever the mouse hovers the ghost
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
-- FOOTER: DISCORD BUTTON (copies the invite link)
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
			if setclipboard then
				setclipboard(kDiscordLink)
			elseif toclipboard then
				toclipboard(kDiscordLink)
			else
				error("no clipboard api")
			end
		end)

		btn.Text = copied and "Copied link!" or "Copy failed - see console"
		TweenService:Create(btn, TweenInfo.new(0.12), {
			BackgroundColor3 = copied and Color3.fromRGB(90, 200, 120) or Color3.fromRGB(220, 80, 80),
		}):Play()
		if not copied then
			warn("[Ghosted Menu] No clipboard API on this executor. Discord: " .. kDiscordLink)
		end

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
-- MOVE TAB
----------------------------------------------------------------
makeSection("FLIGHT", 0, movePage)

-- FLY: survives respawn (re-attaches every frame) and works with keyboard, thumbstick and gamepad
do
	local flySpeed = kDefaultFlySpeed
	local flyConn
	local flyVertical = 0
	local controls -- PlayerModule controls, fetched lazily; false = unavailable

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

	-- camera-relative direction from the same controls the game uses (keyboard/thumbstick/gamepad)
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

	local function cleanupFlyObjects()
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local bv = hrp:FindFirstChild("GhostedFlyBV")
			if bv then bv:Destroy() end
			local bg = hrp:FindFirstChild("GhostedFlyBG")
			if bg then bg:Destroy() end
		end
		local hum = getHumanoid()
		if hum then hum.PlatformStand = false end
	end

	local function setFly(on)
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
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local cam = workspace.CurrentCamera
			if not (hrp and hum and cam) or hum.Health <= 0 then return end

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
			hum.PlatformStand = true

			local vertical = flyVertical
			if not UserInputService:GetFocusedTextBox() then
				if UserInputService:IsKeyDown(Enum.KeyCode.Space) then vertical = 1 end
				if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then vertical = -1 end
			end

			local move = getFlyDirection(hum, cam) + Vector3.new(0, vertical, 0)
			if move.Magnitude > 1 then move = move.Unit end
			bv.Velocity = move * flySpeed
			bg.CFrame = cam.CFrame
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

-- NOCLIP: remembers each part's original CanCollide so disabling restores exactly what the game had
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

-- SPEED: enforced every frame so games that reset WalkSpeed can't undo it
do
	local walkSpeed = kDefaultWalkSpeed
	local speedConn, speedOrig

	local function setSpeed(on)
		disconnect(speedConn)
		speedConn = nil
		local hum = getHumanoid()
		if on then
			if hum and not speedOrig then speedOrig = hum.WalkSpeed end
			speedConn = RunService.Heartbeat:Connect(function()
				local h = getHumanoid()
				if h then h.WalkSpeed = walkSpeed end
			end)
		else
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
				origUse = hum.UseJumpPower
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
-- VISUALS TAB (all of this is local rendering only)
----------------------------------------------------------------
makeSection("ESP", 0, visualsPage)

local hasDrawing = (Drawing ~= nil) and (Drawing.new ~= nil)
local espTeamCheck = false

local chamsFolder = Instance.new("Folder")
chamsFolder.Name = "GhostedChams"
chamsFolder.Parent = guiParent

do
	local esp = { boxes = false, names = false, health = false, distance = false, tracers = false }
	local espCache = {}
	local espMaxDist = kDefaultEspDist
	local espConn
	local chamsOn = false
	local chamsMap = {}

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
			box = newDrawing("Square", { Thickness = 1.5, Color = kEspBoxColor, Filled = false, Visible = false }),
			name = newDrawing("Text", { Size = 14, Center = true, Outline = true, Color = kEspNameColor, Visible = false }),
			tracer = newDrawing("Line", { Thickness = 1, Color = kTracerColor, Visible = false }),
			health = newDrawing("Line", { Thickness = 2, Color = Color3.fromRGB(80, 255, 120), Visible = false }),
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
		d.box.Visible = false
		d.name.Visible = false
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
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			local hum = char and char:FindFirstChildOfClass("Humanoid")

			if hrp and hum and hum.Health > 0 and not sameTeam(plr)
				and (hrp.Position - cam.CFrame.Position).Magnitude <= espMaxDist then
				local top, onScreen = cam:WorldToViewportPoint(hrp.Position + Vector3.new(0, 2.8, 0))
				local bottom = cam:WorldToViewportPoint(hrp.Position - Vector3.new(0, 3.2, 0))

				if onScreen then
					local height = math.abs(bottom.Y - top.Y)
					local width = height * 0.55
					local x = top.X - width / 2
					local y = math.min(top.Y, bottom.Y)

					d.box.Visible = esp.boxes
					if esp.boxes then
						d.box.Size = Vector2.new(width, height)
						d.box.Position = Vector2.new(x, y)
					end

					if esp.names or esp.distance then
						local parts = {}
						if esp.names then parts[#parts + 1] = plr.DisplayName end
						if esp.distance then
							parts[#parts + 1] = "[" .. math.floor((hrp.Position - cam.CFrame.Position).Magnitude) .. " st]"
						end
						d.name.Text = table.concat(parts, " ")
						d.name.Position = Vector2.new(top.X, y - 16)
						d.name.Visible = true
					else
						d.name.Visible = false
					end

					if esp.health then
						local pct = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
						d.health.From = Vector2.new(x - 5, y + height)
						d.health.To = Vector2.new(x - 5, y + height - height * pct)
						d.health.Color = Color3.fromRGB(255 * (1 - pct), 255 * pct, 60)
						d.health.Visible = true
					else
						d.health.Visible = false
					end

					if esp.tracers then
						d.tracer.From = origin
						d.tracer.To = Vector2.new(top.X, y + height)
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

	-- starts/stops the render loop depending on whether any ESP option is on
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
				warn("[Ghosted Menu] This executor has no Drawing API, ESP overlays unavailable (Chams still work).")
			end
			esp[flag] = on
			refreshEsp()
		end
	end

	-- chams use Highlight instances, no Drawing API needed
	local function removeCham(plr)
		local h = chamsMap[plr]
		if h then
			h:Destroy()
			chamsMap[plr] = nil
		end
	end

	local function applyCham(plr)
		if plr == player or not chamsOn then return end
		local char = plr.Character
		if not char or sameTeam(plr) then
			removeCham(plr)
			return
		end
		local h = chamsMap[plr]
		if not h then
			h = Instance.new("Highlight")
			h.Name = plr.Name
			h.FillColor = kChamsFill
			h.OutlineColor = kChamsOutline
			h.FillTransparency = 0.5
			h.OutlineTransparency = 0
			h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			h.Parent = chamsFolder
			chamsMap[plr] = h
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

	makeToggleRow({ name = "Boxes", desc = "Box around every player", key = "espBoxes",
		color = Color3.fromRGB(255, 255, 255), order = 1, parent = visualsPage, callback = espCallback("boxes") })
	makeToggleRow({ name = "Names", desc = "Display names above heads", key = "espNames",
		color = Color3.fromRGB(255, 255, 255), order = 2, parent = visualsPage, callback = espCallback("names") })
	makeToggleRow({ name = "Health Bars", desc = "Bar to the left of the box", key = "espHealth",
		color = Color3.fromRGB(80, 255, 120), order = 3, parent = visualsPage, callback = espCallback("health") })
	makeToggleRow({ name = "Distance", desc = "Studs away, shown with the name", key = "espDistance",
		color = Color3.fromRGB(255, 200, 90), order = 4, parent = visualsPage, callback = espCallback("distance") })
	makeToggleRow({ name = "Tracers", desc = "Line from bottom-center to each player", key = "espTracers",
		color = Color3.fromRGB(110, 110, 255), order = 5, parent = visualsPage, callback = espCallback("tracers") })
	makeToggleRow({ name = "Chams", desc = "Highlight players through walls", key = "chams",
		color = Color3.fromRGB(255, 70, 90), order = 6, parent = visualsPage, callback = setChams })
	makeToggleRow({ name = "Team Check", desc = "Skip your own teammates", key = "teamCheck",
		color = Color3.fromRGB(90, 200, 255), order = 7, parent = visualsPage,
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

-- FULLBRIGHT: enforced every frame so day/night cycles can't dim it
do
	local fbConn
	local saved

	local function setFullbright(on)
		disconnect(fbConn)
		fbConn = nil
		if on then
			saved = {
				Brightness = Lighting.Brightness,
				ClockTime = Lighting.ClockTime,
				FogEnd = Lighting.FogEnd,
				GlobalShadows = Lighting.GlobalShadows,
				Ambient = Lighting.Ambient,
				OutdoorAmbient = Lighting.OutdoorAmbient,
			}
			fbConn = RunService.RenderStepped:Connect(function()
				Lighting.Brightness = 2
				Lighting.ClockTime = 14
				Lighting.FogEnd = 1e5
				Lighting.GlobalShadows = false
				Lighting.Ambient = Color3.fromRGB(178, 178, 178)
				Lighting.OutdoorAmbient = Color3.fromRGB(178, 178, 178)
			end)
		elseif saved then
			for k, v in pairs(saved) do
				pcall(function() Lighting[k] = v end)
			end
			saved = nil
		end
	end

	makeToggleRow({
		name = "Fullbright", desc = "Removes darkness and fog",
		key = "fullbright", color = Color3.fromRGB(255, 240, 150), order = 10, parent = visualsPage, callback = setFullbright,
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

-- CROSSHAIR: plain frames in their own gui (ignores the top bar inset so it sits dead center)
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
	bar(0, 9, 2, 7)
	bar(-9, 0, 7, 2)
	bar(9, 0, 7, 2)
	bar(0, 0, 2, 2)

	onUnload(function() crossGui:Destroy() end)

	makeToggleRow({
		name = "Crosshair", desc = "Accent colored dot-cross at screen center",
		key = "crosshair", color = Color3.fromRGB(255, 120, 120), order = 12, parent = visualsPage,
		callback = function(on) holder.Visible = on end,
	})
end

-- CUSTOM TIME: locks the time of day
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
		key = "customTime", color = Color3.fromRGB(255, 190, 90), order = 13, parent = visualsPage, callback = setCustomTime,
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
-- PLAYERS TAB (search, teleport to, spectate)
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
			local cam = workspace.CurrentCamera
			local char = viewing and viewing.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
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
		local hrp = myChar and myChar:FindFirstChild("HumanoidRootPart")
		local tChar = plr.Character
		local tHrp = tChar and tChar:FindFirstChild("HumanoidRootPart")
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
		b.Size = UDim2.new(0, 48, 0, 28)
		b.BackgroundColor3 = accent
		b.Text = text
		b.TextColor3 = Color3.new(1, 1, 1)
		b.Font = Enum.Font.GothamBold
		b.TextSize = 12
		b.AutoButtonColor = false
		b.Parent = parent
		addCorner(b, 6)
		track(b.MouseButton1Click:Connect(onClick))
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
				or string.find(string.lower(plr.Name), q, 1, true)
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
				nameLbl.Size = UDim2.new(1, -130, 0, 18)
				nameLbl.Position = UDim2.new(0, 12, 0, 5)
				nameLbl.BackgroundTransparency = 1
				nameLbl.Text = plr.DisplayName
				nameLbl.TextColor3 = Color3.fromRGB(230, 230, 235)
				nameLbl.Font = Enum.Font.GothamBold
				nameLbl.TextSize = 14
				nameLbl.TextXAlignment = Enum.TextXAlignment.Left
				nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
				nameLbl.Parent = row

				local subLbl = Instance.new("TextLabel")
				subLbl.Size = UDim2.new(1, -130, 0, 14)
				subLbl.Position = UDim2.new(0, 12, 0, 25)
				subLbl.BackgroundTransparency = 1
				subLbl.Text = "@" .. plr.Name
				subLbl.TextColor3 = kTextDim
				subLbl.Font = Enum.Font.Gotham
				subLbl.TextSize = 11
				subLbl.TextXAlignment = Enum.TextXAlignment.Left
				subLbl.TextTruncate = Enum.TextTruncate.AtEnd
				subLbl.Parent = row

				smallButton(row, "TP", -62, function() teleportTo(plr) end)
				smallButton(row, "View", -10, function() startViewing(plr) end)
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

-- CLICK TELEPORT: Ctrl+click on PC, quick tap on mobile (teleports only yourself)
do
	local beginConn, endConn
	local touches = setmetatable({}, { __mode = "k" })

	local function teleportToRay(ray)
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
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
		key = "clicktp", color = Color3.fromRGB(180, 130, 255), order = 2, parent = miscPage, callback = setClickTp,
	})
end

-- STATS HUD
do
	local statsLabel = Instance.new("TextLabel")
	statsLabel.Name = "StatsHud"
	statsLabel.AnchorPoint = Vector2.new(0.5, 0)
	statsLabel.Position = UDim2.new(0.5, 0, 0, 8)
	statsLabel.Size = UDim2.new(0, 170, 0, 24)
	statsLabel.BackgroundColor3 = Color3.fromRGB(22, 22, 30)
	statsLabel.BackgroundTransparency = 0.25
	statsLabel.TextColor3 = Color3.new(1, 1, 1)
	statsLabel.Font = Enum.Font.GothamBold
	statsLabel.TextSize = 13
	statsLabel.Text = "-- FPS  |  -- ms"
	statsLabel.Visible = false
	statsLabel.Parent = screenGui
	addCorner(statsLabel, -1)

	local statsConn
	local function setStats(on)
		disconnect(statsConn)
		statsConn = nil
		statsLabel.Visible = on
		if on then
			local frames, acc = 0, 0
			statsConn = RunService.Heartbeat:Connect(function(dt)
				frames = frames + 1
				acc = acc + dt
				if acc >= 0.5 then
					local fps = math.floor(frames / acc + 0.5)
					local ping = 0
					pcall(function()
						ping = math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue() + 0.5)
					end)
					statsLabel.Text = fps .. " FPS  |  " .. ping .. " ms"
					frames, acc = 0, 0
				end
			end)
		end
	end

	makeToggleRow({
		name = "Stats HUD", desc = "FPS and ping at the top of the screen",
		key = "stats", color = Color3.fromRGB(90, 200, 255), order = 3, parent = miscPage, callback = setStats,
	})
end

makeButtonRow({
	text = "Rejoin This Server", order = 7, parent = miscPage,
	callback = function()
		notify("Rejoining...")
		local ok = pcall(function()
			TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, player)
		end)
		if not ok then
			pcall(function() TeleportService:Teleport(game.PlaceId, player) end)
		end
	end,
})

-- ANTI-VOID: snaps you back to your last safe spot when you fall out of the map
do
	local voidConn, lastSafe
	local function setAntiVoid(on)
		disconnect(voidConn)
		voidConn = nil
		lastSafe = nil
		if not on then return end
		voidConn = RunService.Heartbeat:Connect(function()
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if not hrp then return end
			local floorY = workspace.FallenPartsDestroyHeight
			if hrp.Position.Y > floorY + 60 then
				local hum = char:FindFirstChildOfClass("Humanoid")
				if hum and hum.FloorMaterial ~= Enum.Material.Air then lastSafe = hrp.CFrame end
			elseif lastSafe then
				hrp.AssemblyLinearVelocity = Vector3.zero
				hrp.CFrame = lastSafe + Vector3.new(0, 3, 0)
			end
		end)
	end
	makeToggleRow({
		name = "Anti-Void", desc = "Saves you from falling out of the map",
		key = "antivoid", color = Color3.fromRGB(255, 120, 150), order = 4, parent = miscPage, callback = setAntiVoid,
	})
end

-- FPS CAP (needs setfpscap)
do
	local touched = false
	makeSliderRow({
		name = "FPS Cap", key = "fpsCap", min = 30, max = 360, default = 60,
		order = 5, parent = miscPage,
		callback = function(v)
			touched = true
			if typeof(setfpscap) == "function" then pcall(setfpscap, v) end
		end,
	})
	onUnload(function()
		if touched and typeof(setfpscap) == "function" then pcall(setfpscap, 60) end
	end)
end

makeSection("SERVER", 6, miscPage)

local function copyText(text, label)
	local ok = pcall(function()
		if setclipboard then
			setclipboard(text)
		elseif toclipboard then
			toclipboard(text)
		else
			error("no clipboard api")
		end
	end)
	notify(ok and (label .. " copied") or "Clipboard not supported here")
end

-- SERVER HOP: picks a random public server that isn't this one (needs game:HttpGet)
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
					local okJson, data = pcall(function() return HttpService:JSONDecode(body) end)
					if okJson and type(data) == "table" and type(data.data) == "table" then
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

makeButtonRow({
	text = "Copy Job ID", order = 9, parent = miscPage,
	callback = function() copyText(game.JobId, "Job ID") end,
})
makeButtonRow({
	text = "Copy Place ID", order = 10, parent = miscPage,
	callback = function() copyText(tostring(game.PlaceId), "Place ID") end,
})
makeButtonRow({
	text = "Reset Character", order = 11, parent = miscPage,
	callback = function()
		local hum = getHumanoid()
		if hum then hum.Health = 0 end
	end,
})

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

	for i, t in ipairs(themes) do
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(0, 24, 0, 24)
		b.AnchorPoint = Vector2.new(1, 0.5)
		b.Position = UDim2.new(1, -10 - (#themes - i) * 30, 0.5, 0)
		b.BackgroundColor3 = t.color
		b.Text = ""
		b.AutoButtonColor = false
		b.Parent = row
		addCorner(b, -1)
		track(b.MouseButton1Click:Connect(function()
			setAccent(i)
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
	callback = function(v) mainFrame.BackgroundTransparency = 1 - v / 100 end,
})

makeSection("STARTUP", 4, configPage)
makeToggleRow({
	name = "Startup Splash", desc = "Ghost intro animation when the menu loads",
	opt = "splash", color = Color3.fromRGB(190, 190, 255), order = 5, parent = configPage,
	callback = function() end,
})
makeToggleRow({
	name = "Open On Load", desc = "Show the menu right after loading",
	opt = "openOnLoad", color = Color3.fromRGB(190, 190, 255), order = 6, parent = configPage,
	callback = function() end,
})
makeToggleRow({
	name = "Notifications", desc = "Toast messages at the bottom",
	opt = "notifs", color = Color3.fromRGB(190, 190, 255), order = 7, parent = configPage,
	callback = function() end,
})
makeToggleRow({
	name = "Floating Ghost", desc = "Hide it and use the menu key instead",
	opt = "showButton", color = Color3.fromRGB(190, 190, 255), order = 8, parent = configPage,
	callback = function(on) toggleBtn.Visible = on end,
})

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
	if input.KeyCode == toggleKey then
		toggleMenu()
		return
	end
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
		for _, r in ipairs(sliderResets) do pcall(r) end
		settings.toggles = {}
		settings.sliders = {}
		settings.binds = {}
		for key in pairs(featureToggles) do refreshBindTag(key) end
		saveSettings()
		notify("Everything reset")
	end,
})

local function unload()
	alive = false
	for _, s in ipairs(toggleSetters) do pcall(s, false, true) end
	for _, fn in ipairs(cleanups) do pcall(fn) end
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
	credit.Text = "Ghosted Menu - made by Dani"
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
	local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
	local px = math.clamp(math.floor(math.min(vp.X, vp.Y) / 150), 2, 4)
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

	-- CanvasGroup lets the whole ghost fade as one piece; plain frame is the fallback
	local okCanvas, holder = pcall(Instance.new, "CanvasGroup")
	if not okCanvas or typeof(holder) ~= "Instance" then holder = Instance.new("Frame") end
	local isCanvas = holder:IsA("CanvasGroup")

	local blockH = gh + 92
	local top = -math.floor(blockH / 2)
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
	sub.Text = "made by Dani"
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

	-- ghost animation runs on its own thread until the exit
	local running = true
	task.spawn(function()
		local i = 1
		while running and alive and holder.Parent do
			ghost:setFrame(i)
			i = i % #ghostFrames + 1
			task.wait(0.05)
		end
	end)

	-- in
	TweenService:Create(overlay, TweenInfo.new(0.25), { BackgroundTransparency = 0.08 }):Play()
	if isCanvas then
		TweenService:Create(holder, TweenInfo.new(0.5), { GroupTransparency = 0 }):Play()
	end
	TweenService:Create(holder, TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0.5, ghostY),
	}):Play()
	pause(0.5)

	-- title types out, bar fills in steps
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

	-- out: the ghost shrinks into the floating button
	running = false
	local outInfo = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	if alive and toggleBtn.Visible then
		local target = toggleBtn.AbsolutePosition + toggleBtn.AbsoluteSize / 2 - overlay.AbsolutePosition
		TweenService:Create(holder, outInfo, { Position = UDim2.fromOffset(target.X, target.Y) }):Play()
		TweenService:Create(holderScale, outInfo, { Scale = 0.3 }):Play()
	end
	if isCanvas then
		TweenService:Create(holder, TweenInfo.new(0.45), { GroupTransparency = 1 }):Play()
	end
	TweenService:Create(title, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
	TweenService:Create(sub, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
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
