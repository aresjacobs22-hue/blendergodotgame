--!strict
-- The main menu (all five nights, each with a live preview of its monster), the
-- countdown before a night, and the results screen after one.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Audio = require(Shared:WaitForChild("Audio"))
local Monsters = require(Shared:WaitForChild("Monsters"))
local Nights = require(Shared:WaitForChild("Nights"))
local ClientState = require(script.Parent.ClientState)
local Endings = require(script.Parent.Endings)
local Spectate = require(script.Parent.Spectate)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local GameState = ReplicatedStorage:WaitForChild("GameState")
local player = Players.LocalPlayer

local Menu = {}

local TEXT = Color3.fromRGB(215, 215, 210)
local DIM = Color3.fromRGB(125, 125, 120)
local FAINT = Color3.fromRGB(70, 70, 68)
local BLACK = Color3.new(0, 0, 0)
local FONT = Enum.Font.SpecialElite

local OBJECTIVE_TAGS: { [string]: string } = {
	survive = "SURVIVE TILL 6 AM",
	keys = "4 KEYS + CODE",
	power = "3 GENERATORS",
	collect = "6 PHOTOGRAPHS",
	hearts = "3 HEARTS",
}

local GENERAL_TIPS = {
	"It hears running. It barely hears walking. It can't hear you crouch.",
	"Your flashlight lets you see. Usually it also lets IT see you.",
	"If it watched you climb into a locker, the locker won't save you.",
	"Loops in the maze can save your life. Dead ends won't.",
	"When the lights start flickering, it's close.",
	"Throw a bottle (G) and it goes to look. Blind things fall for it every time.",
	"In a locker, hold your breath (SPACE) while it's right outside the door.",
	"A phone is ringing: answer it and a voice tells you where it is. Ignore it and IT answers.",
}

local gui: ScreenGui
local main: Frame
local overlay: Frame
local overlayTitle: TextLabel
local overlaySub: TextLabel
local howTo: Frame
local settings: Frame
local banner: TextLabel
local viewport: ViewportFrame
local viewCamera: Camera
local details: { [string]: TextLabel } = {}
local playButton: TextButton
local playStroke: UIStroke
local cards: { { button: TextButton, stroke: UIStroke, status: TextLabel, shade: Frame } } = {}
local previews: { [string]: Monsters.Rig } = {}
local shown: Monsters.Rig? = nil
local selected = 1
local music: Sound? = nil
local lastResult: { result: string, survivors: { string }, seconds: number, night: number }? = nil
local highestAtStart = 1
local brightness = 0
local volume = 1
local settingsLabels: { [string]: TextLabel } = {}

