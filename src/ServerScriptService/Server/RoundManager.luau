--!strict
-- The game, server side. It's one place that runs as two kinds of server:
--
--   a lobby server   (the public ones you join): the lobby. When a group goes through
--                    one of its doors they're teleported to a reserved server of this
--                    same place. In Studio, where teleports don't work, the night is
--                    played right here instead, and the doors stay shut until it's over.
--   a night server   (reserved, one per group): plays the night the group chose
--                    (Playing -> Results), then sends everyone back to a lobby.
--
-- Either way a group is on its own for its night. When you're caught you get two
-- choices: TRY AGAIN (it shows how many of the group want to, like 2 / 4) or BACK TO
-- LOBBY. If the whole group tries again, the night starts over; otherwise everyone goes
-- back to the lobby.
--
-- Each player's "Where" attribute tells their client where they are: "lobby",
-- "night", or "between" (no body: a black screen, a teleport, the results).

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TeleportService = game:GetService("TeleportService")

local Config = require(ReplicatedStorage.Shared.Config)
local Curses = require(ReplicatedStorage.Shared.Curses)
local Maze = require(ReplicatedStorage.Shared.Maze)
local Monsters = require(ReplicatedStorage.Shared.Monsters)
local Nights = require(ReplicatedStorage.Shared.Nights)
local Chaos = require(script.Parent.Chaos)
local Exit = require(script.Parent.Exit)
local Interactables = require(script.Parent.Interactables)
local Lobby = require(script.Parent.Lobby)
local MonsterAI = require(script.Parent.MonsterAI)
local Objectives = require(script.Parent.Objectives)
local Progress = require(script.Parent.Progress)
local Shop = require(script.Parent.Shop)
local Throwables = require(script.Parent.Throwables)
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
	chaos: Chaos.Chaos,
	throwables: Throwables.Throwables,
	curse: Curses.Curse,
	startedAt: number,
	spawnIndex: number,
	participants: { [Player]: boolean },
	connections: { RBXScriptConnection },
}

local RoundManager = {}

local status: { [Player]: string } = {} -- "alive" | "caught" | "escaped"
local looks: { [Player]: Vector3 } = {}
local round: Round? = nil
local lobby: Lobby.Lobby? = nil
local nightBusy = false -- a group's night (and its try-again vote) is going on here

-- The group playing here and what each of them chose when they were caught.
local group: { Player } = {}
local groupSize = 0
local votes: { [Player]: string } = {} -- "again" | "lobby"
local goBack: (players: { Player }) -> () = function() end

local function setWhere(player: Player, where: string)
	player:SetAttribute("Where", where)
end

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

local function loadCharacter(player: Player): boolean
	local ok = pcall(function()
		player:LoadCharacterAsync()
	end)
	if not ok then
		-- older engines only have the (now deprecated) synchronous version
		ok = pcall(function()
			(player :: any):LoadCharacter()
		end)
	end
	return ok and player.Character ~= nil
end

local function applyLighting(l: Nights.Lighting, curse: Curses.Curse?)
	Lighting.Ambient = l.Ambient
	Lighting.OutdoorAmbient = Color3.new(0, 0, 0)
	Lighting.FogColor = l.FogColor
	Lighting.FogStart = l.FogStart
	Lighting.FogEnd = l.FogEnd
	if curse and curse.id == "fog" then
		-- real fog: pale, close, but not pitch black (or the dark nights are unplayable)
		Lighting.FogColor = l.FogColor:Lerp(Color3.fromRGB(78, 78, 82), 0.35)
		Lighting.FogStart = 4
		Lighting.FogEnd = math.min(l.FogEnd * 0.4, 42)
	end
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
	player:SetAttribute("Bottles", 0)
	setWhere(player, "night")
	local ok = loadCharacter(player)
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
			setWhere(player, "between")
			removeCharacter(player)
		end
		-- then the choice (unless someone already got out: that night's won). The night may
		-- already be over by now, if you were the last one.
		local won = false
		for _, s in status do
			if s == "escaped" then
				won = true
			end
		end
		if table.find(group, player) and votes[player] == nil and player.Parent and not won then
			Remotes.Retry:FireClient(player, "open", RoundManager.againCount(), groupSize)
		end
	end)
