--!strict
-- The round loop: wait for players -> countdown -> build a fresh maze -> play until
-- everyone is caught or out -> show results -> tear down -> repeat.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Maze = require(ReplicatedStorage.Shared.Maze)
local Interactables = require(script.Parent.Interactables)
local MonsterAI = require(script.Parent.MonsterAI)
local WorldBuilder = require(script.Parent.WorldBuilder)

local Remotes = ReplicatedStorage.Remotes
local GameState = ReplicatedStorage.GameState

type Round = {
	layout: Maze.Layout,
	world: WorldBuilder.World,
	interactables: Interactables.Interactables,
	monster: MonsterAI.MonsterAI,
	keysFound: number,
	mask: { string },
	startedAt: number,
	spawnIndex: number,
}

local RoundManager = {}

local ready: { [Player]: boolean } = {}
local status: { [Player]: string } = {} -- "alive" | "caught" | "escaped"
local round: Round? = nil

local function isAlive(player: Player): boolean
	return status[player] == "alive" and player.Parent ~= nil
end

local function alivePlayers(): { Player }
	local list = {}
	for player, s in status do
		if s == "alive" and player.Parent ~= nil then
			table.insert(list, player)
		end
	end
	return list
end

local function notifyAll(text: string, style: string?)
	Remotes.Notify:FireAllClients(text, style)
end

local function notifyOthers(except: Player, text: string, style: string?)
	for _, p in Players:GetPlayers() do
		if p ~= except then
			Remotes.Notify:FireClient(p, text, style)
		end
	end
end

local function removeCharacter(player: Player)
	local character = player.Character
	if character then
		character:Destroy()
	end
	pcall(function()
		player.Character = nil
	end)
end

