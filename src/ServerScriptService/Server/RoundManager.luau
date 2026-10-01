--!strict
-- The game loop:
--   Lobby         everyone is on the main menu, picking a night
--   Intermission  someone pressed PLAY; short countdown (others can join / vote)
--   Playing       the chosen night: build its map, monster and objective
--   Results       who made it; beating a night unlocks the next one
-- ...then everyone goes back to the menu.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage.Shared.Config)
local Maze = require(ReplicatedStorage.Shared.Maze)
local Nights = require(ReplicatedStorage.Shared.Nights)
local Exit = require(script.Parent.Exit)
local Interactables = require(script.Parent.Interactables)
local MonsterAI = require(script.Parent.MonsterAI)
local Objectives = require(script.Parent.Objectives)
local Progress = require(script.Parent.Progress)
local WorldBuilder = require(script.Parent.WorldBuilder)

local Remotes = ReplicatedStorage.Remotes
local GameState = ReplicatedStorage.GameState

type Round = {
	night: Nights.Night,
	layout: Maze.Layout,
	world: WorldBuilder.World,
	interactables: Interactables.Interactables,
	monster: MonsterAI.MonsterAI,
	exit: Exit.Exit,
	objective: Objectives.Objective,
	startedAt: number,
	spawnIndex: number,
	participants: { [Player]: boolean },
	connections: { RBXScriptConnection },
}

local RoundManager = {}

local ready: { [Player]: number } = {} -- player -> the night they picked
local status: { [Player]: string } = {} -- "alive" | "caught" | "escaped"
local looks: { [Player]: Vector3 } = {}
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

local function notify(player: Player, text: string, style: string?)
	Remotes.Notify:FireClient(player, text, style)
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

local function countReady(): number
	local n = 0
	for _ in ready do
		n += 1
	end
	return n
end

-- Most-voted night among the ready players (ties go to the earliest night).
local function chosenNight(): number
	local votes: { [number]: number } = {}
	for _, n in ready do
		votes[n] = (votes[n] or 0) + 1
	end
	local best, bestVotes = 1, 0
	for n = 1, Nights.count do
		local v = votes[n] or 0
		if v > bestVotes then
			best, bestVotes = n, v
		end
	end
	return best
end

local function applyLighting(l: Nights.Lighting)
	Lighting.Ambient = l.Ambient
	Lighting.OutdoorAmbient = Color3.new(0, 0, 0)
	Lighting.FogColor = l.FogColor
	Lighting.FogStart = l.FogStart
	Lighting.FogEnd = l.FogEnd
	Lighting.ExposureCompensation = l.Exposure
	local grade = Lighting:FindFirstChild("Monochrome")
	if grade and grade:IsA("ColorCorrectionEffect") then
		grade.Saturation = l.Saturation
		grade.Contrast = l.Contrast
		grade.Brightness = l.Brightness
		grade.TintColor = l.Tint
	end
	local bloom = Lighting:FindFirstChild("Glow")
	if bloom and bloom:IsA("BloomEffect") then
		bloom.Intensity = l.Bloom
	end
	pcall(function()
		SoundService.AmbientReverb = (Enum.ReverbType :: any)[l.Reverb]
	end)
end

local function spawnPlayer(player: Player)
	local r = round
	if not r or status[player] ~= nil then
		return
	end
	status[player] = "alive"
	r.participants[player] = true
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

-- kind: "escaped" | "survived" | "collected" | "final"
function RoundManager.escaped(player: Player, kind: string)
	if status[player] ~= "alive" then
		return
	end
	status[player] = "escaped"
	local r = round
	if r then
		r.interactables:release(player)
		r.monster:forget(player)
	end
	Remotes.Escaped:FireClient(player, kind)
	if kind == "escaped" or kind == "final" then
		notifyOthers(player, player.DisplayName .. " made it out.", "key")
	end
	task.delay(4, function()
		if status[player] == "escaped" then
			removeCharacter(player)
		end
	end)
end

