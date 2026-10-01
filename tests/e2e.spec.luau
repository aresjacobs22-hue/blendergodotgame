-- End-to-end: boots the real server Script and client LocalScript together in the
-- mocked engine and plays two full rounds as a fake player, driving the actual UI:
--   round 1: wake up -> flashlight -> sprint -> 4 keys -> keypad -> escape
--   round 2: hide/leave a locker -> get caught -> jumpscare
-- Run with:  lune run tests/e2e.spec.luau
local roblox = require("@lune/roblox")
local Engine = require("./mock/engine")

local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Enum = roblox.Enum

local REMOTES = { "Ready", "Notify", "Jumpscare", "OpenKeypad", "SubmitCode", "LeaveHiding", "Flashlight", "Battery", "RoundResult", "Apparition", "Escaped" }

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
local Config = require(rs.Shared.Config)
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

local function run(seconds: number, until_: (() -> boolean)?): boolean
	local dt = 1 / 30
	local t = 0
	while t < seconds do
		Engine.step(game, dt)
		moveMonster(dt)
		t += dt
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

local function findPrompt(root, objectText: string)
	for _, d in root:GetDescendants() do
		if d.ClassName == "ProximityPrompt" and d.ObjectText == objectText and d.Enabled then
			return d
		end
	end
	return nil
end

---------------------------------------------------------------------------
print("Title screen")
run(1)
local menu = player.PlayerGui:FindFirstChild("AchromaMenu")
check(menu and menu.Title.Visible, "title screen is showing")
check(phase() == "Waiting", "server waits for someone to wake up")
check(player.Character == nil, "no character until you press WAKE UP")

menu.Title.WakeUp.Activated:Fire()
check(ClientState.started, "clicking WAKE UP starts the game")
local spawned = run(10, function()
	return player.Character ~= nil and phase() == "Playing"
end)
check(spawned, "round starts and you spawn after the countdown")
check(ClientState.roundStatus == "alive", "client knows you're alive")
local root = player.Character.HumanoidRootPart
local layout = Engine.layout
local house = layout.house
check(Maze.isHouse(layout, math.floor(root.Position.X / layout.cellSize), math.floor(root.Position.Z / layout.cellSize)), "you wake up inside the house")
check(player.PlayerGui.AchromaHud.Info.Visible, "HUD is visible")
run(2)
check(not menu.Overlay.Visible, "no overlay while playing")

---------------------------------------------------------------------------
print("Flashlight + sprinting")
press("AchromaFlashlight")
run(0.2)
check(ClientState.flashlightOn, "F turns the flashlight on")
check(player:GetAttribute("Flashlight") == true, "the server knows your light is on")
local humanoid = player.Character.Humanoid
humanoid.MoveDirection = Vector3.new(0, 0, -1)
press("AchromaSprint")
run(1)
check(humanoid.WalkSpeed == Config.Player.SprintSpeed, "holding shift sprints")
run(7)
check(humanoid.WalkSpeed < Config.Player.SprintSpeed, "stamina runs out")
release("AchromaSprint")
humanoid.MoveDirection = Vector3.zero
press("AchromaCrouch")
run(0.2)
check(humanoid.WalkSpeed == Config.Player.CrouchSpeed, "C crouches")
press("AchromaCrouch")
run(0.2)

---------------------------------------------------------------------------
print("Keys")
local interactive = workspace.World.Interactive
for i = 1, Config.Maze.KeyCount do
	local key = interactive:FindFirstChild("Key" .. i)
	local prompt = key and key.Shaft:FindFirstChildOfClass("ProximityPrompt")
	check(prompt ~= nil, "key " .. i .. " has a prompt")
	if prompt then
		prompt.Triggered:Fire(player)
	end
	run(0.3)
end
check(GameState:GetAttribute("KeysFound") == 4, "server counted 4 keys")
check(GameState:GetAttribute("CodeMask") == layout.code, "the whole code is revealed")
local hudCode = player.PlayerGui.AchromaHud.Info:GetChildren()
local shownCode = nil
for _, c in hudCode do
	if c.ClassName == "TextLabel" and c.TextSize == 26 then
		shownCode = c.Text
	end
