-- End-to-end: boots the real server Script and client LocalScript together in the
-- mocked engine and plays the whole game as a fake player, through the actual UI:
--   main menu -> night 1 (survive, hiding in a locker) -> night 2 unlocked
--   -> keys + on-screen keypad -> generators -> photographs -> hearts (the end)
--   -> back to night 1 to get caught by the Hollow (jumpscare).
-- Run with:  lune run tests/e2e.spec.luau
local roblox = require("@lune/roblox")
local Engine = require("./mock/engine")

local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Enum = roblox.Enum

local REMOTES = { "Ready", "Notify", "Jumpscare", "OpenKeypad", "SubmitCode", "LeaveHiding", "Flashlight", "Battery", "RoundResult", "Apparition", "Escaped", "Look" }

local failures = 0
local function check(cond: any, msg: string)
	if cond then
		print("  ok   " .. msg)
	else
		failures += 1
		print("  FAIL " .. msg)
	end
end

---------------------------------------------------------------------------
-- boot

local shared = Engine.folderFromDir("Shared", "src/ReplicatedStorage/Shared")
local server = Engine.folderFromDir("Server", "src/ServerScriptService/Server")
local client = Engine.folderFromDir("Client", "src/StarterPlayer/StarterPlayerScripts/Client")
local game, workspace = Engine.makeGame(server, shared, client, REMOTES)
local player = Engine.addPlayer(game, "Ares", 1)

Engine.onDestroy = function(model)
	if player.Character == model then
		player.CharacterRemoving:Fire(model)
	end
end

local notifications: { string } = {}
local globals = {
	game = game,
	workspace = workspace,
	Instance = Engine.Instance,
	Vector3 = roblox.Vector3,
	Vector2 = roblox.Vector2,
	CFrame = roblox.CFrame,
	Color3 = roblox.Color3,
	UDim = roblox.UDim,
	UDim2 = roblox.UDim2,
	Enum = roblox.Enum,
	NumberRange = roblox.NumberRange,
	NumberSequence = roblox.NumberSequence,
	NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
	Random = Engine.Random,
	TweenInfo = Engine.TweenInfo,
	RaycastParams = Engine.RaycastParams,
	task = Engine.makeTask(),
	os = {
		clock = function()
			return Engine.time
		end,
		time = os.time,
		date = os.date,
	},
	typeof = Engine.typeof,
	warn = function(...)
		table.insert(Engine.log, table.concat({ ... }, " "))
	end,
}
local require, runScript = Engine.makeLoader(globals)
local rs = game:GetService("ReplicatedStorage")

local SoundIds = require(rs.Shared.SoundIds)
SoundIds.SFX = 111
SoundIds.Ambience = 222
SoundIds.MusicBox = 333

local Maze = require(rs.Shared.Maze)
Engine.Maze = Maze
local generate = Maze.generate
Maze.generate = function(seed, cfg)
	local layout = generate(seed, cfg)
	Engine.layout = layout
	return layout
end
local Nights = require(rs.Shared.Nights)
local ClientState = require(client.ClientState)

rs.Remotes.Notify.OnClientEvent:Connect(function(text)
	table.insert(notifications, text)
end)

runScript(server.Main)
runScript(client.Main)

---------------------------------------------------------------------------
-- helpers

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function moveMonster(dt: number)
	local monster = workspace:FindFirstChild("Monster")
	if not monster then
		return
	end
	local root = monster.HumanoidRootPart
	local humanoid = monster.Humanoid
	local target = rawget(humanoid, "_moveTarget")
	if root.Anchored or not target then
		root.AssemblyLinearVelocity = Vector3.zero
		return
	end
	local to = flat(target - root.Position)
	if to.Magnitude < 0.05 then
		root.AssemblyLinearVelocity = Vector3.zero
		return
	end
	local step = math.min(to.Magnitude, humanoid.WalkSpeed * dt)
	local nextPos = root.Position + to.Unit * step
	monster:PivotTo(CFrame.lookAt(nextPos, nextPos + to.Unit))
	root.AssemblyLinearVelocity = to.Unit * (step / dt)
end

local function run(seconds: number, until_: (() -> boolean)?, dt: number?): boolean
	local step = dt or 1 / 30
	local t = 0
	while t < seconds do
		Engine.step(game, step)
		moveMonster(step)
		t += step
		if until_ and until_() then
			return true
		end
	end
	return false
end

local GameState = rs.GameState
local function phase()
	return GameState:GetAttribute("Phase")