local function startRound(night: Nights.Night)
	local seed = Random.new():NextInteger(1, 2 ^ 30)
	local layout = Maze.generate(seed, night.maze)
	local world = WorldBuilder.build(layout, night)
	applyLighting(night.lighting)
	local exit = Exit.new(world)

	local monster: MonsterAI.MonsterAI
	local interactables = Interactables.new(layout, world, {
		isAlive = isAlive,
		onHide = function(player: Player, locker: Interactables.Locker)
			monster:onPlayerHid(player, locker)
		end,
		onNoise = function(position: Vector3, radius: number)
			monster:hearNoise(position, radius)
		end,
	})
	monster = MonsterAI.new(layout, world, interactables, Nights.monsterParams(night), night.monsterKind, {
		getPlayers = alivePlayers,
		onCaught = RoundManager.caught,
		onAwake = function()
			GameState:SetAttribute("MonsterAwake", true)
		end,
		getLook = function(player: Player): Vector3?
			return looks[player]
		end,
		setBlink = function(on: boolean)
			GameState:SetAttribute("Blink", on)
		end,
	})

	GameState:SetAttribute("Night", night.index)
	GameState:SetAttribute("NightName", night.name)
	GameState:SetAttribute("Objective", night.objectiveText)
	GameState:SetAttribute("Progress", "")
	GameState:SetAttribute("CodeMask", "")
	GameState:SetAttribute("ExitOpen", false)
	GameState:SetAttribute("MonsterAwake", false)
	GameState:SetAttribute("Hour", 0)
	GameState:SetAttribute("Blink", false)
	GameState:SetAttribute("Result", "")

	local objective = Objectives.start({
		night = night,
		layout = layout,
		world = world,
		interactables = interactables,
		monster = monster,
		exit = exit,
		isAlive = isAlive,
		notifyAll = notifyAll,
		notify = notify,
		setProgress = function(text: string)
			GameState:SetAttribute("Progress", text)
		end,
		winAll = function(kind: string)
			for _, player in alivePlayers() do
				RoundManager.escaped(player, kind)
			end
		end,
	})

	local r: Round = {
		night = night,
		layout = layout,
		world = world,
		interactables = interactables,
		monster = monster,
		exit = exit,
		objective = objective,
		startedAt = os.clock(),
		spawnIndex = 0,
		participants = {},
		connections = {},
	}
	table.insert(r.connections, world.escapeZone.Touched:Connect(function(hit: BasePart)
		if not exit.isOpen then
			return
		end
		local character = hit:FindFirstAncestorOfClass("Model")
		local player = character and Players:GetPlayerFromCharacter(character)
		if player and isAlive(player) then
			RoundManager.escaped(player, if night.index == Nights.count then "final" else "escaped")
		end
	end))

	table.clear(status)
	round = r
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
	local won = #survivors > 0
	if won then
		-- co-op: everyone who played this night moves on
		for player in r.participants do
			if player.Parent then
				Progress.beat(player, r.night.index)
			end
		end
	end
	local result = if won then "Escaped" else "Caught"
	GameState:SetAttribute("Result", result)
	GameState:SetAttribute("Phase", "Results")
	Remotes.RoundResult:FireAllClients(result, survivors, math.floor(os.clock() - r.startedAt), r.night.index)

	task.wait(Config.Round.ResultsTime)

	for _, c in r.connections do
		c:Disconnect()
	end
	r.objective.destroy()
	r.monster:destroy()
	r.interactables:destroy()
	r.world.model:Destroy()
	round = nil
	table.clear(status)
	table.clear(ready) -- everyone goes back to the menu
	GameState:SetAttribute("ReadyCount", 0)
	for _, player in Players:GetPlayers() do
		removeCharacter(player)
		player:SetAttribute("Hiding", false)
	end
end

function RoundManager.run()
	Players.CharacterAutoLoads = false
	WorldBuilder.setupCollisionGroups()
	applyLighting(Nights.get(1).lighting)

	GameState:SetAttribute("Phase", "Lobby")
	GameState:SetAttribute("Countdown", 0)
	GameState:SetAttribute("Night", 1)
	GameState:SetAttribute("NightName", Nights.get(1).name)
	GameState:SetAttribute("ReadyCount", 0)
	GameState:SetAttribute("Progress", "")

	Players.PlayerAdded:Connect(Progress.load)
	for _, player in Players:GetPlayers() do
		task.spawn(Progress.load, player)
	end

	Remotes.Ready.OnServerEvent:Connect(function(player: Player, night: unknown)
		local wanted = if typeof(night) == "number" then math.floor(night) else 1
		local allowed = math.min(Progress.highest(player), Nights.count)
		ready[player] = math.clamp(wanted, 1, allowed)
		GameState:SetAttribute("ReadyCount", countReady())
		if round and GameState:GetAttribute("Phase") == "Playing" then
			task.spawn(spawnPlayer, player)
		end
	end)

	-- where each player's camera is looking (the Statue can't move while watched)
	Remotes.Look.OnServerEvent:Connect(function(player: Player, direction: unknown)
		if typeof(direction) == "Vector3" and direction.Magnitude > 0.5 and direction.Magnitude < 2 then
			looks[player] = direction.Unit
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
		looks[player] = nil
		GameState:SetAttribute("ReadyCount", countReady())
		local r = round
		if r then
			r.interactables:release(player)
			r.monster:forget(player)
		end
		status[player] = nil
	end)

	local first = true
	while true do
		GameState:SetAttribute("Phase", "Lobby")
		applyLighting(Nights.get(1).lighting)
		while next(ready) == nil do
			task.wait(0.25)
		end

		GameState:SetAttribute("Phase", "Intermission")
		for i = if first then Config.Round.FirstIntermission else Config.Round.Intermission, 1, -1 do
			local n = chosenNight()
			GameState:SetAttribute("Night", n)
			GameState:SetAttribute("NightName", Nights.get(n).name)
			GameState:SetAttribute("Countdown", i)
			task.wait(1)
		end
		first = false

		if next(ready) ~= nil then
			startRound(Nights.get(chosenNight()))
			repeat
				task.wait(0.5)
			until #alivePlayers() == 0
			endRound()
		end
	end
end

return RoundManager