end
check(shownCode == table.concat(string.split(layout.code, ""), " "), "HUD shows the code: " .. tostring(shownCode))
check(workspace.Monster:GetAttribute("State") ~= "Dormant", "taking a key woke the monster")

---------------------------------------------------------------------------
print("Keypad + exit")
local keypad = interactive.Keypad
placePlayer(keypad.Position + Vector3.new(0, 0, 4))
keypad:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(player)
run(0.2)
local keypadGui = player.PlayerGui.AchromaKeypad
check(keypadGui.Enabled, "keypad screen opens")
local panel = keypadGui.Panel
for i = 1, #layout.code do
	panel["Key" .. string.sub(layout.code, i, i)].Activated:Fire()
end
panel.KeyOK.Activated:Fire()
run(0.5)
check(not keypadGui.Enabled, "keypad screen closes after OK")
check(GameState:GetAttribute("ExitOpen") == true, "the right code opens the exit")

---------------------------------------------------------------------------
print("Escape")
local zone = workspace.World.Structure.EscapeZone
workspace.World.Structure.EscapeZone.Touched:Fire(player.Character.HumanoidRootPart)
run(0.5)
check(ClientState.roundStatus == "escaped", "touching the light escapes")
local results = run(15, function()
	return phase() == "Results" and menu.Overlay.Visible
end)
check(results, "results screen appears")
check(menu.Overlay:FindFirstChildOfClass("TextLabel").Text == "YOU ESCAPED", "results say YOU ESCAPED")
zone = zone

---------------------------------------------------------------------------
print("Round 2: hide, then get caught")
local round2 = run(30, function()
	return phase() == "Playing" and player.Character ~= nil
end)
check(round2, "a new night starts and you wake up again")
check(Engine.layout ~= layout and Engine.layout.seed ~= layout.seed, "the new night has a new maze")
check(ClientState.roundStatus == "alive", "alive again")
interactive = workspace.World.Interactive

local lockerPrompt = findPrompt(interactive, "Locker")
check(lockerPrompt ~= nil, "found a locker")
if lockerPrompt then
	lockerPrompt.Triggered:Fire(player)
	run(0.5)
	check(player:GetAttribute("Hiding") == true and ClientState.hiding, "hiding in the locker")
	check(Engine.actions.AchromaLeave ~= nil, "leave action is bound while hiding")
	run(1)
	press("AchromaLeave")
	run(0.5)
	check(player:GetAttribute("Hiding") == false and not ClientState.hiding, "pressed E to get out")
end

-- wake it, then walk right into it
local key = interactive:FindFirstChild("Key1")
key.Shaft:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(player)
run(0.5)
local monster = workspace.Monster
local mroot = monster.HumanoidRootPart
placePlayer(mroot.Position + mroot.CFrame.LookVector * 3)
local caught = run(3, function()
	return ClientState.jumpscaring
end)
check(caught, "it catches you and the jumpscare starts")
check(ClientState.roundStatus == "caught", "client knows you were caught")
local camera = workspace.CurrentCamera
check(camera.CameraType == Enum.CameraType.Scriptable, "camera is pulled into its face")
run(6)
check(player.Character == nil, "your body is gone")
check(not ClientState.jumpscaring, "jumpscare sequence finished")
local over = run(15, function()
	return phase() == "Results" and menu.Overlay.Visible
end)
check(over, "results screen after being caught")
check(menu.Overlay:FindFirstChildOfClass("TextLabel").Text == "NOBODY ESCAPED", "results say NOBODY ESCAPED")
local round3 = run(30, function()
	return phase() == "Playing" and player.Character ~= nil
end)
check(round3, "and the night starts over")

---------------------------------------------------------------------------
print("Notifications received: " .. #notifications)
for i = 1, math.min(8, #notifications) do
	print("  > " .. string.gsub(notifications[i], "\n", " / "))
end
check(#Engine.errors == 0, "no script errors (" .. #Engine.errors .. ")")
if #Engine.log > 0 then
	print("warnings: " .. #Engine.log)
	for i = 1, math.min(5, #Engine.log) do
		print("  " .. Engine.log[i])
	end
end
if failures > 0 then
	error(failures .. " check(s) failed")
end
print("end-to-end tests passed")