local function spawnPlayer(player: Player)
	local r = round
	if not r or status[player] ~= nil then
		return
	end
	status[player] = "alive"
	player:SetAttribute("Hiding", false)
	player:SetAttribute("Flashlight", false)
	local ok = pcall(function()
		player:LoadCharacterAsync()
	end)
	if not ok then
		-- older engines only have the (now deprecated) synchronous version
		ok = pcall(function()
			(player :: any):LoadCharacter()
		end)
	end
	local character = player.Character
	if not ok or not character or round ~= r then
		return
	end
	r.spawnIndex += 1
	character:PivotTo(r.world.spawnPoints[(r.spawnIndex - 1) % #r.world.spawnPoints + 1])
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Died:Connect(function()
			if status[player] == "alive" and round == r then
				RoundManager.caught(player, nil)
			end
		end)
	end
end

function RoundManager.caught(player: Player, monster: Model?)
	if status[player] ~= "alive" then
		return
	end
	status[player] = "caught"
	local r = round
	if r then
		r.interactables:release(player)
		r.monster:forget(player)
	end
	if monster then
		Remotes.Jumpscare:FireClient(player, monster)
	end
	notifyOthers(player, player.DisplayName .. " was taken.", "danger")
	task.delay(if monster then 2.7 else 0.5, function()
		if status[player] == "caught" then
			removeCharacter(player)
		end
	end)
end

function RoundManager.escaped(player: Player)
	if status[player] ~= "alive" then
		return
	end
	status[player] = "escaped"
	local r = round
	if r then
		r.monster:forget(player)
	end
	Remotes.Escaped:FireClient(player)
	notifyOthers(player, player.DisplayName .. " made it out.", "key")
	task.delay(4, function()
		if status[player] == "escaped" then
			removeCharacter(player)
		end
	end)
end

local function startRound()
	local seed = Random.new():NextInteger(1, 2 ^ 30)
	local layout = Maze.generate(seed, Config.Maze)
	local world = WorldBuilder.build(layout)

	local monster: MonsterAI.MonsterAI
	local r: Round

	local interactables = Interactables.new(layout, world, {
		isAlive = isAlive,
		onKey = function(player: Player, index: number)
			r.keysFound += 1
			r.mask[index] = string.sub(layout.code, index, index)
			GameState:SetAttribute("KeysFound", r.keysFound)
			GameState:SetAttribute("CodeMask", table.concat(r.mask))
			r.interactables:removePadlock()
			local tag = {}
			for i = 1, #layout.code do
				tag[i] = if i == index then string.sub(layout.code, i, i) else "_"
			end
			notifyAll(string.format("%s found a key. The tag reads   %s", player.DisplayName, table.concat(tag, " ")), "key")
			monster:setAggression(r.keysFound)
			monster:awaken()
			if r.keysFound >= Config.Maze.KeyCount then
				notifyAll("Every padlock is open. Get to the keypad by the exit.", "key")
			end
		end,
		onHide = function(player: Player, locker: Interactables.Locker)
			monster:onPlayerHid(player, locker)
		end,
		onExitOpened = function(player: Player)
			GameState:SetAttribute("ExitOpen", true)
			notifyAll("The exit is open. RUN.", "danger")
			monster:onExitOpened()
		end,
		onEscaped = RoundManager.escaped,
		onNoise = function(position: Vector3, radius: number)
			monster:hearNoise(position, radius)
		end,
	})

	monster = MonsterAI.new(layout, world, interactables, {
		getPlayers = alivePlayers,
		onCaught = RoundManager.caught,
		onAwake = function()
			GameState:SetAttribute("MonsterAwake", true)
		end,
	})

	r = {
		layout = layout,
		world = world,
		interactables = interactables,
		monster = monster,
		keysFound = 0,
		mask = table.create(Config.Maze.KeyCount, "_"),
		startedAt = os.clock(),
		spawnIndex = 0,
	}

	table.clear(status)
	round = r
	GameState:SetAttribute("KeysFound", 0)
	GameState:SetAttribute("KeyCount", Config.Maze.KeyCount)
	GameState:SetAttribute("CodeMask", table.concat(r.mask))
	GameState:SetAttribute("ExitOpen", false)
	GameState:SetAttribute("MonsterAwake", false)
	GameState:SetAttribute("Result", "")
	GameState:SetAttribute("Phase", "Playing")

	for player in ready do
		task.spawn(spawnPlayer, player)
	end
	monster:start()
end

local function endRound()
	local r = round
	if not r then
		return
	end
	local survivors = {}
	for player, s in status do
		if s == "escaped" then
			table.insert(survivors, player.DisplayName)
		end
	end
	local result = if #survivors > 0 then "Escaped" else "Caught"
	GameState:SetAttribute("Result", result)
	GameState:SetAttribute("Phase", "Results")
	Remotes.RoundResult:FireAllClients(result, survivors, math.floor(os.clock() - r.startedAt))

	task.wait(Config.Round.ResultsTime)

	r.monster:destroy()
	r.interactables:destroy()
	r.world.model:Destroy()
	round = nil
	table.clear(status)
	for _, player in Players:GetPlayers() do
		removeCharacter(player)
		player:SetAttribute("Hiding", false)
	end
end

function RoundManager.run()
	Players.CharacterAutoLoads = false
	WorldBuilder.setupCollisionGroups()

	GameState:SetAttribute("Phase", "Waiting")
	GameState:SetAttribute("Countdown", 0)
	GameState:SetAttribute("KeysFound", 0)
	GameState:SetAttribute("KeyCount", Config.Maze.KeyCount)
	GameState:SetAttribute("CodeMask", string.rep("_", Config.Maze.KeyCount))

	Remotes.Ready.OnServerEvent:Connect(function(player: Player)
		if ready[player] then
			return
		end
		ready[player] = true
		if round and GameState:GetAttribute("Phase") == "Playing" then
			task.spawn(spawnPlayer, player)
		end
	end)

	-- Everyone else sees your flashlight beam too (and so does the monster).
	Remotes.Flashlight.OnServerEvent:Connect(function(player: Player, on: unknown)
		if typeof(on) ~= "boolean" then
			return
		end
		player:SetAttribute("Flashlight", on)
		local character = player.Character
		local head = if character then character:FindFirstChild("Head") else nil
		if head and head:IsA("BasePart") then
			local existing = head:FindFirstChild("SharedFlashlight")
			local light: SpotLight
			if existing and existing:IsA("SpotLight") then
				light = existing
			else
				light = Instance.new("SpotLight")
				light.Name = "SharedFlashlight"
				light.Face = Enum.NormalId.Front
				light.Angle = 50
				light.Range = 40
				light.Brightness = 2
				light.Shadows = true
				light.Parent = head
			end
			light.Enabled = on
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		ready[player] = nil
		local r = round
		if r then
			r.interactables:release(player)
			r.monster:forget(player)
		end
		status[player] = nil
	end)

	local first = true
	while true do
		GameState:SetAttribute("Phase", "Waiting")
		while next(ready) == nil do
			task.wait(0.5)
		end

		GameState:SetAttribute("Phase", "Intermission")
		for i = if first then Config.Round.FirstIntermission else Config.Round.Intermission, 1, -1 do
			GameState:SetAttribute("Countdown", i)
			task.wait(1)
		end
		first = false

		startRound()
		repeat
			task.wait(0.5)
		until #alivePlayers() == 0
		endRound()
	end
end

return RoundManager
