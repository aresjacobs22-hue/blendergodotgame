-- End-to-end: boots the real server Script and client LocalScript together in the
-- mocked engine and plays the whole game as a fake player, through the actual UI:
--   the lobby (walk into a door's square, pick the night and 1 player)
--   -> night 1 (survive, hiding in a locker) -> night 2 unlocked
--   -> keys + on-screen keypad -> generators -> photographs -> hearts (the end)
--   -> back to night 1 to get caught by the Hollow (jumpscare) -> TRY AGAIN (it starts
--   over) -> caught again -> BACK TO LOBBY.
-- It also checks the game never shows words: only "NIGHT 1".."NIGHT 5", ever.
-- Run with:  lune run tests/e2e.spec.luau
local roblox = require("@lune/roblox")
local Engine = require("./mock/engine")

local Vector3 = roblox.Vector3
local CFrame = Engine.CFrame
local Enum = roblox.Enum

local REMOTES = { "Notify", "Jumpscare", "OpenKeypad", "SubmitCode", "LeaveHiding", "Flashlight", "Battery", "Apparition", "Escaped", "Look", "Throw", "Breath", "Chaos", "Lobby", "Retry" }

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
game:GetService("UserInputService").KeyboardEnabled = true
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
	CFrame = Engine.CFrame,
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
	-- the client prints server narration to the console; keep it out of the test output
	print = function(...)
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
local Hud = require(client.Hud)
local Lobby = require(server.Lobby)

-- the night entries on the choice screen at a lobby door
local function entry(n: number)
	return menu.Choice.Nights["Night" .. n]
end

local function pad(i: number)
	return workspace.Lobby["Pad" .. i]
end

local function inLobby(): boolean
	local character = player.Character
	return player:GetAttribute("Where") == "lobby" and character ~= nil and (character.HumanoidRootPart.Position - Lobby.ORIGIN).Magnitude < Lobby.RADIUS + 5
end

-- Every piece of text a player could see right now.
local function hud()
	return player.PlayerGui.AchromaHud
end

local function shownText(): { string }
	local out = {}
	local function visible(g): boolean
		local node = g
		while node and node ~= player.PlayerGui do
			if node.ClassName == "ScreenGui" or node.ClassName == "BillboardGui" then
				if node.Enabled == false then
					return false
				end
			elseif node.Visible == false then
				return false
			end
			node = node.Parent
		end
		return true
	end
	for _, d in player.PlayerGui:GetDescendants() do
		if (d.ClassName == "TextLabel" or d.ClassName == "TextButton") and (d.Text or "") ~= "" and (d.TextTransparency or 0) < 0.95 and visible(d) then
			table.insert(out, d.Text)
		end
	end
	return out
end

-- What each night asks of you, in red at the top of the screen.
local OBJECTIVES = {
	"SURVIVE UNTIL 6 AM",
	"FIND THE FOUR KEYS",
	"ENTER THE CODE AT THE EXIT",
	"GET OUT",
	"START THE THREE GENERATORS",
	"GET TO THE LIFT",
	"FIND THE SIX PHOTOGRAPHS",
	"DESTROY THE THREE HEARTS",
	"GET TO THE PORTAL",
}

-- The only words allowed on screen: the nights' numbers ("N I G H T    3"), the
-- player counts and the cross on the choice screen, the controls before a night, the
-- objective and the hour during one, and TRY AGAIN (1 / 4) / BACK TO LOBBY when you're
-- caught.
local function onlyNights(where: string)
	local bad = {}
	for _, t in shownText() do
		local choice = t == Hud.spaced("TRY AGAIN") or t == Hud.spaced("BACK TO LOBBY") or string.match(t, "^%d / %d$")
		local playing = table.find(OBJECTIVES, t) ~= nil or string.match(t, "^%d+ AM$")
		if not (string.match(t, "^N I G H T%s+%d$") or string.match(t, "^%d$") or t == "×" or t == Hud.KEYBOARD_CONTROLS or choice or playing) then
			table.insert(bad, t)
		end
	end
	check(#bad == 0, "no words on screen " .. where .. (if #bad > 0 then " (saw: " .. table.concat(bad, " | ") .. ")" else ""))
end

-- Walk into a door's square; when the choice comes up pick the night and 1 player.
local function startNight(n: number, door: number?)
	placePlayer(pad(door or 1).Position)
	if not run(3, function()
		return menu.Choice.Visible
	end) then
		return false
	end
	entry(n).Activated:Fire()
	check(entry(n).TextTransparency < 0.5, "night " .. n .. " can be chosen")
	menu.Choice.Players.Players1.Activated:Fire()
	return run(15, function()
		return phase() == "Playing" and player:GetAttribute("Where") == "night" and player.Character ~= nil
	end)
end

local function finishAndReturn(escaped: boolean)
	local results = run(20, function()
		return phase() == "Results"
	end)
	check(results, "the night ends")
	check(ClientState.roundStatus == (if escaped then "escaped" else "caught"), "you " .. (if escaped then "made it" else "were caught") .. " (" .. tostring(ClientState.roundStatus) .. ")")
	local black = run(15, function()
		return menu.Overlay.Visible
	end)
	check(black, "then just black")
	onlyNights("after the night")
	local back = run(25, function()
		return phase() == "Lobby" and inLobby()
	end)
	check(back, "back in the lobby")
	check(not hud().Objective.Visible and not hud().Clock.Visible, "no objective or clock in the lobby")
end

-- the objective at the top: in red, and saying `text`
local function objectiveIs(text: string): boolean
	local label = hud().Objective
	local color = label.TextColor3
	return label.Visible and label.Text == text and label.AnchorPoint.Y == 0 and label.Position.Y.Offset < 40 and color.R > 0.5 and color.G < 0.15 and color.B < 0.15
end

local function progress(): string
	return string.format("%s/%s", tostring(GameState:GetAttribute("Done")), tostring(GameState:GetAttribute("Goal")))
end

local function litPips(): number
	local n = 0
	for _, dot in player.PlayerGui.AchromaHud.Pips:GetChildren() do
		if dot.ClassName == "Frame" and dot.Visible and dot:GetAttribute("Lit") == true then
			n += 1
		end
	end
	return n
end

---------------------------------------------------------------------------
print("The lobby")
run(2)
menu = player.PlayerGui:FindFirstChild("AchromaMenu")
local UserInputService = game:GetService("UserInputService")
check(inLobby(), "you wake up in the lobby")
check(phase() == "Lobby", "server waits in the lobby")
check(player:GetAttribute("HighestNight") == 1, "a new player hasn't beaten anything")
local squares = 0
for i = 1, 4 do
	if workspace.Lobby:FindFirstChild("Pad" .. i) then
		squares += 1
	end
end
check(squares == 4, "four doors, four squares")
check(workspace.Lobby:FindFirstChild("Watcher") ~= nil, "something stands in the fog")
onlyNights("in the lobby")
check(UserInputService.MouseIconEnabled == false, "no cursor while you walk around")
-- step into a square: the choice
placePlayer(pad(2).Position)
run(1)
check(menu.Choice.Visible, "stepping into a square asks you")
check(UserInputService.MouseIconEnabled == true, "the cursor comes up for it")
onlyNights("at the door")
local allOpen = true
for i = 2, 5 do
	allOpen = allOpen and entry(i).TextTransparency < 0.7
end
check(entry(1).TextTransparency < 0.1 and allOpen, "all five nights are open, night 1 picked first")
entry(5).Activated:Fire()
check(entry(5).TextTransparency < 0.1 and entry(1).TextTransparency > 0.5, "any night can be picked, even night 5")
-- walk away: it closes and nothing happens
placePlayer(Lobby.ORIGIN)
run(1)
check(not menu.Choice.Visible and UserInputService.MouseIconEnabled == false, "walking away closes it")
check(phase() == "Lobby" and inLobby(), "and you're still in the lobby")

---------------------------------------------------------------------------
print("Night 1: THE HOUSE (survive)")
check(startNight(1), "picking 1 player goes straight in: night 1 starts")
check(not menu.Choice.Visible and not inLobby(), "out of the lobby")
onlyNights("as the night starts")
check(player.PlayerGui.AchromaHud.Controls.Text == Hud.KEYBOARD_CONTROLS, "the controls show before the night")
run(8)
onlyNights("while playing")
check(UserInputService.MouseIconEnabled == false, "no cursor while playing")
check(objectiveIs("SURVIVE UNTIL 6 AM"), "the objective in red at the top (" .. hud().Objective.Text .. ")")
local clock = hud().Clock
check(clock.Visible and clock.Text == "12 AM" and clock.AnchorPoint.X == 1 and clock.Position.X.Scale == 1 and clock.Position.Y.Offset < 40, "12 AM in the top right corner (" .. clock.Text .. ")")
check(not hud().Pips.Visible, "the hour instead of dots")
press("AchromaFlashlight")
run(0.3)
check(player:GetAttribute("Flashlight") == true, "flashlight works")
-- hide in a locker and wait for morning
local locker = prompts("Locker")[1] or prompts("Wardrobe")[1]
check(locker ~= nil, "found a hiding spot")
locker.Triggered:Fire(player)
run(0.5)
check(ClientState.hiding, "hiding")
-- hold your breath whenever it comes close to the locker
local breathHeld = 0
local revealedAt = nil
local atThree = nil
local morning = run(320, function()
	if ClientState.roundStatus ~= "alive" then
		return true
	end
	if not ClientState.hiding and not revealedAt then
		revealedAt = tostring(GameState:GetAttribute("Hour")) .. " AM"
	end
	if GameState:GetAttribute("Hour") == 3 and not atThree then
		atThree = clock.Text
	end
	local monster = workspace:FindFirstChild("Monster")
	local character = player.Character
	local near = monster ~= nil and character ~= nil and (monster.HumanoidRootPart.Position - character.HumanoidRootPart.Position).Magnitude < 10
	if near and not ClientState.holdingBreath and ClientState.hiding then
		press("AchromaBreath")
		breathHeld += 1
	elseif not near and ClientState.holdingBreath then
		release("AchromaBreath")
	end
	return ClientState.roundStatus == "escaped"
end, 0.1) and ClientState.roundStatus == "escaped"
release("AchromaBreath")
check(morning, "made it to 6 AM (hour " .. tostring(GameState:GetAttribute("Hour")) .. ")")
check(atThree == "3 AM", "the clock kept time (" .. tostring(atThree) .. " at 3)")
print("    (held breath " .. breathHeld .. " times; " .. (if revealedAt then "dragged out at " .. revealedAt else "stayed hidden") .. ")")
finishAndReturn(true)
check(player:GetAttribute("HighestNight") == 2, "night 1 beaten: saved")

---------------------------------------------------------------------------
print("Night 2: THE RED WARD (keys)")
placePlayer(pad(1).Position)
run(1)
check(menu.Choice.Visible and entry(2).TextTransparency < 0.1, "the door now starts on night 2")
placePlayer(Lobby.ORIGIN)
run(1)
check(startNight(2), "night 2 starts")
check(GameState:GetAttribute("NightName") == "THE RED WARD", "it's the ward")
check(workspace.Monster:GetAttribute("Kind") == "Crawler", "the Crawler is here")
check(objectiveIs("FIND THE FOUR KEYS"), "FIND THE FOUR KEYS (" .. hud().Objective.Text .. ")")
check(hud().Pips.Visible and not hud().Clock.Visible, "dots, no clock")
for _, prompt in prompts("Key") do
	prompt.Triggered:Fire(player)
	run(0.2)
end
check(progress() == "4/5" and litPips() == 4, "four of five dots lit (" .. progress() .. ")")
check(objectiveIs("ENTER THE CODE AT THE EXIT"), "then ENTER THE CODE AT THE EXIT")
local keypad = workspace.World:FindFirstChild("Keypad", true)
placePlayer(keypad.Position + Vector3.new(0, 0, 4))
keypad:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(player)
run(0.2)
local panel = player.PlayerGui.AchromaKeypad.Panel
check(player.PlayerGui.AchromaKeypad.Enabled, "keypad screen opens")
check(UserInputService.MouseIconEnabled == true, "the cursor comes back for the keypad")
local display = panel:FindFirstChildOfClass("TextLabel").Text
check(string.find(display, string.sub(Engine.layout.code, 1, 1), 1, true) ~= nil, "it shows the digits from the keys you found, faintly (" .. display .. ")")
for i = 1, #Engine.layout.code do
	panel["Key" .. string.sub(Engine.layout.code, i, i)].Activated:Fire()
end
panel.KeyOK.Activated:Fire()
run(1)
check(UserInputService.MouseIconEnabled == false, "and goes away again after")
check(GameState:GetAttribute("ExitOpen") == true, "typing the code opens the exit")
check(objectiveIs("GET OUT"), "then GET OUT")
onlyNights("with the exit open")
workspace.World.Structure.EscapeZone.Touched:Fire(player.Character.HumanoidRootPart)
finishAndReturn(true)
check(player:GetAttribute("HighestNight") == 3, "night 2 beaten: saved")

---------------------------------------------------------------------------
print("Night 3: THE DROWNED TUNNELS (power)")
check(startNight(3), "night 3 starts")
check(workspace.Monster:GetAttribute("Kind") == "Listener", "the Listener is here")
check(objectiveIs("START THE THREE GENERATORS"), "START THE THREE GENERATORS (" .. hud().Objective.Text .. ")")
for _, prompt in prompts("Generator") do
	prompt.Triggered:Fire(player)
	run(0.2)
end
run(2)
check(GameState:GetAttribute("ExitOpen") == true, "the lift opens (" .. progress() .. ")")
check(objectiveIs("GET TO THE LIFT"), "then GET TO THE LIFT")
workspace.World.Structure.EscapeZone.Touched:Fire(player.Character.HumanoidRootPart)
finishAndReturn(true)
check(player:GetAttribute("HighestNight") == 4, "night 3 beaten: saved")

---------------------------------------------------------------------------
print("Night 4: THE ATRIUM (photographs)")
check(startNight(4), "night 4 starts")
check(workspace.Monster:GetAttribute("Kind") == "Statue", "the Statue is here")
check(objectiveIs("FIND THE SIX PHOTOGRAPHS"), "FIND THE SIX PHOTOGRAPHS (" .. hud().Objective.Text .. ")")
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
finishAndReturn(true)
check(player:GetAttribute("HighestNight") == 5, "night 4 beaten: saved")

---------------------------------------------------------------------------
print("Night 5: THE VOID (hearts)")
check(startNight(5), "night 5 starts")
check(workspace.Monster:GetAttribute("Kind") == "Amalgam", "the Amalgam is here")
check(objectiveIs("DESTROY THE THREE HEARTS"), "DESTROY THE THREE HEARTS (" .. hud().Objective.Text .. ")")
local hearts = prompts("Heart")
check(#hearts == 3, "3 hearts")
for _, prompt in hearts do
	prompt.Triggered:Fire(player)
end
run(1)
check(GameState:GetAttribute("ExitOpen") == true, "the portal opens")
check(objectiveIs("GET TO THE PORTAL"), "then GET TO THE PORTAL")
workspace.World.Structure.EscapeZone.Touched:Fire(player.Character.HumanoidRootPart)
finishAndReturn(true)
check(player:GetAttribute("HighestNight") == 6, "every night beaten")

---------------------------------------------------------------------------
print("Night 1 again: caught by the Hollow")
check(startNight(1), "night 1 starts again")
run(1)
-- walk straight into it once it's awake
local function getCaught()
	local awake = run(80, function()
		return GameState:GetAttribute("MonsterAwake") == true
	end, 0.1)
	check(awake, "it wakes up at 1 AM")
	local m = workspace.Monster.HumanoidRootPart
	placePlayer(m.Position + m.CFrame.LookVector * 3)
	local caught = run(3, function()
		return ClientState.jumpscaring
	end)
	check(caught, "it catches you: jumpscare")
end
getCaught()
check(workspace.CurrentCamera.CameraType == Enum.CameraType.Scriptable, "camera pulled into its face")
onlyNights("during the jumpscare")
local offered = run(10, function()
	return menu.Death.Visible
end)
check(offered, "then the choice: TRY AGAIN or BACK TO LOBBY")
check(menu.Death.Again.Text == Hud.spaced("TRY AGAIN") and menu.Death.Lobby.Text == Hud.spaced("BACK TO LOBBY"), "it says so")
check(menu.Death.Count.Text == "0 / 1", "nobody has chosen yet (" .. menu.Death.Count.Text .. ")")
check(UserInputService.MouseIconEnabled == true, "with the cursor")
check(player:GetAttribute("Where") == "between" and player.Character == nil, "no body, no spectating")
onlyNights("on the choice")
menu.Death.Again.Activated:Fire()
local again = run(15, function()
	return phase() == "Playing" and player:GetAttribute("Where") == "night" and player.Character ~= nil
end)
check(again, "TRY AGAIN, 1 / 1: the night starts over")
check(not menu.Death.Visible and UserInputService.MouseIconEnabled == false, "the choice is gone")
run(1)
getCaught()
check(run(10, function()
	return menu.Death.Visible
end), "caught again: the choice again")
menu.Death.Lobby.Activated:Fire()
local back = run(15, function()
	return inLobby()
end)
check(back, "BACK TO LOBBY: back in the lobby")
check(run(3, function()
	return phase() == "Lobby"
end), "and the doors are open again")

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