end

local function placePlayer(position)
	local character = player.Character
	local cf = CFrame.new(position.X, 3, position.Z)
	character.HumanoidRootPart.CFrame = cf
	character.Head.CFrame = cf * CFrame.new(0, 1.5, 0)
end

local function press(action: string)
	local fn = Engine.actions[action]
	assert(fn, "action not bound: " .. action)
	fn(action, Enum.UserInputState.Begin, nil)
end

local function release(action: string)
	local fn = Engine.actions[action]
	if fn then
		fn(action, Enum.UserInputState.End, nil)
	end
end

local function prompts(objectText: string)
	local list = {}
	local world = workspace:FindFirstChild("World")
	if not world then
		return list
	end
	for _, d in world:GetDescendants() do
		if d.ClassName == "ProximityPrompt" and d.ObjectText == objectText and d.Enabled then
			table.insert(list, d)
		end
	end
	return list
end

local menu
local function card(n: number)
	return menu.Main.Nights["Night" .. n]
end

local function startNight(n: number)
	card(n).Activated:Fire()
	menu.Main.Details.Play.Activated:Fire()
	return run(15, function()
		return phase() == "Playing" and player.Character ~= nil
	end)
end

local function finishAndReturn(expectedTitle: string)
	local results = run(20, function()
		return phase() == "Results" and menu.Overlay.Visible
	end)
	check(results, "results screen appears")
	local title = menu.Overlay:FindFirstChildOfClass("TextLabel").Text
	check(title == expectedTitle, "results say " .. expectedTitle .. " (got " .. tostring(title) .. ")")
	local back = run(20, function()
		return phase() == "Lobby" and menu.Main.Visible
	end)
	check(back, "back on the main menu")
end

local function objectiveText(): string
	return player.PlayerGui.AchromaHud.Info.Objective.Text
end

local function progressText(): string
	return player.PlayerGui.AchromaHud.Info.Progress.Text
end

---------------------------------------------------------------------------
print("Main menu")
run(1)
menu = player.PlayerGui:FindFirstChild("AchromaMenu")
check(menu and menu.Main.Visible, "the main menu shows when you open the game")
check(phase() == "Lobby", "server waits in the lobby")
check(player:GetAttribute("HighestNight") == 1, "a new player has only night 1")
local cardCount = 0
for n = 1, 5 do
	if card(n) then
		cardCount += 1
	end
end
check(cardCount == 5, "all 5 nights are on the menu")
check(not card(1).Locked.Visible and card(2).Locked.Visible and card(5).Locked.Visible, "nights 2-5 start locked")
card(3).Activated:Fire()
check(string.find(menu.Main.Details.Play.Text, "LOCKED") ~= nil, "a locked night can't be played")
check(menu.Main.Preview:FindFirstChild("Monster") ~= nil, "the selected night's monster is previewed")
menu.Main.Details.Play.Activated:Fire()
run(1)
check(phase() == "Lobby" and not ClientState.started, "pressing play on a locked night does nothing")

---------------------------------------------------------------------------
print("Night 1: THE HOUSE (survive)")
check(startNight(1), "night 1 starts")
check(not menu.Main.Visible, "menu hides while playing")
check(objectiveText() == "Survive until 6 AM.", "objective shown: " .. objectiveText())
check(string.find(progressText(), "AM") ~= nil, "clock shown: " .. progressText())
press("AchromaFlashlight")
run(0.3)
check(player:GetAttribute("Flashlight") == true, "flashlight works")
-- hide in a locker and wait for morning
local locker = prompts("Locker")[1] or prompts("Wardrobe")[1]
check(locker ~= nil, "found a hiding spot")
locker.Triggered:Fire(player)
run(0.5)
check(ClientState.hiding, "hiding")
local morning = run(320, function()
	return ClientState.roundStatus == "escaped"
end, 0.1)
check(morning, "made it to 6 AM (" .. progressText() .. ")")
finishAndReturn("YOU SURVIVED")
check(player:GetAttribute("HighestNight") == 2, "night 2 unlocked")
check(not card(2).Locked.Visible and card(1).Status.Text == "CLEARED", "menu shows night 1 cleared, night 2 open")

---------------------------------------------------------------------------
print("Night 2: THE RED WARD (keys)")
check(startNight(2), "night 2 starts")
check(GameState:GetAttribute("NightName") == "THE RED WARD", "it's the ward")
check(workspace.Monster:GetAttribute("Kind") == "Crawler", "the Crawler is here")
for _, prompt in prompts("Key") do
	prompt.Triggered:Fire(player)
	run(0.2)
