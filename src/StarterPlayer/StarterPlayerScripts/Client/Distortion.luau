--!strict
-- The picture is wrong, like a tape that's been copied too many times. Laid over
-- everything (the menu, the HUD, the night's title): film grain and dust, scanlines, a
-- dark band rolling slowly down the screen, lines tearing across with a red fringe,
-- scratches on the film, and red bleeding in at the edges. Every few seconds the tape
-- chokes: for a split second the picture shreds, flashes red and smears. All of it gets
-- worse the closer it is, and worst when it's furious.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Audio = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Audio"))
local ClientState = require(script.Parent.ClientState)

local GameState = ReplicatedStorage:WaitForChild("GameState")
local player = Players.LocalPlayer

local Distortion = {}

local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)
local BLEED = Color3.fromRGB(150, 12, 12)
local SCANLINES = 180

type Flicker = { frame: Frame, fringe: Frame?, untilT: number }

local gui: ScreenGui
local grain: Frame
local specks: { Frame } = {}
local roll: Frame
local rollEdge: Frame
local bleeds: { Frame } = {}
local tears: { Flicker } = {}
local scratches: { Flicker } = {}
local tint: ColorCorrectionEffect
local smear: BlurEffect
local burstUntil = 0
local nextBurst = 0

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

-- a plain overlay strip; Active = false so clicks go straight through to the menu
local function strip(props: { [string]: any }): Frame
	props.BorderSizePixel = 0
	props.Active = false
	return new("Frame", props, gui)
end

-- 0 when calm, 1 when it's on top of you
local function intensity(): number
	local k = 0.25 + ClientState.fear * 0.75
	if GameState:GetAttribute("Rage") == true then
		k += 0.3
	end
	return math.min(k, 1)
end

