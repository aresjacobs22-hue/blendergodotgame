--!strict
-- On-screen everything: film grain, vignette, glitches, keys/code readout, stamina,
-- flashlight battery, typewriter messages, big titles, fades and flashes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Audio = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Audio"))

local GameState = ReplicatedStorage:WaitForChild("GameState")
local player = Players.LocalPlayer

local Hud = {}

local TEXT = Color3.fromRGB(205, 205, 200)
local DIM = Color3.fromRGB(120, 120, 116)
local BLACK = Color3.new(0, 0, 0)
local FONT = Enum.Font.SpecialElite

local gui: ScreenGui
local info: Frame
local keyBoxes: { Frame } = {}
local codeLabel: TextLabel
local staminaFrame: Frame
local staminaFill: Frame
local batteryFrame: Frame
local batterySegments: { Frame } = {}
local messages: Frame
local bigTitle: TextLabel
local bigSub: TextLabel
local fadeFrame: Frame
local flashFrame: Frame
local whiteFrame: Frame
local grain: Frame
local specks: { Frame } = {}
local vignette: { Frame } = {}
local glitchBars: { Frame } = {}
local hint: TextLabel
local crosshair: Frame

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

local function label(props: { [string]: any }, parent: Instance): TextLabel
	local defaults: { [string]: any } = {
		BackgroundTransparency = 1,
		Font = FONT,
		TextColor3 = TEXT,
		TextStrokeTransparency = 0.6,
		TextStrokeColor3 = BLACK,
		TextSize = 20,
	}
	for k, v in props do
		defaults[k] = v
	end
	return new("TextLabel", defaults, parent)
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

	-- film grain + dust
	grain = new("Frame", { Name = "Grain", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.97, BorderSizePixel = 0, ZIndex = 1 }, gui)
	for _ = 1, 36 do
		table.insert(specks, new("Frame", { Size = UDim2.fromOffset(2, 2), BorderSizePixel = 0, ZIndex = 1, BackgroundTransparency = 1 }, gui))
	end

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

	-- keys + code (bottom left)
	info = new("Frame", { Name = "Info", BackgroundTransparency = 1, Position = UDim2.new(0, 28, 1, -96), Size = UDim2.fromOffset(320, 76), ZIndex = 5 }, gui)
	label({ Text = "KEYS", Size = UDim2.fromOffset(60, 24), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = DIM, ZIndex = 5 }, info)
	for i = 1, 4 do
		local box: Frame = new("Frame", { Position = UDim2.fromOffset(64 + (i - 1) * 26, 4), Size = UDim2.fromOffset(16, 16), BackgroundColor3 = TEXT, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 5 }, info)
		new("UIStroke", { Color = TEXT, Thickness = 1.5, Transparency = 0.3 }, box)
		table.insert(keyBoxes, box)
	end
	label({ Text = "CODE", Position = UDim2.fromOffset(0, 34), Size = UDim2.fromOffset(60, 24), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = DIM, ZIndex = 5 }, info)
	codeLabel = label({ Text = "_ _ _ _", Position = UDim2.fromOffset(64, 32), Size = UDim2.fromOffset(200, 28), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 26, ZIndex = 5 }, info)

	-- stamina (bottom centre)
	staminaFrame = new("Frame", { Name = "Stamina", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -34), Size = UDim2.fromOffset(260, 4), BackgroundColor3 = Color3.fromRGB(40, 40, 40), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 5 }, gui)
	staminaFill = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = TEXT, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 5 }, staminaFrame)

	-- flashlight battery (bottom right)
	batteryFrame = new("Frame", { Name = "Battery", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -28, 1, -28), Size = UDim2.fromOffset(180, 30), BackgroundTransparency = 1, ZIndex = 5 }, gui)
	label({ Text = "LIGHT", Size = UDim2.fromOffset(64, 30), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = DIM, ZIndex = 5 }, batteryFrame)
	for i = 1, 5 do
		table.insert(batterySegments, new("Frame", { Position = UDim2.fromOffset(66 + (i - 1) * 21, 9), Size = UDim2.fromOffset(16, 12), BackgroundColor3 = TEXT, BorderSizePixel = 0, ZIndex = 5 }, batteryFrame))
	end

	hint = label({ Name = "Hint", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -60), Size = UDim2.fromOffset(500, 26), Text = "", TextColor3 = DIM, TextSize = 18, ZIndex = 6 }, gui)

	messages = new("Frame", { Name = "Messages", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.8), Size = UDim2.fromScale(0.62, 0.3), BackgroundTransparency = 1, ZIndex = 6 }, gui)
	new("UIListLayout", { VerticalAlignment = Enum.VerticalAlignment.Bottom, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, messages)

	bigTitle = label({ Name = "BigTitle", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromScale(0.9, 0.2), Font = Enum.Font.Creepster, TextScaled = true, Text = "", TextTransparency = 1, TextStrokeTransparency = 1, ZIndex = 11 }, gui)
	bigSub = label({ Name = "BigSub", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.54), Size = UDim2.fromScale(0.8, 0.12), TextWrapped = true, TextSize = 24, Text = "", TextTransparency = 1, TextStrokeTransparency = 1, TextColor3 = DIM, ZIndex = 11 }, gui)

	fadeFrame = new("Frame", { Name = "Fade", Size = UDim2.fromScale(1, 1), BackgroundColor3 = BLACK, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 9 }, gui)
	whiteFrame = new("Frame", { Name = "White", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 10 }, gui)
	flashFrame = new("Frame", { Name = "Flash", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 10 }, gui)

	if RunService:IsStudio() and not Audio.isConfigured() then
		label({ Text = "Audio IDs not set: see README (ReplicatedStorage.Shared.SoundIds)", Position = UDim2.fromOffset(12, 8), Size = UDim2.fromOffset(520, 20), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 14, TextColor3 = Color3.fromRGB(150, 150, 150), ZIndex = 12 }, gui)
	end

	local function refreshKeys()
		local found = (GameState:GetAttribute("KeysFound") :: number?) or 0
		for i, box in keyBoxes do
			box.BackgroundTransparency = if i <= found then 0.1 else 1
		end
	end
	local function refreshCode()
		local mask = (GameState:GetAttribute("CodeMask") :: string?) or "____"
		codeLabel.Text = table.concat(string.split(mask, ""), " ")
	end
	GameState:GetAttributeChangedSignal("KeysFound"):Connect(refreshKeys)
	GameState:GetAttributeChangedSignal("CodeMask"):Connect(refreshCode)
	refreshKeys()
	refreshCode()

	Hud.setHudVisible(false)
	RunService.RenderStepped:Connect(Hud._update)
