--!strict
-- On-screen everything, and no words: vignette, glitches, a few faint dots
-- for how far along you are, stamina, flashlight battery, bottles, the hold-your-breath
-- meter, the night's title, fades, flashes and the red of its rage.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Audio = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Audio"))

local GameState = ReplicatedStorage:WaitForChild("GameState")
local player = Players.LocalPlayer

local Hud = {}

local TEXT = Color3.fromRGB(205, 205, 200)
local BLACK = Color3.new(0, 0, 0)
local DANGER = Color3.fromRGB(220, 70, 60)
Hud.TITLE_FONT = Enum.Font.Garamond

local gui: ScreenGui
local pips: Frame
local pipDots: { Frame } = {}
local pipsShownAt = -math.huge
local blinkFrame: Frame
local staminaFrame: Frame
local staminaFill: Frame
local batteryFrame: Frame
local batterySegments: { Frame } = {}
local bigTitle: TextLabel
local fadeFrame: Frame
local flashFrame: Frame
local whiteFrame: Frame
local vignette: { Frame } = {}
local glitchBars: { Frame } = {}
local crosshair: Frame
local bottles: Frame
local bottleMarks: { Frame } = {}
local breathFrame: Frame
local breathFill: Frame
local breathUrgent = false
local rageFrame: Frame

local fearLevel = 0
local glitchAmount = 0
local glitchUntil = 0
local pulse = 0
local staminaShownAt = 0
local hidingDark = false