local function update(dt: number)
	local t = os.clock()
	local k = intensity()

	-- the tape chokes now and then (more often when it's close)
	if t >= nextBurst then
		nextBurst = t + (5 + math.random() * 11) / (0.6 + k)
		burstUntil = t + 0.1 + math.random() * 0.22
		if ClientState.roundStatus == "alive" then
			Audio.play("StaticBurst", nil, 0.12 + k * 0.2, 0.8 + math.random() * 0.4)
		end
	end
	local bursting = t < burstUntil
	tint.TintColor = if bursting and math.random() < 0.6 then Color3.fromRGB(255, 200, 200) else Color3.new(1, 1, 1)
	tint.Contrast = if bursting then 0.25 else 0
	smear.Size = if bursting then 3 + math.random() * 5 else 0
	local camera = workspace.CurrentCamera
	if camera and tint.Parent ~= camera then
		tint.Parent = camera
		smear.Parent = camera
	end

	-- grain flicker and dust
	grain.BackgroundTransparency = 0.955 + math.random() * 0.03 - k * 0.02
	for i, s in specks do
		if math.random() < 0.5 then
			s.Position = UDim2.fromScale(math.random(), math.random())
			s.BackgroundColor3 = if i % 3 == 0 then BLACK else WHITE
			s.BackgroundTransparency = 0.55 + math.random() * 0.4
			s.Size = UDim2.fromOffset(math.random(1, 3), math.random(1, 3))
		end
	end

	-- the tracking band crawls down the screen, faster when it's close
	local y = (t * (0.05 + k * 0.05)) % 1.35 - 0.2
	roll.Position = UDim2.fromScale(0, y)
	rollEdge.Position = UDim2.fromScale(0, y)
	rollEdge.BackgroundTransparency = 0.94 - (if math.random() < 0.1 then 0.1 else 0)

	-- red seeping in at the sides
	for _, b in bleeds do
		b.BackgroundTransparency = 0.88 - k * 0.22 - math.random() * 0.04 - (if bursting then 0.25 else 0)
	end

	-- tears: a band across part of the screen (bright, or a black dropout), its red ghost
	-- just below it. During a burst they're everywhere.
	for _, tear in tears do
		if t > tear.untilT or bursting then
			tear.frame.Visible = false
			if tear.fringe then
				tear.fringe.Visible = false
			end
			if math.random() < (if bursting then 0.7 else dt * (0.5 + k * 6)) then
				local height = if bursting then math.random(3, 22) else math.random(1, 6)
				local x, width = math.random() * 0.4, 0.3 + math.random() * 0.7
				local at = math.random()
				local dropout = math.random() < 0.35
				tear.frame.Position = UDim2.new(x, 0, at, 0)
				tear.frame.Size = UDim2.new(width, 0, 0, height)
				tear.frame.BackgroundColor3 = if dropout then BLACK else WHITE
				tear.frame.BackgroundTransparency = if dropout then 0.2 + math.random() * 0.4 else 0.5 + math.random() * 0.35
				tear.frame.Visible = true
				local fringe = tear.fringe
				if fringe then
					fringe.Position = UDim2.new(x, 7, at, height + 1)
					fringe.Size = UDim2.new(width, 0, 0, height)
					fringe.Visible = true
				end
				tear.untilT = t + 0.03 + math.random() * 0.1
			end
		end
	end

	-- scratches down the film
	for _, s in scratches do
		if t > s.untilT then
			s.frame.Visible = false
			if math.random() < dt * 0.6 then
				s.frame.Position = UDim2.fromScale(math.random(), 0)
				s.frame.BackgroundTransparency = 0.6 + math.random() * 0.3
				s.frame.Visible = true
				s.untilT = t + 0.05 + math.random() * 0.25
			end
		end
	end
end

function Distortion.init()
	gui = new("ScreenGui", {
		Name = "AchromaDistort",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 30, -- above the menu (20) and the HUD (5)
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, player:WaitForChild("PlayerGui"))

	grain = strip({ Name = "Grain", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 0.97 })
	for _ = 1, 40 do
		table.insert(specks, strip({ Size = UDim2.fromOffset(2, 2), BackgroundTransparency = 1 }))
	end

	local lines: Frame = strip({ Name = "Scanlines", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
	for i = 0, SCANLINES - 1 do
		new("Frame", { Position = UDim2.new(0, 0, i / SCANLINES, 0), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = BLACK, BackgroundTransparency = 0.74, BorderSizePixel = 0, Active = false }, lines)
	end

	roll = strip({ Name = "Roll", Size = UDim2.fromScale(1, 0.16), BackgroundColor3 = BLACK, BackgroundTransparency = 0.82 })
	new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.35, 0), NumberSequenceKeypoint.new(1, 1) }),
	}, roll)
	rollEdge = strip({ Name = "RollEdge", Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = WHITE, BackgroundTransparency = 0.94 })

	for _, side in { 0, 1 } do
		local b = strip({ Name = "Bleed", AnchorPoint = Vector2.new(side, 0), Position = UDim2.fromScale(side, 0), Size = UDim2.fromScale(0.08, 1), BackgroundColor3 = BLEED, BackgroundTransparency = 0.88 })
		new("UIGradient", {
			Rotation = if side == 0 then 0 else 180,
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
		}, b)
		table.insert(bleeds, b)
	end

	for _ = 1, 10 do
		local line = strip({ Name = "Tear", BackgroundColor3 = WHITE, Visible = false })
		local fringe = strip({ Name = "TearFringe", BackgroundColor3 = BLEED, BackgroundTransparency = 0.45, Visible = false })
		table.insert(tears, { frame = line, fringe = fringe, untilT = 0 })
	end
	for _ = 1, 3 do
		table.insert(scratches, { frame = strip({ Name = "Scratch", Size = UDim2.new(0, 1, 1, 0), BackgroundColor3 = Color3.fromRGB(210, 210, 205), Visible = false }), untilT = 0 })
	end

	-- the red flash and the smear of a burst
	tint = new("ColorCorrectionEffect", { Name = "AchromaDistortTint" })
	smear = new("BlurEffect", { Name = "AchromaDistortSmear", Size = 0 })
	nextBurst = os.clock() + 4

	RunService.RenderStepped:Connect(update)
end

return Distortion
