--!strict
-- The menu: a black screen and five lines, NIGHT 1 to NIGHT 5. Nights you haven't
-- reached are barely there. The one you're on breathes. Click one to play it. A small
-- ring in the corner opens brightness and volume. Between nights: black, and the
-- night's number.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Audio = require(Shared:WaitForChild("Audio"))
local Nights = require(Shared:WaitForChild("Nights"))
local ClientState = require(script.Parent.ClientState)
local Endings = require(script.Parent.Endings)
local Hud = require(script.Parent.Hud)
local Spectate = require(script.Parent.Spectate)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local GameState = ReplicatedStorage:WaitForChild("GameState")
local player = Players.LocalPlayer

local Menu = {}

local PALE = Color3.fromRGB(200, 200, 194)
local BLACK = Color3.new(0, 0, 0)
local FONT = Hud.TITLE_FONT

-- how visible each line is (TextTransparency)
local LOCKED = 0.92
local CLEARED = 0.55
local CURRENT = 0.12

local gui: ScreenGui
local main: Frame
local overlay: Frame
local overlayTitle: TextLabel
local settings: Frame
local ghost: TextLabel
local entries: { TextButton } = {}
local hovered: number? = nil
local revealing: { [number]: number } = {} -- newly unlocked nights fading in: n -> start time
local music: Sound? = nil
local highestAtStart = 1
local brightness = 0
local volume = 1
local levelBars: { [string]: { Frame } } = {}
local nextGhost = 0

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

-- Screen state ------------------------------------------------------------------

local function refresh()
	local phase = GameState:GetAttribute("Phase")
	local hasCharacter = player.Character ~= nil

	if not ClientState.started then
		main.Visible = true
		overlay.Visible = false
	else
		main.Visible = false
		-- black whenever you're between nights (the endings draw their own screens)
		local between = not ClientState.jumpscaring and not hasCharacter and not Spectate.isActive()
		overlay.Visible = between
		local n = GameState:GetAttribute("Night")
		local title = if between and phase == "Intermission" then Hud.spaced(string.format("NIGHT %d", if typeof(n) == "number" then n else 1)) else ""
		if title ~= overlayTitle.Text then
			overlayTitle.Text = title
			overlayTitle.TextTransparency = 1
			TweenService:Create(overlayTitle, TweenInfo.new(2.2, Enum.EasingStyle.Sine), { TextTransparency = 0.05 }):Play()
		end
	end

	if music then
		local wanted = if main.Visible or overlay.Visible then 0.35 else 0
		TweenService:Create(music, TweenInfo.new(1.5), { Volume = wanted }):Play()
	end
end

local function play(n: number)
	if not unlocked(n) then
		Audio.play("MenuHover", nil, 0.25, 0.6)
		return
	end
	Audio.play("MenuSelect", nil, 0.7, 0.85)
	ClientState.started = true
	highestAtStart = highest()
	Remotes.Ready:FireServer(n)
	refresh()
end

-- Settings ----------------------------------------------------------------------

local function applySettings()
	ClientState.brightness = brightness
	local group = SoundService:FindFirstChild("AchromaMaster")
	if group and group:IsA("SoundGroup") then
		group.Volume = volume
	end
	local function fill(name: string, k: number)
		for i, bar in levelBars[name] do
			bar.BackgroundTransparency = if i <= math.floor(k * 10 + 0.5) then 0.2 else 0.85
		end
	end
	fill("brightness", (brightness + 0.09) / 0.39)
	fill("volume", volume / 1.5)
end

-- one row: "-" [ten little bars] "+"
local function settingRow(parent: Instance, y: number, name: string, onChange: (number) -> ())
	make("TextLabel", { Text = name, BackgroundTransparency = 1, Font = FONT, TextSize = 16, TextColor3 = PALE, TextTransparency = 0.5, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(24, y), Size = UDim2.fromOffset(90, 24), ZIndex = 11 }, parent)
	local function step(text: string, x: number, dir: number)
		local b: TextButton = make("TextButton", { Text = text, BackgroundTransparency = 1, Font = FONT, TextSize = 22, TextColor3 = PALE, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(24, 24), ZIndex = 11 }, parent)
		b.Activated:Connect(function()
			onChange(dir)
			Audio.play("MenuHover", nil, 0.4)
			applySettings()
		end)
	end
	step("-", 116, -1)
	local bars = {}
	for i = 1, 10 do
		table.insert(bars, make("Frame", { BackgroundColor3 = PALE, BorderSizePixel = 0, Position = UDim2.fromOffset(146 + (i - 1) * 9, y + 6), Size = UDim2.fromOffset(5, 12), ZIndex = 11 }, parent))
	end
	levelBars[name] = bars
	step("+", 240, 1)
end

-- Build -------------------------------------------------------------------------