end
check(string.find(progressText(), "KEYS 4/4") ~= nil, "HUD: " .. progressText())
local keypad = workspace.World:FindFirstChild("Keypad", true)
placePlayer(keypad.Position + Vector3.new(0, 0, 4))
keypad:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(player)
run(0.2)
local panel = player.PlayerGui.AchromaKeypad.Panel
check(player.PlayerGui.AchromaKeypad.Enabled, "keypad screen opens")
for i = 1, #Engine.layout.code do
	panel["Key" .. string.sub(Engine.layout.code, i, i)].Activated:Fire()
end
panel.KeyOK.Activated:Fire()
run(1)
check(GameState:GetAttribute("ExitOpen") == true, "typing the code opens the exit")
workspace.World.Structure.EscapeZone.Touched:Fire(player.Character.HumanoidRootPart)
finishAndReturn("YOU MADE IT")
check(player:GetAttribute("HighestNight") == 3, "night 3 unlocked")

---------------------------------------------------------------------------
print("Night 3: THE DROWNED TUNNELS (power)")
check(startNight(3), "night 3 starts")
check(workspace.Monster:GetAttribute("Kind") == "Listener", "the Listener is here")
for _, prompt in prompts("Generator") do
	prompt.Triggered:Fire(player)
	run(0.2)
end
run(2)
check(GameState:GetAttribute("ExitOpen") == true, "the lift opens (" .. progressText() .. ")")
workspace.World.Structure.EscapeZone.Touched:Fire(player.Character.HumanoidRootPart)
finishAndReturn("YOU MADE IT")
check(player:GetAttribute("HighestNight") == 4, "night 4 unlocked")

---------------------------------------------------------------------------
print("Night 4: THE ATRIUM (photographs)")
check(startNight(4), "night 4 starts")
check(workspace.Monster:GetAttribute("Kind") == "Statue", "the Statue is here")
local decoys = 0
for _, d in workspace.World:GetDescendants() do
	if d.Name == "Statue" and d.ClassName == "Model" then
		decoys += 1
	end
end
check(decoys >= 4, "there are decoy statues (" .. decoys .. ")")
for _, prompt in prompts("Photograph") do
	prompt.Triggered:Fire(player)
	run(0.2)
end
finishAndReturn("YOU MADE IT")
check(player:GetAttribute("HighestNight") == 5, "night 5 unlocked")

---------------------------------------------------------------------------
print("Night 5: THE VOID (hearts)")
check(startNight(5), "night 5 starts")
check(workspace.Monster:GetAttribute("Kind") == "Amalgam", "the Amalgam is here")
local hearts = prompts("Heart")
check(#hearts == 3, "3 hearts")
for _, prompt in hearts do
	prompt.Triggered:Fire(player)
end
run(1)
check(GameState:GetAttribute("ExitOpen") == true, "the portal opens")
workspace.World.Structure.EscapeZone.Touched:Fire(player.Character.HumanoidRootPart)
finishAndReturn("THE COLOR IS BACK")
check(player:GetAttribute("HighestNight") == 6, "every night beaten")
check(card(5).Status.Text == "CLEARED", "night 5 shows as cleared")

---------------------------------------------------------------------------
print("Night 1 again: caught by the Hollow")
check(startNight(1), "night 1 starts again")
run(1)
local monster = workspace.Monster
local m = monster.HumanoidRootPart
-- walk straight into it once it's awake
local awake = run(80, function()
	return GameState:GetAttribute("MonsterAwake") == true
end, 0.1)
check(awake, "it wakes up at 1 AM")
placePlayer(m.Position + m.CFrame.LookVector * 3)
local caught = run(3, function()
	return ClientState.jumpscaring
end)
check(caught, "it catches you: jumpscare")
check(workspace.CurrentCamera.CameraType == Enum.CameraType.Scriptable, "camera pulled into its face")
finishAndReturn("NOBODY MADE IT")

---------------------------------------------------------------------------
print("Notifications received: " .. #notifications)
for i = 1, math.min(10, #notifications) do
	print("  > " .. string.gsub(notifications[i], "\n", " / "))
end
check(#Engine.errors == 0, "no script errors (" .. #Engine.errors .. ")")
if failures > 0 then
	error(failures .. " check(s) failed")
end
print("end-to-end tests passed")
