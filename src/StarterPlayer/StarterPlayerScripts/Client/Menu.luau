--!strict
-- Title screen, "night falls in..." intermission, and the results screen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Audio = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Audio"))
local ClientState = require(script.Parent.ClientState)
local Endings = require(script.Parent.Endings)
local Spectate = require(script.Parent.Spectate)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local GameState = ReplicatedStorage:WaitForChild("GameState")
local player = Players.LocalPlayer

local Menu = {}

local TEXT = Color3.fromRGB(210, 210, 205)
local DIM = Color3.fromRGB(125, 125, 120)

local TIPS = {
	"It hears running. It barely hears walking. It can't hear you crouch.",
	"Your flashlight lets you see. It also lets IT see you.",
	"If it watched you climb into a locker, the locker won't save you.",
	"Each key's tag shows one digit of the exit code.",
	"A wrong code makes the keypad buzz. Something will come to see.",
	"Loops in the maze can save your life. Dead ends won't.",
	"When the lights start flickering, it's close.",
	"Listen for the clicking.",
}

local gui: ScreenGui
local title: Frame
local overlay: Frame
local overlayTitle: TextLabel
local overlaySub: TextLabel
local logo: TextLabel
local music: Sound? = nil
local lastResult: { result: string, survivors: { string }, seconds: number }? = nil
local tip = TIPS[1]

local function text(parent: Instance, props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.SpecialElite
	l.TextColor3 = TEXT
	l.TextSize = 22
	for k, v in props do
		(l :: any)[k] = v
	end
	l.Parent = parent
	return l
end

local function fullscreen(parent: Instance, name: string): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = Color3.new(0, 0, 0)
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

local function formatTime(seconds: number): string
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function refresh()
	if not ClientState.started then
		overlay.Visible = false
		return
	end
	local phase = GameState:GetAttribute("Phase")
	local hasCharacter = player.Character ~= nil
	local busy = ClientState.jumpscaring
	local heading: string? = nil
	local sub = ""

	if busy then
		heading = nil
	elseif phase == "Results" and lastResult then
		local r = lastResult
		if ClientState.roundStatus == "escaped" then
			heading = "YOU ESCAPED"
		elseif r.result == "Escaped" then
			heading = "THEY GOT OUT"
		else
			heading = "NOBODY ESCAPED"
		end
		sub = if #r.survivors > 0 then "Survivors: " .. table.concat(r.survivors, ", ") .. "\n" else ""
		sub ..= "Time in the dark: " .. formatTime(r.seconds)
	elseif not hasCharacter and (phase == "Intermission" or phase == "Waiting") then
		local countdown = GameState:GetAttribute("Countdown")
		heading = if phase == "Intermission" and typeof(countdown) == "number" then "NIGHT FALLS IN " .. countdown else "..."
		sub = tip
	elseif not hasCharacter and phase == "Playing" and not Spectate.isActive() then
		heading = "..."
		sub = "Waiting for the others to escape, or not."
	end

	overlay.Visible = heading ~= nil
	if heading then
		overlayTitle.Text = heading
		overlaySub.Text = sub
	end
	if music then
		local target = if heading ~= nil then 0.4 else 0
		TweenService:Create(music, TweenInfo.new(1.5), { Volume = target }):Play()
	end
end

local function start()
	if ClientState.started then
		return
	end
	ClientState.started = true
	tip = TIPS[math.random(1, #TIPS)]
	local fade = TweenService:Create(title, TweenInfo.new(1.2), { BackgroundTransparency = 1 })
	for _, d in title:GetDescendants() do
		if d:IsA("TextLabel") or d:IsA("TextButton") then
			TweenService:Create(d, TweenInfo.new(0.8), { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
		end
		if d:IsA("UIStroke") then
			TweenService:Create(d, TweenInfo.new(0.8), { Transparency = 1 }):Play()
		end
	end
	fade:Play()
	fade.Completed:Once(function()
		title.Visible = false
	end)
	Remotes.Ready:FireServer()
	refresh()
end

function Menu.init()
	gui = Instance.new("ScreenGui")
	gui.Name = "AchromaMenu"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 20
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Title screen
	title = fullscreen(gui, "Title")
	logo = text(title, {
		Name = "Logo",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromScale(0.8, 0.22),
		Font = Enum.Font.Creepster,
		Text = "ACHROMA",
		TextScaled = true,
	})
	text(title, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.43),
		Size = UDim2.fromScale(0.8, 0.05),
		Text = "You woke up. The color is gone. Something else woke up too.",
		TextColor3 = DIM,
		TextScaled = true,
	})
	local button = Instance.new("TextButton")
	button.Name = "WakeUp"
	button.Modal = true -- frees the mouse while the menu is up
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.fromScale(0.5, 0.6)
	button.Size = UDim2.fromOffset(280, 60)
	button.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
	button.AutoButtonColor = true
	button.Font = Enum.Font.SpecialElite
	button.TextSize = 30
	button.TextColor3 = TEXT
	button.Text = "WAKE UP"
	button.Parent = title
	local stroke = Instance.new("UIStroke")
	stroke.Color = TEXT
	stroke.Thickness = 1.5
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button
	button.Activated:Connect(start)

	text(title, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -30),
		Size = UDim2.new(0.9, 0, 0, 120),
		TextWrapped = true,
		TextSize = 18,
		TextColor3 = DIM,
		Text = "Find the 4 KEYS hidden in the maze. Each key's tag shows one number of the exit code.\n"
			.. "Bring them back to the exit in the hall and type the code.  Don't let it see you.\n\n"
			.. "WASD move    SHIFT run    C crouch    F flashlight    E interact / hide",
	})

	-- Intermission / results overlay
	overlay = fullscreen(gui, "Overlay")
	overlay.Visible = false
	overlayTitle = text(overlay, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromScale(0.85, 0.16),
		Font = Enum.Font.Creepster,
		TextScaled = true,
	})
	overlaySub = text(overlay, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.54),
		Size = UDim2.fromScale(0.75, 0.2),
		TextWrapped = true,
		TextColor3 = DIM,
		TextYAlignment = Enum.TextYAlignment.Top,
	})

	music = Audio.track("MusicBox", nil, 0.4)
	if music then
		music:Play()
	end

	GameState:GetAttributeChangedSignal("Phase"):Connect(function()
		local phase = GameState:GetAttribute("Phase")
		if phase == "Intermission" then
			tip = TIPS[math.random(1, #TIPS)]
			ClientState.roundStatus = "none"
		end
		refresh()
	end)
	GameState:GetAttributeChangedSignal("Countdown"):Connect(refresh)
	Remotes.RoundResult.OnClientEvent:Connect(function(result: string, survivors: { string }, seconds: number)
		lastResult = { result = result, survivors = survivors, seconds = seconds }
		refresh()
	end)
	player.CharacterAdded:Connect(refresh)
	player.CharacterRemoving:Connect(function()
		task.defer(refresh)
	end)
	Endings.Changed:Connect(refresh)

	-- the logo flickers like a dying bulb; overlay refreshes for spectate changes
	local accum = 0
	RunService.RenderStepped:Connect(function(dt: number)
		if title.Visible then
			logo.TextTransparency = if math.random() < 0.04 then 0.2 + math.random() * 0.6 else 0
			logo.Rotation = if math.random() < 0.01 then (math.random() - 0.5) * 3 else 0
		end
		accum += dt
		if accum > 0.5 then
			accum = 0
			if ClientState.started and player.Character == nil then
				refresh()
			end
		end
	end)
end

return Menu