local function make<T>(className: string, props: { [string]: any }, parent: Instance?): T
	local inst = Instance.new(className :: any)
	for k, v in props do
		(inst :: any)[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return (inst :: any) :: T
end

local function text(parent: Instance, props: { [string]: any }): TextLabel
	local defaults: { [string]: any } = {
		BackgroundTransparency = 1,
		Font = FONT,
		TextColor3 = TEXT,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
	}
	for k, v in props do
		defaults[k] = v
	end
	return make("TextLabel", defaults, parent)
end

local function button(parent: Instance, label: string, props: { [string]: any }): (TextButton, UIStroke)
	local defaults: { [string]: any } = {
		BackgroundColor3 = Color3.fromRGB(16, 16, 16),
		AutoButtonColor = true,
		Font = FONT,
		TextColor3 = TEXT,
		TextSize = 24,
		Text = label,
	}
	for k, v in props do
		defaults[k] = v
	end
	local b: TextButton = make("TextButton", defaults, parent)
	local stroke: UIStroke = make("UIStroke", { Color = TEXT, Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Transparency = 0.3 }, b)
	b.MouseEnter:Connect(function()
		Audio.play("MenuHover", nil, 0.4)
	end)
	return b, stroke
end

local function highest(): number
	local value = player:GetAttribute("HighestNight")
	return if typeof(value) == "number" then value else 1
end

local function unlocked(n: number): boolean
	return n <= highest()
end

local function cleared(n: number): boolean
	return n < highest()
end

local function fullscreen(name: string, parent: Instance): Frame
	return make("Frame", { Name = name, Size = UDim2.fromScale(1, 1), BackgroundColor3 = BLACK, BorderSizePixel = 0 }, parent)
end

-- Monster preview ---------------------------------------------------------------

-- statue night swaps between its two looks (each round picks one of them)
local statueLook = 1
local nextStatueSwap = 0
local previewNight: Nights.Night? = nil

local function previewFor(night: Nights.Night): Monsters.Rig
	local variant = if night.monsterKind == "Statue" then Monsters.STATUE_VARIANTS[statueLook] else nil
	local key = night.monsterKind .. (variant or "")
	local rig = previews[key]
	if rig then
		return rig
	end
	local built = Monsters.build(night.monsterKind, { preview = true, variant = variant })
	if night.monsterKind == "Statue" then
		Monsters.applyStatuePose(built, 4, nil)
		Monsters.solve(built)
	end
	previews[key] = built
	return built
end

local function showPreview(night: Nights.Night)
	if shown then
		shown.model.Parent = nil
	end
	previewNight = night
	nextStatueSwap = os.clock() + 3.5
	local rig = previewFor(night)
	rig.model.Parent = viewport
	shown = rig
	viewport.LightColor = night.accent
	viewport.Ambient = night.accent:Lerp(BLACK, 0.75)
	local height = rig.rootHeight * 2.1
	viewCamera.CFrame = CFrame.lookAt(Vector3.new(0, height * 0.55, height * 1.25), Vector3.new(0, height * 0.45, 0))
end

-- Selecting a night -------------------------------------------------------------

local function select(n: number)
	selected = n
	local night = Nights.get(n)
	local open = unlocked(n)
	details.Number.Text = string.format("NIGHT %d   ·   %s", n, string.upper(night.vibe))
	details.Number.TextColor3 = night.accent
	details.Name.Text = night.name
	details.Place.Text = night.place
	details.Objective.Text = "OBJECTIVE    " .. night.objectiveText
	details.Monster.Text = night.monsterName .. "\n" .. night.monsterBlurb
	details.Tips.Text = "· " .. table.concat(night.tips, "\n· ")
	if open then
		playButton.Text = if cleared(n) then string.format("PLAY NIGHT %d AGAIN", n) else string.format("PLAY NIGHT %d", n)
		playButton.TextColor3 = TEXT
		playStroke.Color = night.accent
	else
		playButton.Text = string.format("LOCKED: BEAT NIGHT %d FIRST", n - 1)
		playButton.TextColor3 = DIM
		playStroke.Color = FAINT
	end
	for i, card in cards do
		card.stroke.Color = if i == n then Nights.get(i).accent else FAINT
		card.stroke.Thickness = if i == n then 3 else 1
	end
	showPreview(night)
end

local function refreshCards()
	for i, card in cards do
		local isOpen = unlocked(i)
		card.shade.Visible = not isOpen
		card.status.Text = if cleared(i) then "CLEARED" elseif isOpen then "" else "LOCKED"
		card.status.TextColor3 = if cleared(i) then Nights.get(i).accent else DIM
	end
	select(selected)
end

-- Screen state ------------------------------------------------------------------

local function formatTime(seconds: number): string
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function refresh()
	local phase = GameState:GetAttribute("Phase")
	local hasCharacter = player.Character ~= nil
	local heading: string? = nil
	local sub = ""

	if not ClientState.started then
		main.Visible = true
		overlay.Visible = false
		if phase == "Playing" or phase == "Intermission" then
			banner.Text = string.format("NIGHT %s  ·  %s  IS UNDERWAY. PRESS PLAY TO JOIN.", tostring(GameState:GetAttribute("Night") or ""), tostring(GameState:GetAttribute("NightName") or ""))
		else
			banner.Text = ""
		end
	else
		main.Visible = false
		if ClientState.jumpscaring then
			heading = nil
		elseif phase == "Results" and lastResult then
			local r = lastResult
			local night = Nights.get(r.night)
			if ClientState.roundStatus == "escaped" then
				heading = if night.objective == "survive" then "YOU SURVIVED" elseif night.index == Nights.count then "THE COLOR IS BACK" else "YOU MADE IT"
			elseif r.result == "Escaped" then
				heading = "THEY MADE IT"
			else
				heading = "NOBODY MADE IT"
			end
			sub = night.name .. "   ·   " .. formatTime(r.seconds)
			if #r.survivors > 0 then
				sub ..= "\nSurvivors: " .. table.concat(r.survivors, ", ")
			end
			if highest() > highestAtStart and highest() <= Nights.count then
				sub ..= string.format("\n\nNIGHT %d UNLOCKED: %s", highest(), Nights.get(highest()).name)
			elseif r.result == "Escaped" and night.index == Nights.count then
				sub ..= "\n\nYou beat every night. Thank you for playing ACHROMA."
			end
		elseif phase == "Intermission" and not hasCharacter then
			local n = GameState:GetAttribute("Night")
			local night = Nights.get(if typeof(n) == "number" then n else selected)
			heading = string.format("NIGHT %d", night.index)
			local countdown = GameState:GetAttribute("Countdown")
			sub = night.name .. "\n" .. night.objectiveText
			if typeof(countdown) == "number" then
				sub ..= string.format("\n\nbegins in %d", countdown)
			end
			local readyCount = GameState:GetAttribute("ReadyCount")
			if typeof(readyCount) == "number" and readyCount > 1 then
				sub ..= string.format("   ·   %d players", readyCount)
			end
		elseif (phase == "Lobby" or phase == "Playing") and not hasCharacter and not Spectate.isActive() then
			heading = "..."
			sub = if phase == "Playing" then "Waiting for the others to make it out. Or not." else "Waiting..."
		end
		overlay.Visible = heading ~= nil
		if heading then
			overlayTitle.Text = heading
			overlaySub.Text = sub
		end
	end

	if music then
		local wanted = if main.Visible or overlay.Visible then 0.4 else 0
		TweenService:Create(music, TweenInfo.new(1.5), { Volume = wanted }):Play()
	end
end

local function play()
	if not unlocked(selected) then
		Audio.play("KeypadError", nil, 0.5)
		return
	end
	Audio.play("MenuSelect", nil, 0.8)
	ClientState.started = true
	highestAtStart = highest()
	Remotes.Ready:FireServer(selected)
	refresh()
end

-- Settings ----------------------------------------------------------------------

local function applySettings()
	ClientState.brightness = brightness
	local group = SoundService:FindFirstChild("AchromaMaster")
	if group and group:IsA("SoundGroup") then
		group.Volume = volume
	end
	settingsLabels.Brightness.Text = string.format("%+d", math.floor(brightness * 100 + 0.5))
	settingsLabels.Volume.Text = string.format("%d%%", math.floor(volume * 100 + 0.5))
end

local function settingRow(parent: Instance, y: number, name: string, onChange: (number) -> ())
	text(parent, { Text = string.upper(name), Position = UDim2.new(0, 30, 0, y), Size = UDim2.new(0, 200, 0, 34), TextSize = 24, TextYAlignment = Enum.TextYAlignment.Center })
	local minus = button(parent, "-", { Position = UDim2.new(0, 250, 0, y), Size = UDim2.fromOffset(44, 34) })
	settingsLabels[name] = text(parent, { Position = UDim2.new(0, 300, 0, y), Size = UDim2.fromOffset(90, 34), TextSize = 24, TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center })
	local plus = button(parent, "+", { Position = UDim2.new(0, 396, 0, y), Size = UDim2.fromOffset(44, 34) })
	minus.Activated:Connect(function()
		onChange(-1)
		applySettings()
	end)
	plus.Activated:Connect(function()
		onChange(1)
		applySettings()
	end)
end

-- Build -------------------------------------------------------------------------

function Menu.init()
	gui = make("ScreenGui", { Name = "AchromaMenu", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 20, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, player:WaitForChild("PlayerGui"))

	main = fullscreen("Main", gui)
	-- keeps the mouse free while the menu is up
	make("TextButton", { Name = "MouseCatcher", Modal = true, Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 0 }, main)

	viewport = make("ViewportFrame", { Name = "Preview", Position = UDim2.fromScale(0.42, 0), Size = UDim2.fromScale(0.58, 0.72), BackgroundTransparency = 1, LightDirection = Vector3.new(-0.6, -1, -0.4) }, main)
	viewCamera = make("Camera", { FieldOfView = 40 }, viewport)
	viewport.CurrentCamera = viewCamera
	local fadeIn: Frame = make("Frame", { Position = UDim2.fromScale(0.42, 0), Size = UDim2.fromScale(0.25, 0.72), BackgroundColor3 = BLACK, BorderSizePixel = 0 }, main)
	make("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }) }, fadeIn)

	text(main, { Name = "Logo", Text = "ACHROMA", Font = Enum.Font.Creepster, TextScaled = true, Position = UDim2.fromScale(0.05, 0.04), Size = UDim2.fromScale(0.42, 0.13) })
	text(main, { Text = "five nights. five monsters. no color.", TextColor3 = DIM, Position = UDim2.fromScale(0.05, 0.165), Size = UDim2.fromScale(0.42, 0.04), TextSize = 20 })

	local panel: Frame = make("Frame", { Name = "Details", BackgroundTransparency = 1, Position = UDim2.fromScale(0.05, 0.23), Size = UDim2.fromScale(0.4, 0.46) }, main)
	details.Number = text(panel, { Text = "", TextSize = 20, Size = UDim2.new(1, 0, 0, 24) })
	details.Name = text(panel, { Text = "", Font = Enum.Font.Creepster, TextSize = 54, Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 0, 58) })
	details.Place = text(panel, { Text = "", TextColor3 = DIM, TextSize = 18, Position = UDim2.fromOffset(0, 86), Size = UDim2.new(1, 0, 0, 22) })
	details.Objective = text(panel, { Text = "", TextSize = 21, Position = UDim2.fromOffset(0, 118), Size = UDim2.new(1, 0, 0, 26) })
	details.Monster = text(panel, { Text = "", TextColor3 = DIM, TextSize = 18, Position = UDim2.fromOffset(0, 152), Size = UDim2.new(1, 0, 0, 64) })
	details.Tips = text(panel, { Text = "", TextColor3 = FAINT:Lerp(TEXT, 0.4), TextSize = 16, Position = UDim2.fromOffset(0, 222), Size = UDim2.new(1, 0, 0, 72) })
	playButton, playStroke = button(panel, "PLAY", { Name = "Play", Position = UDim2.new(0, 0, 1, -54), Size = UDim2.new(0.75, 0, 0, 54), TextSize = 28 })
	playButton.Activated:Connect(play)

	-- the five nights
	local row: Frame = make("Frame", { Name = "Nights", BackgroundTransparency = 1, Position = UDim2.fromScale(0.05, 0.74), Size = UDim2.fromScale(0.9, 0.21) }, main)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0.012, 0), SortOrder = Enum.SortOrder.LayoutOrder }, row)
	for _, night in Nights.list do
		local card: TextButton = make("TextButton", { Name = "Night" .. night.index, LayoutOrder = night.index, Text = "", AutoButtonColor = true, BackgroundColor3 = Color3.fromRGB(14, 14, 14), Size = UDim2.fromScale(0.19, 1) }, row)
		local stroke: UIStroke = make("UIStroke", { Color = FAINT, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, card)
		make("Frame", { Size = UDim2.new(1, 0, 0, 4), BackgroundColor3 = night.accent, BorderSizePixel = 0 }, card)
		text(card, { Text = "NIGHT " .. night.index, TextColor3 = night.accent, TextSize = 16, Position = UDim2.fromOffset(12, 12), Size = UDim2.new(1, -24, 0, 20) })
		text(card, { Text = night.name, Font = Enum.Font.Creepster, TextScaled = true, Position = UDim2.new(0, 12, 0, 34), Size = UDim2.new(1, -24, 0.32, 0) })
		text(card, { Text = string.upper(night.vibe), TextColor3 = DIM, TextSize = 15, Position = UDim2.new(0, 12, 0.6, 0), Size = UDim2.new(1, -24, 0, 18) })
		text(card, { Text = OBJECTIVE_TAGS[night.objective] or "", TextSize = 15, Position = UDim2.new(0, 12, 0.6, 20), Size = UDim2.new(1, -24, 0, 18) })
		local shade: Frame = make("Frame", { Name = "Locked", Size = UDim2.fromScale(1, 1), BackgroundColor3 = BLACK, BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = 3 }, card)
		local status = text(card, { Name = "Status", Text = "", TextSize = 16, Position = UDim2.new(0, 12, 1, -26), Size = UDim2.new(1, -24, 0, 20), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 4 })
		card.MouseEnter:Connect(function()
			Audio.play("MenuHover", nil, 0.4)
		end)
		card.Activated:Connect(function()
			Audio.play("MenuHover", nil, 0.7, 0.8)
			select(night.index)
		end)
		table.insert(cards, { button = card, stroke = stroke, status = status, shade = shade })
	end

	local helpButton = button(main, "HOW TO PLAY", { Position = UDim2.new(1, -460, 0, 30), Size = UDim2.fromOffset(200, 40), TextSize = 20 })
	local settingsButton = button(main, "SETTINGS", { Position = UDim2.new(1, -240, 0, 30), Size = UDim2.fromOffset(200, 40), TextSize = 20 })
	banner = text(main, { Text = "", TextSize = 18, TextColor3 = TEXT, Position = UDim2.new(0.05, 0, 0.7, 0), Size = UDim2.new(0.9, 0, 0, 24), TextXAlignment = Enum.TextXAlignment.Center })

	-- How to play
	howTo = make("Frame", { Name = "HowTo", Visible = false, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(760, 600), BackgroundColor3 = Color3.fromRGB(10, 10, 10), ZIndex = 10 }, gui)
	make("UIStroke", { Color = DIM, Thickness = 1.5 }, howTo)
	text(howTo, { Text = "HOW TO PLAY", Font = Enum.Font.Creepster, TextSize = 46, Position = UDim2.fromOffset(30, 20), Size = UDim2.new(1, -60, 0, 50), ZIndex = 11 })
	text(howTo, {
		ZIndex = 11,
		TextSize = 17,
		Position = UDim2.fromOffset(30, 84),
		Size = UDim2.new(1, -60, 1, -150),
		Text = "Every night has its own place, its own monster and its own way out. Beat a night to unlock the next.\n\n"
			.. "WASD  move         SHIFT  run         C  crouch (silent)         G  throw a bottle\n"
			.. "F  flashlight        E  interact / hide / leave         SPACE  hold your breath (in a locker)\n\n"
			.. "Every night rolls a CURSE (dead lights, moving walls, fog, phantoms...) and things go wrong while you play: "
			.. "the power fails, doors slam, phones ring. When the way out opens, it gets FURIOUS.\n\n"
			.. "· " .. table.concat(GENERAL_TIPS, "\n· "),
	})
	local closeHelp = button(howTo, "CLOSE", { Position = UDim2.new(1, -170, 1, -60), Size = UDim2.fromOffset(140, 40), ZIndex = 11 })
	closeHelp.Activated:Connect(function()
		howTo.Visible = false
	end)
	helpButton.Activated:Connect(function()
		settings.Visible = false
		howTo.Visible = not howTo.Visible
	end)

	-- Settings
	settings = make("Frame", { Name = "Settings", Visible = false, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(480, 260), BackgroundColor3 = Color3.fromRGB(10, 10, 10), ZIndex = 10 }, gui)
	make("UIStroke", { Color = DIM, Thickness = 1.5 }, settings)
	text(settings, { Text = "SETTINGS", Font = Enum.Font.Creepster, TextSize = 44, Position = UDim2.fromOffset(30, 16), Size = UDim2.new(1, -60, 0, 50), ZIndex = 11 })
	settingRow(settings, 90, "Brightness", function(step: number)
		brightness = math.clamp(brightness + step * 0.03, -0.09, 0.21)
	end)
	settingRow(settings, 140, "Volume", function(step: number)
		volume = math.clamp(volume + step * 0.1, 0, 1.5)
	end)
	for _, d in settings:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = 11
		end
	end
	local closeSettings = button(settings, "CLOSE", { Position = UDim2.new(1, -170, 1, -56), Size = UDim2.fromOffset(140, 40), ZIndex = 11 })
	closeSettings.Activated:Connect(function()
		settings.Visible = false
	end)
	settingsButton.Activated:Connect(function()
		howTo.Visible = false
		settings.Visible = not settings.Visible
	end)
	applySettings()

	-- Countdown / results overlay
	overlay = fullscreen("Overlay", gui)
	overlay.Visible = false
	overlayTitle = text(overlay, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.36), Size = UDim2.fromScale(0.85, 0.16), Font = Enum.Font.Creepster, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center })
	overlaySub = text(overlay, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.47), Size = UDim2.fromScale(0.75, 0.4), TextColor3 = DIM, TextSize = 24, TextXAlignment = Enum.TextXAlignment.Center })

	music = Audio.track("MusicBox", nil, 0.4)
	if music then
		music:Play()
	end

	selected = math.min(highest(), Nights.count)
	refreshCards()

	player:GetAttributeChangedSignal("HighestNight"):Connect(function()
		if not ClientState.started then
			selected = math.min(highest(), Nights.count)
		end
		refreshCards()
		refresh()
	end)
	GameState:GetAttributeChangedSignal("Phase"):Connect(function()
		local phase = GameState:GetAttribute("Phase")
		if phase == "Lobby" and ClientState.started and player.Character == nil then
			-- back to the menu, with the next night ready to go
			ClientState.started = false
			ClientState.roundStatus = "none"
			selected = math.min(highest(), Nights.count)
			refreshCards()
		end
		refresh()
	end)
	for _, attr in { "Countdown", "Night", "NightName", "ReadyCount" } do
		GameState:GetAttributeChangedSignal(attr):Connect(refresh)
	end
	Remotes.RoundResult.OnClientEvent:Connect(function(result: string, survivors: { string }, seconds: number, night: number)
		lastResult = { result = result, survivors = survivors, seconds = seconds, night = night }
		refresh()
	end)
	player.CharacterAdded:Connect(refresh)
	player.CharacterRemoving:Connect(function()
		task.defer(refresh)
	end)
	Endings.Changed:Connect(refresh)

	-- the logo flickers like a dying bulb; the preview monster slowly turns
	local accum = 0
	RunService.RenderStepped:Connect(function(dt: number)
		if main.Visible then
			local logo = main:FindFirstChild("Logo")
			if logo and logo:IsA("TextLabel") then
				logo.TextTransparency = if math.random() < 0.04 then 0.2 + math.random() * 0.6 else 0
			end
			local pn = previewNight
			if pn and pn.monsterKind == "Statue" and os.clock() >= nextStatueSwap then
				statueLook = statueLook % #Monsters.STATUE_VARIANTS + 1
				showPreview(pn)
			end
			local rig = shown
			if rig then
				rig.model:PivotTo(CFrame.Angles(0, os.clock() * 0.35, 0) * CFrame.new(0, rig.rootHeight, 0))
			end
			viewport.ImageTransparency = if math.random() < 0.03 then 0.5 else 0
		end
		accum += dt
		if accum > 0.5 then
			accum = 0
			if ClientState.started and player.Character == nil then
				refresh()
			end
		end
	end)
	refresh()
end

return Menu