function Menu.init()
	gui = make("ScreenGui", { Name = "AchromaMenu", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 20, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, player:WaitForChild("PlayerGui"))

	main = fullscreen("Main", gui)
	-- keeps the mouse free while the menu is up
	make("TextButton", { Name = "MouseCatcher", Modal = true, Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 0 }, main)

	local list: Frame = make("Frame", { Name = "Nights", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(420, 6 * 56) }, main)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 14), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	for _, night in Nights.list do
		local n = night.index
		local entry: TextButton = make("TextButton", {
			Name = "Night" .. n,
			LayoutOrder = n,
			Text = Hud.spaced(string.format("NIGHT %d", n)),
			Font = FONT,
			TextSize = 30,
			TextColor3 = PALE,
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Size = UDim2.new(1, 0, 0, 42),
		}, list)
		entry.MouseEnter:Connect(function()
			if unlocked(n) then
				hovered = n
				Audio.play("MenuHover", nil, 0.3, 0.9)
			end
		end)
		entry.MouseLeave:Connect(function()
			if hovered == n then
				hovered = nil
			end
		end)
		entry.Activated:Connect(function()
			play(n)
		end)
		table.insert(entries, entry)
	end
	-- sometimes, for a moment, there's one more
	ghost = make("TextLabel", { Name = "Ghost", LayoutOrder = Nights.count + 1, Text = Hud.spaced(string.format("NIGHT %d", Nights.count + 1)), Font = FONT, TextSize = 30, TextColor3 = Color3.fromRGB(150, 40, 36), TextTransparency = 1, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 42) }, list)
	nextGhost = os.clock() + 40 + math.random() * 60

	-- settings: a small ring in the corner
	local ring: TextButton = make("TextButton", { Name = "SettingsButton", Text = "", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -28, 1, -28), Size = UDim2.fromOffset(16, 16), BackgroundTransparency = 1, AutoButtonColor = false }, main)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, ring)
	local ringStroke: UIStroke = make("UIStroke", { Color = PALE, Thickness = 1.2, Transparency = 0.6, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, ring)
	ring.MouseEnter:Connect(function()
		ringStroke.Transparency = 0.1
	end)
	ring.MouseLeave:Connect(function()
		ringStroke.Transparency = 0.6
	end)

	settings = make("Frame", { Name = "Settings", Visible = false, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -56, 1, -28), Size = UDim2.fromOffset(290, 96), BackgroundColor3 = Color3.fromRGB(6, 6, 6), BorderSizePixel = 0, ZIndex = 10 }, gui)
	make("UIStroke", { Color = PALE, Thickness = 1, Transparency = 0.8 }, settings)
	settingRow(settings, 20, "brightness", function(dir: number)
		brightness = math.clamp(brightness + dir * 0.03, -0.09, 0.3)
	end)
	settingRow(settings, 54, "volume", function(dir: number)
		volume = math.clamp(volume + dir * 0.1, 0, 1.5)
	end)
	ring.Activated:Connect(function()
		settings.Visible = not settings.Visible
	end)
	applySettings()

	-- between nights: black, and the night's number
	overlay = fullscreen("Overlay", gui)
	overlay.Visible = false
	overlayTitle = make("TextLabel", { Name = "Title", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.48), Size = UDim2.new(0.9, 0, 0, 60), BackgroundTransparency = 1, Font = FONT, TextSize = 40, TextColor3 = PALE, Text = "" }, overlay)

	music = Audio.track("MusicBox", nil, 0.35)
	if music then
		music:Play()
	end

	player:GetAttributeChangedSignal("HighestNight"):Connect(refresh)
	GameState:GetAttributeChangedSignal("Phase"):Connect(function()
		local phase = GameState:GetAttribute("Phase")
		if phase == "Lobby" and ClientState.started and player.Character == nil then
			-- back to the menu. A night you just unlocked surfaces slowly out of the dark.
			ClientState.started = false
			ClientState.roundStatus = "none"
			settings.Visible = false
			local h = highest()
			if h > highestAtStart and h <= Nights.count then
				revealing[h] = os.clock() + 1
			end
		end
		refresh()
	end)
	GameState:GetAttributeChangedSignal("Night"):Connect(refresh)
	player.CharacterAdded:Connect(refresh)
	player.CharacterRemoving:Connect(function()
		task.defer(refresh)
	end)
	Endings.Changed:Connect(refresh)

	local accum = 0
	RunService.RenderStepped:Connect(function(dt: number)
		local t = os.clock()
		if main.Visible then
			local phase = GameState:GetAttribute("Phase")
			local underway = GameState:GetAttribute("Night")
			local busy = phase == "Playing" or phase == "Intermission"
			local current = math.min(highest(), Nights.count)
			for n, entry in entries do
				local k: number
				if not unlocked(n) then
					k = LOCKED
				elseif hovered == n then
					k = 0
				elseif (busy and underway == n) or (not busy and n == current and not cleared(n)) then
					k = CURRENT + 0.14 * (0.5 + 0.5 * math.sin(t * 1.3)) -- breathing
				else
					k = CLEARED
				end
				local since = revealing[n]
				if since then
					local a = math.clamp((t - since) / 4, 0, 1)
					k = LOCKED + (k - LOCKED) * a
					if a >= 1 then
						revealing[n] = nil
					end
				end
				-- now and then a line flickers like a dying bulb
				if math.random() < 0.0015 then
					k = math.min(1, k + 0.5)
				end
				entry.TextTransparency = k
			end
			if t >= nextGhost then
				nextGhost = t + 50 + math.random() * 70
				ghost.TextTransparency = 0.82
				task.delay(0.09, function()
					ghost.TextTransparency = 1
				end)
			end
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