local function new<T>(className: string, props: { [string]: any }, parent: Instance?): T
	local inst = Instance.new(className :: any)
	for k, v in props do
		(inst :: any)[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return (inst :: any) :: T
end

-- "NIGHT 1" -> "N I G H T   1": the only words the game ever shows
function Hud.spaced(text: string): string
	local out = {}
	for _, word in string.split(text, " ") do
		local letters = {}
		for i = 1, #word do
			table.insert(letters, string.sub(word, i, i))
		end
		table.insert(out, table.concat(letters, " "))
	end
	return table.concat(out, "    ")
end

local function corner(parent: Instance, radius: number?)
	new("UICorner", { CornerRadius = UDim.new(radius or 0.5, 0) }, parent)
end

local function edgeShade(name: string, size: UDim2, position: UDim2, anchor: Vector2, rotation: number): Frame
	local f: Frame = new("Frame", {
		Name = name,
		BackgroundColor3 = BLACK,
		BorderSizePixel = 0,
		Size = size,
		Position = position,
		AnchorPoint = anchor,
		ZIndex = 2,
	}, gui)
	new("UIGradient", {
		Rotation = rotation,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.45, 0.55),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, f)
	return f
end

function Hud.init()
	gui = new("ScreenGui", {
		Name = "AchromaHud",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 5,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, player:WaitForChild("PlayerGui"))

	-- vignette
	table.insert(vignette, edgeShade("Top", UDim2.fromScale(1, 0.38), UDim2.fromScale(0, 0), Vector2.zero, 90))
	table.insert(vignette, edgeShade("Bottom", UDim2.fromScale(1, 0.38), UDim2.fromScale(0, 1), Vector2.new(0, 1), 270))
	table.insert(vignette, edgeShade("Left", UDim2.fromScale(0.3, 1), UDim2.fromScale(0, 0), Vector2.zero, 0))
	table.insert(vignette, edgeShade("Right", UDim2.fromScale(0.3, 1), UDim2.fromScale(1, 0), Vector2.new(1, 0), 180))

	for _ = 1, 8 do
		table.insert(glitchBars, new("Frame", { BorderSizePixel = 0, Visible = false, ZIndex = 4, BackgroundColor3 = Color3.new(1, 1, 1) }, gui))
	end

	crosshair = new("Frame", { Name = "Crosshair", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(4, 4), BackgroundColor3 = TEXT, BackgroundTransparency = 0.55, BorderSizePixel = 0, ZIndex = 5 }, gui)
	corner(crosshair)

	-- how far along you are: a row of faint dots (top centre) that light up one by one
	pips = new("Frame", { Name = "Pips", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 26), Size = UDim2.fromOffset(240, 8), BackgroundTransparency = 1, ZIndex = 5 }, gui)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }, pips)
	blinkFrame = new("Frame", { Name = "Blink", Size = UDim2.fromScale(1, 1), BackgroundColor3 = BLACK, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 8 }, gui)

	-- stamina (bottom centre)
	staminaFrame = new("Frame", { Name = "Stamina", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -34), Size = UDim2.fromOffset(260, 4), BackgroundColor3 = Color3.fromRGB(40, 40, 40), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 5 }, gui)
	staminaFill = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = TEXT, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 5 }, staminaFrame)

	-- flashlight battery (bottom right): five faint ticks
	batteryFrame = new("Frame", { Name = "Battery", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -30, 1, -30), Size = UDim2.fromOffset(80, 8), BackgroundTransparency = 1, ZIndex = 5 }, gui)
	for i = 1, 5 do
		table.insert(batterySegments, new("Frame", { Position = UDim2.fromOffset((i - 1) * 16, 0), Size = UDim2.fromOffset(12, 4), BackgroundColor3 = TEXT, BorderSizePixel = 0, ZIndex = 5 }, batteryFrame))
	end

	-- bottles you're carrying (above the battery): one small mark each
	bottles = new("Frame", { Name = "Bottles", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -30, 1, -48), Size = UDim2.fromOffset(80, 14), BackgroundTransparency = 1, ZIndex = 5 }, gui)
	for i = 1, 3 do
		table.insert(bottleMarks, new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -(i - 1) * 10, 0, 0), Size = UDim2.fromOffset(4, 14), BackgroundColor3 = TEXT, BackgroundTransparency = 0.45, BorderSizePixel = 0, Visible = false, ZIndex = 5 }, bottles))
	end

	-- hold your breath (centre, only while you're hiding): a thin line that runs out
	breathFrame = new("Frame", { Name = "Breath", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.7), Size = UDim2.fromOffset(240, 3), BackgroundColor3 = Color3.fromRGB(30, 30, 30), BackgroundTransparency = 0.4, BorderSizePixel = 0, Visible = false, ZIndex = 7 }, gui)
	breathFill = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromScale(1, 1), BackgroundColor3 = TEXT, BorderSizePixel = 0, ZIndex = 7 }, breathFrame)

	-- the red wash while it's enraged
	rageFrame = new("Frame", { Name = "Rage", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(150, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 2 }, gui)

	bigTitle = new("TextLabel", { Name = "BigTitle", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.48), Size = UDim2.new(0.9, 0, 0, 60), BackgroundTransparency = 1, Font = Hud.TITLE_FONT, TextSize = 40, TextColor3 = TEXT, Text = "", TextTransparency = 1, ZIndex = 11 }, gui)

	fadeFrame = new("Frame", { Name = "Fade", Size = UDim2.fromScale(1, 1), BackgroundColor3 = BLACK, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 9 }, gui)
	whiteFrame = new("Frame", { Name = "White", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 10 }, gui)
	flashFrame = new("Frame", { Name = "Flash", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 10 }, gui)

	-- a developer-only reminder (Studio, never in the published game)
	if RunService:IsStudio() and not Audio.isConfigured() then
		new("TextLabel", { Text = "Audio IDs not set: see README (ReplicatedStorage.Shared.SoundIds)", BackgroundTransparency = 1, Font = Enum.Font.SourceSans, Position = UDim2.fromOffset(12, 8), Size = UDim2.fromOffset(520, 20), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 14, TextColor3 = Color3.fromRGB(150, 150, 150), ZIndex = 12 }, gui)
	end

	local function refreshPips()
		local done = GameState:GetAttribute("Done")
		local goal = GameState:GetAttribute("Goal")
		local d = if typeof(done) == "number" then done else 0
		local g = if typeof(goal) == "number" then goal else 0
		while #pipDots < g do
			local dot: Frame = new("Frame", { Size = UDim2.fromOffset(5, 5), BackgroundColor3 = TEXT, BorderSizePixel = 0, LayoutOrder = #pipDots + 1, ZIndex = 5 }, pips)
			corner(dot)
			table.insert(pipDots, dot)
		end
		for i, dot in pipDots do
			dot.Visible = i <= g
			dot:SetAttribute("Lit", i <= d)
		end
		pipsShownAt = os.clock()
	end
	GameState:GetAttributeChangedSignal("Done"):Connect(refreshPips)
	GameState:GetAttributeChangedSignal("Goal"):Connect(refreshPips)
	refreshPips()
	-- statue night: everyone blinks
	GameState:GetAttributeChangedSignal("Blink"):Connect(function()
		if GameState:GetAttribute("Blink") == true then
			blinkFrame.BackgroundTransparency = 0
		else
			TweenService:Create(blinkFrame, TweenInfo.new(0.15), { BackgroundTransparency = 1 }):Play()
		end
	end)

	Hud.setHudVisible(false)
	RunService.RenderStepped:Connect(Hud._update)
end

function Hud._update(dt: number)
	local t = os.clock()

	-- vignette tightens with fear and pulses with the heartbeat
	pulse = math.max(0, pulse - dt * 3)
	local base = 0.35 - fearLevel * 0.3 - pulse * 0.25 - (if hidingDark then 0.3 else 0)
	for _, v in vignette do
		v.BackgroundTransparency = math.clamp(base, 0, 1)
	end

	-- glitch bars
	local g = math.max(glitchAmount * (if t < glitchUntil then 1 else 0), fearLevel > 0.75 and (fearLevel - 0.75) * 1.6 or 0)
	for _, bar in glitchBars do
		if g > 0 and math.random() < g * 0.9 then
			bar.Visible = true
			bar.Position = UDim2.new(math.random() * 0.1 - 0.05, 0, math.random(), 0)
			bar.Size = UDim2.new(1.1, 0, 0, math.random(2, 4 + math.floor(g * 26)))
			bar.BackgroundColor3 = if math.random() < 0.5 then Color3.new(1, 1, 1) else BLACK
			bar.BackgroundTransparency = 0.35 + math.random() * 0.5
		else
			bar.Visible = false
		end
	end

	-- stamina fades away when full
	local showStamina = t - staminaShownAt < 1.2
	staminaFrame.BackgroundTransparency = if showStamina then 0.4 else 1
	staminaFill.BackgroundTransparency = if showStamina then 0.15 else 1

	-- the dots stand out for a few seconds after they change, then sink back into the dark.
	-- When they're all lit they breathe.
	local since = t - pipsShownAt
	local loud = math.clamp(1 - (since - 4) / 2, 0, 1)
	local all = #pipDots > 0
	for _, dot in pipDots do
		if dot.Visible and dot:GetAttribute("Lit") ~= true then
			all = false
		end
	end
	for _, dot in pipDots do
		local lit = dot:GetAttribute("Lit") == true
		local quiet = if lit then (if all then 0.55 + 0.25 * math.sin(t * 1.6) else 0.75) else 0.93
		local shown = if lit then 0.1 else 0.75
		dot.BackgroundTransparency = quiet + (shown - quiet) * loud
	end

	if breathFrame.Visible then
		breathFill.BackgroundColor3 = if breathUrgent and math.floor(t * 6) % 2 == 0 then DANGER else TEXT
	end
end

function Hud.setHudVisible(visible: boolean)
	pips.Visible = visible
	batteryFrame.Visible = visible
	bottles.Visible = visible
	staminaFrame.Visible = visible
	crosshair.Visible = visible
end

function Hud.setStamina(fraction: number)
	staminaFill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
	if fraction < 0.995 then
		staminaShownAt = os.clock()
	end
end

function Hud.setBattery(fraction: number)
	local lit = math.ceil(math.clamp(fraction, 0, 1) * #batterySegments - 0.001)
	for i, seg in batterySegments do
		seg.BackgroundTransparency = if i <= lit then (if fraction < 0.2 then 0.55 + math.random() * 0.3 else 0.5) else 0.9
	end
end

function Hud.setBottles(n: number)
	for i, mark in bottleMarks do
		mark.Visible = i <= n
	end
end

-- fraction: breath left (0..1). urgent: it's right outside and you're not holding it.
function Hud.setBreath(visible: boolean, fraction: number, urgent: boolean)
	breathFrame.Visible = visible
	breathFill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
	breathUrgent = urgent or fraction < 0.25
end

function Hud.setRage(amount: number)
	rageFrame.BackgroundTransparency = 1 - math.clamp(amount, 0, 1) * 0.16
end

function Hud.setFear(f: number)
	fearLevel = f
end

function Hud.pulse(strength: number)
	pulse = math.max(pulse, strength)
end

function Hud.glitch(amount: number, duration: number)
	glitchAmount = amount
	glitchUntil = os.clock() + duration
end

function Hud.setHiding(on: boolean)
	hidingDark = on
end

-- The night's title in the middle of the dark ("NIGHT 3", letter-spaced). It's already
-- there (the menu's black screen showed it while the night loaded); it fades out slowly.
function Hud.showTitle(title: string)
	bigTitle.Text = Hud.spaced(title)
	bigTitle.TextTransparency = 0.05
end

function Hud.hideTitle()
	TweenService:Create(bigTitle, TweenInfo.new(1.6, Enum.EasingStyle.Sine), { TextTransparency = 1 }):Play()
end

-- 0 = fully black, 1 = clear
function Hud.fade(transparency: number, time: number)
	if time <= 0 then
		fadeFrame.BackgroundTransparency = transparency
	else
		TweenService:Create(fadeFrame, TweenInfo.new(time), { BackgroundTransparency = transparency }):Play()
	end
end

function Hud.whiteout(transparency: number, time: number)
	if time <= 0 then
		whiteFrame.BackgroundTransparency = transparency
	else
		TweenService:Create(whiteFrame, TweenInfo.new(time), { BackgroundTransparency = transparency }):Play()
	end
end

function Hud.flash(strength: number?, time: number?)
	flashFrame.BackgroundTransparency = 1 - (strength or 0.9)
	TweenService:Create(flashFrame, TweenInfo.new(time or 0.25), { BackgroundTransparency = 1 }):Play()
end

function Hud.gui(): ScreenGui
	return gui
end

return Hud
