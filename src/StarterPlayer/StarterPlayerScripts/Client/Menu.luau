--!strict
-- Everything between you and the dark that isn't the HUD:
--   * the choice at a door: step into an empty square in the lobby and the screen dims
--     to NIGHT 1..5 (the ones you've reached) and 1 2 3 4 (how many of you). Pick a
--     number and it's decided. A small ring in the corner opens brightness and volume.
--   * black, with the night's number, while you're being sent through (that's also the
--     teleport's loading screen) and black between a night and the lobby.
-- The music box plays in the lobby and in the dark.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TeleportService = game:GetService("TeleportService")
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
local MAX_PLAYERS = 4

local gui: ScreenGui
local choice: TextButton -- the dimmed screen at a door (a button so it can be Modal)
local nightEntries: { TextButton } = {}
local countEntries: { TextButton } = {}
local settings: Frame
local overlay: Frame
local overlayTitle: TextLabel
local music: Sound? = nil
local pad = 0 -- which door we're choosing at
local highest = 1 -- highest night we may pick
local picked = 1 -- the night that's selected
local launching: number? = nil -- going through, to this night
local brightness = 0
local volume = 1
local levelBars: { [string]: { Frame } } = {}

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

local function where(): string
	local w = player:GetAttribute("Where")
	return if typeof(w) == "string" then w else ""
end

-- Screen state ------------------------------------------------------------------

local function refresh()
	local w = where()
	-- black whenever you have no body (the endings draw their own screens), or you're
	-- on your way through a door
	local dark = launching ~= nil or (w == "between" and player.Character == nil and not ClientState.jumpscaring and not Spectate.isActive())
	overlay.Visible = dark
	-- the night's number: on the way through, and in a night server waiting for the others
	local n = launching
	local waitingNight = GameState:GetAttribute("Night")
	if not n and GameState:GetAttribute("Phase") == "Waiting" and typeof(waitingNight) == "number" then
		n = waitingNight
	end
	local title = if n then Hud.spaced(string.format("NIGHT %d", n)) else ""
	if title ~= overlayTitle.Text then
		overlayTitle.Text = title
		overlayTitle.TextTransparency = 1
		TweenService:Create(overlayTitle, TweenInfo.new(2.2, Enum.EasingStyle.Sine), { TextTransparency = 0.05 }):Play()
	end
	if music then
		local wanted = if dark or w == "lobby" then 0.3 else 0
		TweenService:Create(music, TweenInfo.new(1.5), { Volume = wanted }):Play()
	end
end

local function closeChoice()
	choice.Visible = false
	settings.Visible = false
	ClientState.choosing = false
end

local function selectNight(n: number)
	picked = n
	for i, entry in nightEntries do
		entry.TextTransparency = if i > highest then 0.92 elseif i == picked then 0.05 else 0.6
	end
end

local function openChoice(index: number, upTo: number)
	pad = index
	highest = math.clamp(upTo, 1, Nights.count)
	selectNight(highest)
	choice.Visible = true
	ClientState.choosing = true
	Audio.play("MenuHover", nil, 0.4, 0.7)
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

	-- the choice at a door: Modal frees the mouse while it's up
	choice = make("TextButton", { Name = "Choice", Visible = false, Modal = true, AutoButtonColor = false, Text = "", Size = UDim2.fromScale(1, 1), BackgroundColor3 = BLACK, BackgroundTransparency = 0.3 }, gui)
	local column: Frame = make("Frame", { Name = "Nights", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromOffset(420, Nights.count * 54) }, choice)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }, column)
	for _, night in Nights.list do
		local n = night.index
		local entry: TextButton = make("TextButton", { Name = "Night" .. n, LayoutOrder = n, Text = Hud.spaced(string.format("NIGHT %d", n)), Font = FONT, TextSize = 28, TextColor3 = PALE, BackgroundTransparency = 1, AutoButtonColor = false, Size = UDim2.new(1, 0, 0, 40) }, column)
		entry.MouseEnter:Connect(function()
			if n <= highest then
				Audio.play("MenuHover", nil, 0.3, 0.9)
			end
		end)
		entry.Activated:Connect(function()
			if n <= highest then
				selectNight(n)
				Audio.play("MenuHover", nil, 0.5, 0.8)
			end
		end)
		table.insert(nightEntries, entry)
	end
	-- how many of you: picking one decides it
	local row: Frame = make("Frame", { Name = "Players", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.42, Nights.count * 27 + 40), Size = UDim2.fromOffset(320, 50) }, choice)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 34), SortOrder = Enum.SortOrder.LayoutOrder }, row)
	for n = 1, MAX_PLAYERS do
		local b: TextButton = make("TextButton", { Name = "Players" .. n, LayoutOrder = n, Text = tostring(n), Font = FONT, TextSize = 34, TextColor3 = PALE, TextTransparency = 0.35, BackgroundTransparency = 1, AutoButtonColor = false, Size = UDim2.fromOffset(40, 50) }, row)
		b.MouseEnter:Connect(function()
			b.TextTransparency = 0
			Audio.play("MenuHover", nil, 0.3, 1.1)
		end)
		b.MouseLeave:Connect(function()
			b.TextTransparency = 0.35
		end)
		b.Activated:Connect(function()
			Audio.play("MenuSelect", nil, 0.7, 0.85)
			Remotes.Lobby:FireServer("choose", pad, picked, n)
			closeChoice()
		end)
		table.insert(countEntries, b)
	end
	-- step back from the door: a small cross in the corner
	local back: TextButton = make("TextButton", { Name = "Back", Text = "×", Font = FONT, TextSize = 30, TextColor3 = PALE, TextTransparency = 0.5, BackgroundTransparency = 1, Position = UDim2.fromOffset(24, 18), Size = UDim2.fromOffset(32, 32) }, choice)
	back.Activated:Connect(function()
		Remotes.Lobby:FireServer("cancel", pad)
		closeChoice()
	end)

	-- settings: a small ring in the corner of the choice screen
	local ring: TextButton = make("TextButton", { Name = "SettingsButton", Text = "", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -28, 1, -28), Size = UDim2.fromOffset(16, 16), BackgroundTransparency = 1, AutoButtonColor = false }, choice)
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

	-- the dark between places, with the night's number on the way in
	overlay = make("Frame", { Name = "Overlay", Visible = false, Size = UDim2.fromScale(1, 1), BackgroundColor3 = BLACK, BorderSizePixel = 0 }, gui)
	overlayTitle = make("TextLabel", { Name = "Title", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.48), Size = UDim2.new(0.9, 0, 0, 60), BackgroundTransparency = 1, Font = FONT, TextSize = 40, TextColor3 = PALE, Text = "" }, overlay)

	music = Audio.track("MusicBox", nil, 0.3)
	if music then
		music:Play()
	end

	Remotes.Lobby.OnClientEvent:Connect(function(action: string, a: any, b: any)
		if action == "choose" and typeof(a) == "number" and typeof(b) == "number" then
			openChoice(a, b)
		elseif action == "close" then
			closeChoice()
		elseif action == "launch" and typeof(a) == "number" then
			closeChoice()
			launching = a
			refresh()
			-- the same black screen while the teleport loads
			pcall(function()
				local loading: ScreenGui = make("ScreenGui", { Name = "AchromaTeleport", IgnoreGuiInset = true, DisplayOrder = 100 })
				local copy = overlay:Clone()
				copy.Visible = true
				copy.Parent = loading
				local t = copy:FindFirstChild("Title")
				if t and t:IsA("TextLabel") then
					t.TextTransparency = 0.05
				end
				TeleportService:SetTeleportGui(loading)
			end)
		end
	end)
	player:GetAttributeChangedSignal("Where"):Connect(function()
		-- arrived somewhere (or the teleport fell through and we're back in the lobby)
		if where() ~= "between" then
			launching = nil
		end
		if where() ~= "lobby" then
			closeChoice()
		end
		refresh()
	end)
	player.CharacterAdded:Connect(refresh)
	player.CharacterRemoving:Connect(function()
		task.defer(refresh)
	end)
	Endings.Changed:Connect(refresh)

	local accum = 0
	RunService.RenderStepped:Connect(function(dt: number)
		accum += dt
		if accum > 0.5 then
			accum = 0
			refresh()
		end
	end)
	refresh()
end

return Menu