end

-- A bought revive: someone caught tonight gets back up where the night started, if the
-- night's still going.
function RoundManager.revive(player: Player): boolean
	if not round or status[player] ~= "caught" or GameState:GetAttribute("Phase") ~= "Playing" then
		return false
	end
	status[player] = nil
	votes[player] = nil
	Remotes.Retry:FireClient(player, "close")
	task.spawn(spawnPlayer, player)
	return true
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
			setWhere(player, "between")
			removeCharacter(player)
		end
	end)
end

local function startRound(night: Nights.Night, players: { Player })
	local seed = Random.new():NextInteger(1, 2 ^ 30)
	local layout = Maze.generate(seed, night.maze)
	local world = WorldBuilder.build(layout, night)
	local curse = Curses.roll(night.monsterKind, Random.new(seed + 5))
	applyLighting(night.lighting, curse)
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
	local params = Nights.monsterParams(night)
	if night.monsterKind == "Statue" then
		params.Variant = Monsters.STATUE_VARIANTS[Random.new(seed):NextInteger(1, #Monsters.STATUE_VARIANTS)]
	end
	monster = MonsterAI.new(layout, world, interactables, params, night.monsterKind, {
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
	GameState:SetAttribute("Done", 0)
	GameState:SetAttribute("Goal", 0)
	GameState:SetAttribute("CodeMask", "")
	GameState:SetAttribute("ExitOpen", false)
	GameState:SetAttribute("MonsterAwake", false)
	GameState:SetAttribute("Hour", 0)
	GameState:SetAttribute("Blink", false)
	GameState:SetAttribute("Result", "")
	GameState:SetAttribute("Curse", curse.id)
	GameState:SetAttribute("Blackout", false)
	GameState:SetAttribute("Rage", false)

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
		setProgress = function(done: number, goal: number)
			GameState:SetAttribute("Goal", goal)
			GameState:SetAttribute("Done", done)
		end,
		winAll = function(kind: string)
			for _, player in alivePlayers() do
				RoundManager.escaped(player, kind)
			end
		end,
	})

	local throwables = Throwables.new(layout, world, {
		isAlive = isAlive,
		onNoise = function(position: Vector3, radius: number)
			monster:hearNoise(position, radius)
		end,
	})
	local chaos = Chaos.start({
		night = night,
		layout = layout,
		world = world,
		interactables = interactables,
		monster = monster,
		curse = curse,
		getPlayers = alivePlayers,
		isAlive = isAlive,
		notifyAll = notifyAll,
	})

	local r: Round = {
		night = night,
		layout = layout,
		world = world,
		interactables = interactables,
		monster = monster,
		exit = exit,
		objective = objective,
		chaos = chaos,
		throwables = throwables,
		curse = curse,
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
	for _, player in players do
		task.spawn(spawnPlayer, player)
	end
	monster:start()
end

-- Ends the night and clears it away; returns whether anyone made it out.
local function endRound(): boolean
	local r = round
	if not r then
		return false
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
	GameState:SetAttribute("Result", if won then "Escaped" else "Caught")
	GameState:SetAttribute("Phase", "Results")
	if won then
		task.wait(Config.Round.ResultsTime) -- let the ending play out
	end

	for _, c in r.connections do
		c:Disconnect()
	end
	r.objective.destroy()
	r.chaos.destroy()
	r.throwables.destroy()
	r.monster:destroy()
	r.interactables:destroy()
	r.world.model:Destroy()
	round = nil
	table.clear(status)
	for player in r.participants do
		if player.Parent then
			removeCharacter(player)
			setWhere(player, "between")
			player:SetAttribute("Hiding", false)
			player:SetAttribute("Bottles", 0)
		end
	end
	GameState:SetAttribute("Curse", "")
	return won
end

-- The try-again vote ----------------------------------------------------------------

function RoundManager.againCount(): number
	local n = 0
	for p, v in votes do
		if v == "again" and p.Parent then
			n += 1
		end
	end
	return n
end

local function present(players: { Player }): { Player }
	local out = {}
	for _, p in players do
		if p.Parent then
			table.insert(out, p)
		end
	end
	return out
end

local function tell(players: { Player }, ...: any)
	for _, p in present(players) do
		Remotes.Retry:FireClient(p, ...)
	end
end

-- The group's night, again and again for as long as all of them want to try again.
-- `back` sends players to a lobby (a teleport home, or a respawn in this one).
local function playNight(players: { Player }, nightIndex: number, back: (players: { Player }) -> ())
	nightBusy = true
	group = table.clone(players)
	groupSize = #players
	goBack = back
	while true do
		table.clear(votes)
		startRound(Nights.get(nightIndex), present(group))
		repeat
			repeat
				task.wait(0.5)
			until #alivePlayers() == 0
			-- the last of you was just caught: give them a moment to buy a revive
			local revived = false
			local won = false
			for _, s in status do
				won = won or s == "escaped"
			end
			if Shop.canRevive() and not won then
				local deadline = os.clock() + Config.Shop.ReviveWait
				repeat
					task.wait(0.25)
					revived = #alivePlayers() > 0
				until revived or os.clock() > deadline
			end
		until not revived
		if endRound() then
			tell(group, "close")
			break
		end
		-- caught, all of them: wait for everyone's choice (a minute at most)
		local deadline = os.clock() + 60
		repeat
			task.wait(0.25)
		until RoundManager.againCount() >= groupSize or #present(group) < groupSize or os.clock() > deadline
		tell(group, "close")
		if RoundManager.againCount() < groupSize then
			break
		end
	end
	local remaining = present(group)
	table.clear(group)
	table.clear(votes)
	groupSize = 0
	back(remaining)
	nightBusy = false
end

-- Lobby -----------------------------------------------------------------------------

local function spawnInLobby(player: Player)
	local l = lobby
	if not l or player.Parent == nil or status[player] == "alive" then
		return
	end
	setWhere(player, "lobby")
	player:SetAttribute("Flashlight", false)
	if not loadCharacter(player) then
		return
	end
	local character = player.Character :: Model
	character:PivotTo(l.spawnCFrame())
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Died:Connect(function()
			task.wait(3)
			if player:GetAttribute("Where") == "lobby" and player.Character == character then
				spawnInLobby(player)
			end
		end)
	end
end

local function teleportsWork(): boolean
	return not RunService:IsStudio() and game.PlaceId ~= 0
end

-- Send a group to a reserved server of this place to play `night`.
local function sendToNight(group: { Player }, night: number): boolean
	local ok, err = pcall(function()
		local code = TeleportService:ReserveServer(game.PlaceId)
		local options = Instance.new("TeleportOptions")
		options.ReservedServerAccessCode = code
		options:SetTeleportData({ night = night, count = #group })
		TeleportService:TeleportAsync(game.PlaceId, group, options)
	end)
	if not ok then
		warn("ACHROMA: couldn't reach a night server (" .. tostring(err) .. "); playing it here")
	end
	return ok
end

-- Studio (or a failed teleport): play the night in this server, then back to the lobby.
local function playHere(players: { Player }, night: number)
	if nightBusy then
		for _, p in players do
			spawnInLobby(p)
		end
		return
	end
	playNight(players, night, function(back: { Player })
		for _, p in back do
			task.spawn(spawnInLobby, p)
		end
	end)
	applyLighting(Lobby.LIGHTING)
	GameState:SetAttribute("Phase", "Lobby")
	GameState:SetAttribute("Night", 1)
end

local function runLobby()
	GameState:SetAttribute("Phase", "Lobby")
	applyLighting(Lobby.LIGHTING)
	lobby = Lobby.new({
		highest = Progress.allowed,
		isOpen = function(): boolean
			return not nightBusy
		end,
		launch = function(group: { Player }, night: number)
			for _, p in group do
				setWhere(p, "between")
			end
			if not (teleportsWork() and sendToNight(group, night)) then
				task.spawn(playHere, group, night)
			end
		end,
	})
	-- a teleport that fails after it started: back to the lobby
	TeleportService.TeleportInitFailed:Connect(function(player: Player)
		if player:GetAttribute("Where") == "between" and status[player] == nil then
			spawnInLobby(player)
		end
	end)
	local function join(player: Player)
		Progress.load(player)
		spawnInLobby(player)
	end
	Players.PlayerAdded:Connect(join)
	for _, player in Players:GetPlayers() do
		task.spawn(join, player)
	end
end

-- Night server --------------------------------------------------------------------------

-- Everyone back to a (public) lobby server.
local function sendHome(players: { Player })
	for attempt = 1, 3 do
		local ok = pcall(function()
			TeleportService:TeleportAsync(game.PlaceId, players)
		end)
		if ok then
			return
		end
		task.wait(2 * attempt)
	end
end

local function runNightServer()
	GameState:SetAttribute("Phase", "Waiting")
	local planned: number? = nil
	local expected = 1
	local firstArrival: number? = nil
	local function join(player: Player)
		setWhere(player, "between")
		local ok, data = pcall(function()
			return player:GetJoinData().TeleportData
		end)
		if ok and typeof(data) == "table" then
			local n = tonumber((data :: any).night)
			if n and not planned then
				planned = n
				-- so the black screen can already say which night it is
				GameState:SetAttribute("Night", math.clamp(math.floor(n), 1, Nights.count))
			end
			expected = math.max(expected, tonumber((data :: any).count) or 1)
		end
		firstArrival = firstArrival or os.clock()
		Progress.load(player)
		if round then
			spawnPlayer(player) -- late, but the night's still going
		end
	end
	Players.PlayerAdded:Connect(join)
	for _, player in Players:GetPlayers() do
		task.spawn(join, player)
	end

	-- wait for the whole group (or 20 seconds after the first of them)
	repeat
		task.wait(0.25)
	until firstArrival and (#Players:GetPlayers() >= expected or os.clock() - (firstArrival :: number) > 20)
	task.wait(0.5)
	-- nobody gets a night they couldn't have chosen
	local allowed = 1
	for _, player in Players:GetPlayers() do
		allowed = math.max(allowed, Progress.allowed(player))
	end
	local night = math.clamp(math.floor(planned or 1), 1, allowed)
	GameState:SetAttribute("Night", night)
	playNight(Players:GetPlayers(), night, sendHome)
	sendHome(Players:GetPlayers())
	-- anyone who still turns up here goes home too
	Players.PlayerAdded:Connect(function(player: Player)
		sendHome({ player })
	end)
end

function RoundManager.run()
	Shop.start({
		revive = RoundManager.revive,
		isAlive = function(player: Player): boolean
			return status[player] == "alive"
		end,
	})
	Players.CharacterAutoLoads = false
	WorldBuilder.setupCollisionGroups()

	GameState:SetAttribute("Phase", "Lobby")
	GameState:SetAttribute("Night", 1)
	GameState:SetAttribute("NightName", Nights.get(1).name)
	GameState:SetAttribute("Done", 0)
	GameState:SetAttribute("Goal", 0)

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
				light.Shadows = true
				light.Parent = head
			end
			local r = round
			local beam = Nights.flashlight(if r then r.night else Nights.get(1))
			light.Angle = beam.angle + 4
			light.Range = beam.range * 0.85
			light.Brightness = beam.brightness * 0.8
			light.Enabled = on
		end
	end)

	-- what a caught player chose: TRY AGAIN, or BACK TO LOBBY (which leaves right away)
	Remotes.Retry.OnServerEvent:Connect(function(player: Player, choice: unknown)
		if not table.find(group, player) or status[player] == "alive" or votes[player] ~= nil then
			return
		end
		if choice == "again" then
			votes[player] = "again"
			tell(group, "count", RoundManager.againCount(), groupSize)
		elseif choice == "lobby" then
			votes[player] = "lobby"
			table.remove(group, table.find(group, player) :: number)
			Remotes.Retry:FireClient(player, "close")
			goBack({ player })
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		looks[player] = nil
		local r = round
		if r then
			r.interactables:release(player)
			r.monster:forget(player)
		end
		status[player] = nil
	end)

	-- a reserved server is a night server; anything else is a lobby
	if game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0 then
		runNightServer()
	else
		runLobby()
	end
end

return RoundManager