end

function Hud._update(dt: number)
	local t = os.clock()

	-- grain flicker + dust
	grain.BackgroundTransparency = 0.955 + math.random() * 0.03 - fearLevel * 0.02
	for i, s in specks do
		if math.random() < 0.5 then
			s.Position = UDim2.fromScale(math.random(), math.random())
			s.BackgroundColor3 = if i % 3 == 0 then BLACK else Color3.new(1, 1, 1)
			s.BackgroundTransparency = 0.55 + math.random() * 0.4
			s.Size = UDim2.fromOffset(math.random(1, 3), math.random(1, 3))
		end
	end

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
end

function Hud.setHudVisible(visible: boolean)
	info.Visible = visible
	batteryFrame.Visible = visible
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
		seg.BackgroundTransparency = if i <= lit then (if fraction < 0.2 then 0.4 + math.random() * 0.3 else 0.15) else 0.85
	end
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
	Hud.setHint(if on then "[E]  leave hiding spot" else "")
end

function Hud.setHint(text: string)
	hint.Text = text
end

function Hud.message(text: string, style: string?)
	local isNote = style == "note"
	local color = if style == "danger" then Color3.fromRGB(240, 240, 240) elseif style == "key" then Color3.fromRGB(225, 225, 215) else TEXT
	local line = label({
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		Text = text,
		TextSize = if style == "danger" then 26 elseif isNote then 22 else 21,
		TextColor3 = color,
		TextStrokeTransparency = 0.35,
		MaxVisibleGraphemes = 0,
		LayoutOrder = math.floor(os.clock() * 100),
		ZIndex = 6,
	}, messages)
	if isNote then
		line.BackgroundTransparency = 0.25
		line.BackgroundColor3 = Color3.fromRGB(14, 14, 14)
		new("UIPadding", { PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12), PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18) }, line)
	end
	local lifetime = (if isNote then 7 else 3.5) + #text * (if isNote then 0.045 else 0.03)
	task.spawn(function()
		local count = utf8.len(text) or #text
		for i = 1, count do
			if not line.Parent then
				return
			end
			line.MaxVisibleGraphemes = i
			if i % 2 == 0 then
				task.wait()
			end
		end
		line.MaxVisibleGraphemes = -1
		task.wait(lifetime)
		if line.Parent then
			local tween = TweenService:Create(line, TweenInfo.new(1.2), { TextTransparency = 1, TextStrokeTransparency = 1, BackgroundTransparency = 1 })
			tween:Play()
			tween.Completed:Wait()
			line:Destroy()
		end
	end)
	if style == "danger" then
		Hud.glitch(0.6, 0.4)
	end
	-- keep at most 4 lines
	local lines = {}
	for _, c in messages:GetChildren() do
		if c:IsA("TextLabel") then
			table.insert(lines, c)
		end
	end
	table.sort(lines, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for i = 1, #lines - 4 do
		lines[i]:Destroy()
	end
end

function Hud.showBig(title: string, sub: string?, font: Enum.Font?)
	bigTitle.Text = title
	bigTitle.Font = font or Enum.Font.Creepster
	bigSub.Text = sub or ""
	TweenService:Create(bigTitle, TweenInfo.new(0.6), { TextTransparency = 0 }):Play()
	TweenService:Create(bigSub, TweenInfo.new(1.2), { TextTransparency = 0 }):Play()
end

function Hud.setBigColor(color: Color3)
	bigTitle.TextColor3 = color
	bigSub.TextColor3 = color
end

function Hud.hideBig(instant: boolean?)
	if instant then
		bigTitle.TextTransparency = 1
		bigSub.TextTransparency = 1
	else
		TweenService:Create(bigTitle, TweenInfo.new(0.8), { TextTransparency = 1 }):Play()
		TweenService:Create(bigSub, TweenInfo.new(0.8), { TextTransparency = 1 }):Play()
	end
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
