-- Runs the real server scripts (maps, monsters, objectives) inside a mocked Roblox
-- under Lune, and plays out scenarios for all five nights with fake players:
--   lune run tests/sim.spec.luau
local roblox = require("@lune/roblox")
local Engine = require("./mock/engine")

local Vector3 = roblox.Vector3
local CFrame = Engine.CFrame

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

local function boot()
	Engine.time = 0
	Engine.delayed = {}
	Engine.sleeping = {}
	Engine.errors = {}
	local shared = Engine.folderFromDir("Shared", "src/ReplicatedStorage/Shared")
	local server = Engine.folderFromDir("Server", "src/ServerScriptService/Server")
	local game, workspace = Engine.makeGame(server, shared, nil, REMOTES)
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
	}
	local require, runScript = Engine.makeLoader(globals)
	local rs = game:GetService("ReplicatedStorage")
	local sss = game:GetService("ServerScriptService")
	local SoundIds = require(rs.Shared.SoundIds)
	SoundIds.SFX = 111
	SoundIds.Ambience = 222
	SoundIds.MusicBox = 333
	local mods = {
		Maze = require(rs.Shared.Maze),
		Nights = require(rs.Shared.Nights),
		Monsters = require(rs.Shared.Monsters),
		WorldBuilder = require(sss.Server.WorldBuilder),
		Interactables = require(sss.Server.Interactables),
		Exit = require(sss.Server.Exit),
		MonsterAI = require(sss.Server.MonsterAI),
		Objectives = require(sss.Server.Objectives),
		Curses = require(rs.Shared.Curses),
		Chaos = require(sss.Server.Chaos),
		Throwables = require(sss.Server.Throwables),
		Lobby = require(sss.Server.Lobby),
		require = require,
		runScript = runScript,
		server = server,
	}
	Engine.Maze = mods.Maze
	return game, workspace, mods
end

local function makePlayer(game, name: string, userId: number)
	local players = game:GetService("Players")
	local player = Engine.newInstance("Player", name)
	player.DisplayName = name
	player.UserId = userId
	player.Character = Engine.makeCharacter(player)
	player.Parent = players
	table.insert(rawget(players, "_list"), player)
	return player
end

local function placePlayer(player, position)
	local cf = CFrame.new(position.X, 3, position.Z)
	player.Character.HumanoidRootPart.CFrame = cf
	player.Character.Head.CFrame = cf * CFrame.new(0, 1.5, 0)
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local wallViolations = 0
local function tick(s, dt: number)
	Engine.time += dt
	Engine.runScheduled()
	s.game:GetService("RunService").Heartbeat:Fire(dt)
	local monster = s.monster
	local root = monster.rig.root
	local humanoid = monster.humanoid
	local target = rawget(humanoid, "_moveTarget")
	if not root.Anchored and target then
		local to = flat(target - root.Position)
		if to.Magnitude > 0.05 then
			local step = math.min(to.Magnitude, humanoid.WalkSpeed * dt)
			local from = root.Position
			local nextPos = from + to.Unit * step
			local C = Engine.layout.cellSize
			local ax, az = math.floor(from.X / C), math.floor(from.Z / C)
			local bx, bz = math.floor(nextPos.X / C), math.floor(nextPos.Z / C)
			if ax >= 0 and az >= 0 and bx >= 0 and bz >= 0 and not Engine.canCross(ax, az, bx, bz) then
				wallViolations += 1
			end
			monster.rig.model:PivotTo(CFrame.lookAt(nextPos, nextPos + to.Unit))
			root.AssemblyLinearVelocity = to.Unit * (step / dt)
		else
			root.AssemblyLinearVelocity = Vector3.zero
		end
	else
		root.AssemblyLinearVelocity = Vector3.zero
	end
end

local function run(s, seconds: number, until_: (() -> boolean)?): (boolean, number)
	local dt = 0.05
	local t = 0
	while t < seconds do
		tick(s, dt)
		t += dt
		if until_ and until_() then
			return true, t
		end
	end
	return false, t
end

local function setup(nightIndex: number, seed: number, startMonster: boolean?)
	local game, workspace, mods = boot()
	local night = mods.Nights.get(nightIndex)
	local layout = mods.Maze.generate(seed, night.maze)
	Engine.layout = layout
	local world = mods.WorldBuilder.build(layout, night)
	local exit = mods.Exit.new(world)
	local s: any = {
		game = game,
		workspace = workspace,
		mods = mods,
		night = night,
		layout = layout,
		world = world,
		exit = exit,
		alive = {},
		caught = {},
		wins = {},
		looks = {},
		blinks = 0,
		progress = "",
	}
	local function isAlive(p)
		return table.find(s.alive, p) ~= nil
	end
	local function remove(p)
		local i = table.find(s.alive, p)
		if i then
			table.remove(s.alive, i)
		end
	end
	s.interactables = mods.Interactables.new(layout, world, {
		isAlive = isAlive,
		onHide = function(p, locker)
			s.monster:onPlayerHid(p, locker)
		end,
		onNoise = function(pos, radius)
			s.monster:hearNoise(pos, radius)
		end,
	})
	s.monster = mods.MonsterAI.new(layout, world, s.interactables, mods.Nights.monsterParams(night), night.monsterKind, {
		getPlayers = function()
			return table.clone(s.alive)
		end,
		onCaught = function(p)
			table.insert(s.caught, p)
			remove(p)
		end,
		onAwake = function() end,
		getLook = function(p)
			return s.looks[p]
		end,
		setBlink = function(on)
			if on then
				s.blinks += 1
			end
		end,
	})
	s.objective = mods.Objectives.start({
		night = night,
		layout = layout,
		world = world,
		interactables = s.interactables,
		monster = s.monster,
		exit = exit,
		isAlive = isAlive,
		notifyAll = function() end,
		notify = function() end,
		setProgress = function(done, goal)
			s.progress = string.format("%d/%d", done, goal)
		end,
		winAll = function(kind)
			for _, p in table.clone(s.alive) do
				table.insert(s.wins, kind)
				remove(p)
			end
		end,
	})
	world.escapeZone.Touched:Connect(function(hit)
		if exit.isOpen then
			local character = hit:FindFirstAncestorOfClass("Model")
			local player = character and game:GetService("Players"):GetPlayerFromCharacter(character)
			if player and isAlive(player) then
				table.insert(s.wins, "escaped")
				remove(player)
			end
		end
	end)
	if startMonster ~= false then
		s.monster:start()
	end
	return s
end

-- The curse + random events, wired up like RoundManager does it.
local function startChaos(s, curseId: string)
	s.notes = {}
	s.chaos = s.mods.Chaos.start({
		night = s.night,
		layout = s.layout,
		world = s.world,
		interactables = s.interactables,
		monster = s.monster,
		curse = s.mods.Curses.get(curseId),
		getPlayers = function()
			return table.clone(s.alive)
		end,
		isAlive = function(p)
			return table.find(s.alive, p) ~= nil
		end,
		notifyAll = function(text)
			table.insert(s.notes, text)
		end,
	})
	return s.chaos
end

local function cellCenter(layout, c)
	return Vector3.new((c.x + 0.5) * layout.cellSize, 0, (c.z + 0.5) * layout.cellSize)
end

local function prompts(root, objectText: string)
	local list = {}
	for _, d in root:GetDescendants() do
		if d.ClassName == "ProximityPrompt" and d.ObjectText == objectText then
			table.insert(list, d)
		end
	end
	return list
end

-- Put the player two cells in front of the monster down a straight corridor, facing it.
local function faceOff(s, player): boolean
	local Maze = s.mods.Maze
	local mroot = s.monster.rig.root
	local mc = Maze.cellOf(s.layout, mroot.Position.X, mroot.Position.Z)
	for _, d in Maze.DIRS do
		local runCells = Maze.straightRun(s.layout, mc, d, 3)
		if #runCells >= 2 then
			local target = cellCenter(s.layout, runCells[2])
			placePlayer(player, target)
			s.monster.rig.model:PivotTo(CFrame.lookAt(mroot.Position, Vector3.new(target.X, mroot.Position.Y, target.Z)))
			player.Character.HumanoidRootPart.CFrame = CFrame.lookAt(player.Character.HumanoidRootPart.Position, Vector3.new(mroot.Position.X, 3, mroot.Position.Z))
			return true
		end
	end
	return false
end

---------------------------------------------------------------------------
print("Every night builds")
for n = 1, 5 do
	local s = setup(n, 4242 + n, false)
	local parts, lights, prompts_ = 0, 0, 0
	for _, d in s.world.model:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
		elseif d.ClassName == "PointLight" then
			lights += 1
		elseif d.ClassName == "ProximityPrompt" then
			prompts_ += 1
		end
	end
	local rigParts = 0
	for _, d in s.monster.rig.model:GetDescendants() do
		if d:IsA("BasePart") then
			rigParts += 1
		end
	end
	print(string.format("  %-20s %5d parts  %3d lights  %3d prompts  monster %s (%d parts)", s.night.name, parts, lights, prompts_, s.night.monsterKind, rigParts))
	check(parts > 300 and parts < 4500, s.night.id .. ": part count is sane")
	check(lights >= 8 and lights <= 70, s.night.id .. ": light count is sane")
	check(rigParts >= 20, s.night.id .. ": monster built")
	check(#s.world.spawnPoints >= 4, s.night.id .. ": spawn points")
	check(#s.interactables.lockers == #s.layout.lockers, s.night.id .. ": lockers built")
	check(#s.exit.leaves == 2 or s.exit.membrane ~= nil, s.night.id .. ": exit built")
	check(#Engine.errors == 0, s.night.id .. ": no script errors")
end

---------------------------------------------------------------------------
print("Objectives can be completed")
do
	-- Night 1: survive until 6 AM
	local s = setup(1, 11, false)
	local p = makePlayer(s.game, "Ares", 1)
	table.insert(s.alive, p)
	local won = run(s, s.night.surviveSeconds + 2, function()
		return #s.wins > 0
	end)
	check(won and s.wins[1] == "survived", "night 1: reaching 6 AM wins (" .. s.progress .. ")")

	-- Night 2: keys -> code -> exit
	s = setup(2, 22, false)
	p = makePlayer(s.game, "Ares", 1)
	table.insert(s.alive, p)
	for _, prompt in prompts(s.world.model, "Key") do
		prompt.Triggered:Fire(p)
	end
	check(s.progress == "4/5", "night 2: 4 keys found (" .. s.progress .. ")")
	local keypad = s.world.model:FindFirstChild("Keypad", true)
	placePlayer(p, keypad.Position + Vector3.new(0, 0, 4))
	Engine.time += 1
	s.game:GetService("ReplicatedStorage").Remotes.SubmitCode.OnServerEvent:Fire(p, s.layout.code)
	check(s.exit.isOpen, "night 2: the right code opens the exit")
	s.world.escapeZone.Touched:Fire(p.Character.HumanoidRootPart)
	check(s.wins[1] == "escaped", "night 2: escaping through the exit")

	-- Night 3: generators power the lamps and the lift
	s = setup(3, 33, false)
	p = makePlayer(s.game, "Ares", 1)
	table.insert(s.alive, p)
	local function litLamps()
		local n = 0
		for _, lamp in s.world.lamps do
			if lamp.light.Enabled then
				n += 1
			end
		end
		return n
	end
	local before = litLamps()
	for _, prompt in prompts(s.world.model, "Generator") do
		prompt.Triggered:Fire(p)
	end
	run(s, 3)
	check(litLamps() > before + 5, string.format("night 3: generators turn the lights on (%d -> %d)", before, litLamps()))
	check(s.exit.isOpen, "night 3: the lift opens after 3 generators")

	-- Night 4: photographs
	s = setup(4, 44, false)
	p = makePlayer(s.game, "Ares", 1)
	table.insert(s.alive, p)
	local photos = prompts(s.world.model, "Photograph")
	check(#photos == 6, "night 4: 6 photographs placed")
	for _, prompt in photos do
		prompt.Triggered:Fire(p)
	end
	check(s.wins[1] == "collected", "night 4: collecting all photographs wins")

	-- Night 5: hearts -> portal
	s = setup(5, 55, false)
	p = makePlayer(s.game, "Ares", 1)
	table.insert(s.alive, p)
	local heartPrompts = prompts(s.world.model, "Heart")
	check(#heartPrompts == 3, "night 5: 3 hearts placed")
	heartPrompts[1].Triggered:Fire(p)
	check(s.monster.awake and s.monster.state == "Chase", "night 5: breaking a heart sends it after you")
	for i = 2, #heartPrompts do
		heartPrompts[i].Triggered:Fire(p)
	end
	run(s, 1)
	check(s.exit.isOpen and s.exit.membrane.Transparency > 0.9, "night 5: the portal opens after 3 hearts")
	check(#Engine.errors == 0, "no script errors during objectives")
end

---------------------------------------------------------------------------
print("The Hollow hunts down a player standing still (night 1)")
do
	local found = 0
	for seed = 1, 5 do
		local s = setup(1, seed * 7777)
		local p = makePlayer(s.game, "Ares", 1)
		table.insert(s.alive, p)
		placePlayer(p, cellCenter(s.layout, s.layout.deadEnds[1] or s.layout.monsterSpawn))
		s.monster:awaken()
		local ok, t = run(s, 300, function()
			return #s.caught > 0
		end)
		if ok then
			found += 1
		end
		print(string.format("  seed %d: %s after %.0fs", seed * 7777, if ok then "caught" else "not caught", t))
	end
	check(found >= 4, string.format("caught %d/5 within 5 minutes", found))
	check(wallViolations == 0, "never walked through a wall (" .. wallViolations .. ")")
end

---------------------------------------------------------------------------
print("The Crawler lunges (night 2)")
do
	local s = setup(2, 202)
	local p = makePlayer(s.game, "Ares", 1)
	table.insert(s.alive, p)
	s.monster:awaken()
	check(faceOff(s, p), "set up a face-off")
	local lunged = run(s, 6, function()
		return Engine.time < s.monster.lungeUntil
	end)
	check(lunged, "it lunges when it gets close")
end

---------------------------------------------------------------------------
print("The Listener is blind but hears everything (night 3)")
do
	local s = setup(3, 303)
	local p = makePlayer(s.game, "Ares", 1)
	table.insert(s.alive, p)
	s.monster:awaken()
	-- stand still, light on, a few cells away down its path
	local Maze = s.mods.Maze
	local mroot = s.monster.rig.root
	local mc = Maze.cellOf(s.layout, mroot.Position.X, mroot.Position.Z)
	local dist = Maze.distances(s.layout, mc)
	local spot = s.layout.entrance
	for z = 0, s.layout.depth - 1 do
		for x = 0, s.layout.width - 1 do
			local d = dist[Maze.key(x, z)] or 0
			if d >= 4 and d <= 6 and not Maze.isHub(s.layout, x, z) then
				spot = { x = x, z = z }
			end
		end
	end
	placePlayer(p, cellCenter(s.layout, spot))
	p:SetAttribute("Flashlight", true)
	local noticed = run(s, 3, function()
		return s.monster.state == "Chase" or s.monster.state == "Investigate"
	end)
	check(not noticed, "it doesn't notice a silent player (even with a light on)")
	-- now sprint on the spot
	p.Character.HumanoidRootPart.AssemblyLinearVelocity = Vector3.new(18, 0, 0)
	local reacted = run(s, 1, function()
		return s.monster.state == "Chase" or s.monster.state == "Investigate"
	end)
	check(reacted, "it hears the player sprint")
	local got = run(s, 25, function()
		return #s.caught > 0
	end)
	check(got, "and follows the sound all the way to them")
end

---------------------------------------------------------------------------
print("The Statue only moves when nobody is looking (night 4)")
do
	local s = setup(4, 404)
	local p = makePlayer(s.game, "Ares", 1)
	table.insert(s.alive, p)
	run(s, 0.2)
	s.monster:awaken()
	local mroot = s.monster.rig.root
	-- stand 3 cells away in the open hall
	local Maze = s.mods.Maze
	local mc = Maze.cellOf(s.layout, mroot.Position.X, mroot.Position.Z)
	local spot = nil
	for _, d in Maze.DIRS do
		local runCells = Maze.straightRun(s.layout, mc, d, 3)
		if #runCells >= 2 then
			spot = runCells[#runCells]
			break
		end
	end
	check(spot ~= nil, "found a line of sight")
	placePlayer(p, cellCenter(s.layout, spot))
	local head = p.Character.Head
	s.looks[p] = (s.monster.rig.head.Position - head.Position).Unit
	for _ = 1, 10 do
		tick(s, 0.05)
		s.looks[p] = (s.monster.rig.head.Position - head.Position).Unit
	end
	s.monster.nextBlink = Engine.time + 100 -- no blinking during this check
	local start = mroot.Position
	for _ = 1, 60 do
		tick(s, 0.05)
		s.looks[p] = (s.monster.rig.head.Position - head.Position).Unit
	end
	check(s.monster.state == "Frozen", "it freezes while watched")
	check((mroot.Position - start).Magnitude < 0.5, "it doesn't move while watched")
	-- look away
	s.looks[p] = -s.looks[p]
	local caught = run(s, 20, function()
		return #s.caught > 0
	end)
	check(caught, "the moment you look away, it gets you")
	local blinked = s.blinks
	local s2 = setup(4, 405)
	local p2 = makePlayer(s2.game, "Ares", 1)
	table.insert(s2.alive, p2)
	placePlayer(p2, cellCenter(s2.layout, s2.layout.entrance))
	s2.looks[p2] = Vector3.new(0, 0, 1)
	run(s2, 40)
	check(s2.blinks + blinked >= 1, "the lights blink every so often (" .. s2.blinks .. " blinks in 40s)")
end

---------------------------------------------------------------------------
print("The Amalgam smells players hiding nearby (night 5)")
do
	local s = setup(5, 505)
	local p = makePlayer(s.game, "Ares", 1)
	table.insert(s.alive, p)
	s.monster:awaken()
	local locker = s.interactables.lockers[1]
	-- the monster wanders right past the locker
	s.monster.rig.model:PivotTo(CFrame.new(locker.outside.Position.X, s.monster.rig.rootHeight, locker.outside.Position.Z) * CFrame.new(0, 0, 6))
	placePlayer(p, locker.outside.Position)
	s.interactables:hide(p, locker)
	check(p:GetAttribute("Hiding") == true, "player hid")
	check(s.monster.state == "HuntLocker", "it smelled them")
	local pulled = run(s, 20, function()
		return #s.caught > 0
	end)
	check(pulled, "and dragged them out")
end

---------------------------------------------------------------------------
print("A hidden, unseen player survives (night 1)")
do
	local s = setup(1, 2024)
	local p = makePlayer(s.game, "Ares", 1)
	table.insert(s.alive, p)
	s.monster:awaken()
	local locker = s.interactables.lockers[#s.interactables.lockers]
	placePlayer(p, locker.outside.Position)
	s.interactables:hide(p, locker)
	local bad = run(s, 150, function()
		return #s.caught > 0 or s.monster.state == "HuntLocker"
	end)
	check(not bad, "survived 150s in a locker")
	s.interactables:leave(p, false)
	check(p:GetAttribute("Hiding") == false and not p.Character.HumanoidRootPart.Anchored, "leaving the locker frees the player")
end

---------------------------------------------------------------------------
print("Curses")
do
	local _, _, mods = boot()
	for n = 1, 5 do
		local night = mods.Nights.get(n)
		local seen, kinds = {}, 0
		for seed = 1, 80 do
			local c = mods.Curses.roll(night.monsterKind, Engine.Random.new(seed * 104729 + 7))
			if not seen[c.id] then
				seen[c.id] = true
				kinds += 1
			end
		end
		check(kinds >= 5, string.format("night %d rolls different curses (%d kinds)", n, kinds))
		if night.monsterKind == "Statue" then
			check(not seen.hunted, "the Statue never gets HUNTED (it already knows where you are)")
		end
	end
	local saint = mods.Monsters.build("Statue", { variant = "Saint" })
	local mourner = mods.Monsters.build("Statue", {})
	check(saint.model:GetAttribute("Variant") == "Saint" and mourner.model:GetAttribute("Variant") == "Mourner", "the Statue comes as the Mourner or the Saint")
end

---------------------------------------------------------------------------
print("Shifting walls move, but never cut anything off")
for n = 1, 5 do
	local s = setup(n, 900 + n)
	local Maze = s.mods.Maze
	local p = makePlayer(s.game, "Ares", 1)
	table.insert(s.alive, p)
	placePlayer(p, cellCenter(s.layout, s.layout.entrance))
	local chaos = startChaos(s, "shifting")
	local walls = 0
	for _, d in s.world.model.Chaos:GetChildren() do
		if d.Name == "ShiftingWall" then
			walls += 1
		end
	end
	local before = table.clone(s.layout.edges)
	local allReachable, everRaised = true, 0
	for _ = 1, 12 do
		chaos.shift()
		local raised = 0
		for k, v in s.layout.edges do
			if v == "wall" and before[k] ~= "wall" then
				raised += 1
			end
		end
		everRaised = math.max(everRaised, raised)
		local count = 0
		for _ in Maze.distances(s.layout, s.layout.entrance) do
			count += 1
		end
		allReachable = allReachable and count == s.layout.width * s.layout.depth
	end
	check(walls >= 6 and everRaised >= 3, string.format("night %d: %d moving walls, up to %d raised at once", n, walls, everRaised))
	check(allReachable, string.format("night %d: every room stays reachable after 12 shifts", n))
	-- and the monster still never walks through one while they move around it
	local violations = wallViolations
	s.monster:awaken()
	placePlayer(p, cellCenter(s.layout, s.layout.deadEnds[1] or s.layout.monsterSpawn))
	run(s, 120)
	check(wallViolations == violations, string.format("night %d: the monster respects the moving walls (%d violations)", n, wallViolations - violations))
	chaos.destroy()
	check(#Engine.errors == 0, "no script errors (" .. #Engine.errors .. ")")
end

---------------------------------------------------------------------------
print("Curses and random events")
do
	local s = setup(2, 4242)
	local p = makePlayer(s.game, "Ares", 1)
	table.insert(s.alive, p)
	placePlayer(p, cellCenter(s.layout, s.layout.entrance))
	local lamps, dead = 0, 0
	startChaos(s, "blackout")
	for _, lamp in s.world.lamps do
		if lamp.cell then
			lamps += 1
			if not lamp.light.Enabled and lamp.bulb:GetAttribute("Dead") == true then
				dead += 1
			end
		end
	end
	check(lamps > 0 and dead / lamps > 0.5 and dead < lamps, string.format("BLACKOUT kills most lamps (%d/%d)", dead, lamps))
	s.chaos.destroy()

	s = setup(1, 4243)
	p = makePlayer(s.game, "Ares", 1)
	table.insert(s.alive, p)
	placePlayer(p, cellCenter(s.layout, s.layout.entrance))
	startChaos(s, "silent")
	check(s.monster.silent and s.monster.rig.model:GetAttribute("Silent") == true, "DEAD SILENCE mutes the monster")
	local GameState = s.game:GetService("ReplicatedStorage").GameState

	check(s.chaos.event("blackout") and GameState:GetAttribute("Blackout") == true, "power failure: the lights go out")
	run(s, 13)
	check(GameState:GetAttribute("Blackout") == false, "...and come back")

	check(s.chaos.event("phone"), "a phone starts ringing")
	local phone = prompts(s.world.model.Chaos, "Phone")
	check(#phone == 1 and phone[1].Enabled, "you can answer it")
	phone[1].Triggered:Fire(p)
	check(not phone[1].Enabled, "answering hangs it up")
	check(s.chaos.event("phone"), "another call")
	phone = prompts(s.world.model.Chaos, "Phone")
	local ringing = phone[#phone]
	local heard = false
	local hear = s.monster.hearNoise
	s.monster.hearNoise = function(self, pos, radius)
		if radius >= 200 then
			heard = true
		end
		return hear(self, pos, radius)
	end
	run(s, 21)
	s.monster.hearNoise = hear
	check(not ringing.Enabled and heard, "nobody picked up, so it went to see who was calling")

	local closed = 0
	for _, door in s.interactables.doors do
		s.interactables:setDoor(door, true, false)
	end
	run(s, 1)
	check(s.chaos.event("slam"), "every door slams shut")
	for _, door in s.interactables.doors do
		if not door.isOpen then
			closed += 1
		end
	end
	check(#s.interactables.doors > 0 and closed == #s.interactables.doors, string.format("all %d doors are closed", closed))
	check(s.chaos.event("falseChase"), "a fake chase plays for someone")

	GameState:SetAttribute("ExitOpen", true)
	run(s, 2)
	check(GameState:GetAttribute("Rage") == true and s.monster.state == "Chase", "the exit opening sends it into a RAGE (" .. tostring(s.monster.state) .. ")")
	s.chaos.destroy()
	GameState:SetAttribute("ExitOpen", false)
	check(GameState:GetAttribute("Rage") == false and GameState:GetAttribute("Blackout") == false, "the round ending clears it all")
	check(#Engine.errors == 0, "no script errors (" .. #Engine.errors .. ")")
end

---------------------------------------------------------------------------
print("Bottles: pick them up, throw them, the monster goes to look")
do
	local s = setup(3, 3131)
	local p = makePlayer(s.game, "Ares", 1)
	table.insert(s.alive, p)
	local throwables = s.mods.Throwables.new(s.layout, s.world, {
		isAlive = function(pl)
			return table.find(s.alive, pl) ~= nil
		end,
		onNoise = function(pos, radius)
			s.monster:hearNoise(pos, radius)
		end,
	})
	local bottles = prompts(s.world.model.Bottles, "Bottle")
	check(#bottles >= 6 and #bottles <= 12, #bottles .. " bottles lying around")
	for i = 1, 4 do
		bottles[i].Triggered:Fire(p)
	end
	check(p:GetAttribute("Bottles") == 3, "you can carry 3 (" .. tostring(p:GetAttribute("Bottles")) .. ")")
	check(bottles[4].Parent ~= nil, "the 4th stays on the floor")
	s.monster:awaken()
	-- stand at the end of a long corridor with the monster partway down it, and throw past it
	local from, run_
	for z = 0, s.layout.depth - 1 do
		for x = 0, s.layout.width - 1 do
			for _, d in s.mods.Maze.DIRS do
				local cells = s.mods.Maze.straightRun(s.layout, { x = x, z = z }, d, 3)
				if not from and #cells == 3 then
					from, run_ = { x = x, z = z }, cells
				end
			end
		end
	end
	check(from ~= nil, "found a long corridor")
	local start = cellCenter(s.layout, from)
	local look = (cellCenter(s.layout, run_[3]) - start).Unit
	placePlayer(p, start)
	p.Character.HumanoidRootPart.CFrame = CFrame.lookAt(Vector3.new(start.X, 3, start.Z), Vector3.new(start.X, 3, start.Z) + look)
	local mid = cellCenter(s.layout, run_[2])
	s.monster.rig.model:PivotTo(CFrame.new(mid.X, s.monster.rig.rootHeight, mid.Z))
	local remotes = s.game:GetService("ReplicatedStorage").Remotes
	remotes.Throw.OnServerEvent:Fire(p, look)
	check(p:GetAttribute("Bottles") == 2, "throwing uses one up")
	local went = run(s, 3, function()
		return s.monster.state == "Investigate"
	end)
	local shards = 0
	for _, d in s.world.model.Bottles:GetChildren() do
		if d.Name == "Shard" then
			shards += 1
		end
	end
	check(shards > 0, "it smashes")
	check(went, "the monster goes to look (" .. tostring(s.monster.state) .. ")")
	remotes.Throw.OnServerEvent:Fire(p, Vector3.new(0, 0, 50))
	check(p:GetAttribute("Bottles") == 2, "bogus throws are ignored")
	p:SetAttribute("Hiding", true)
	remotes.Throw.OnServerEvent:Fire(p, Vector3.new(0, 0, 1))
	check(p:GetAttribute("Bottles") == 2, "no throwing from inside a locker")
	p:SetAttribute("Hiding", false)
	throwables.destroy()
	check(#Engine.errors == 0, "no script errors (" .. #Engine.errors .. ")")
end

---------------------------------------------------------------------------
print("Holding your breath")
do
	local s = setup(1, 777)
	local p = makePlayer(s.game, "Ares", 1)
	table.insert(s.alive, p)
	startChaos(s, "fog")
	local remotes = s.game:GetService("ReplicatedStorage").Remotes
	s.monster:awaken()
	local locker = s.interactables.lockers[1]
	placePlayer(p, locker.outside.Position)
	s.interactables:hide(p, locker)
	-- far away: letting your breath out does nothing
	s.monster.rig.model:PivotTo(CFrame.new(locker.outside.Position.X + 200, s.monster.rig.rootHeight, locker.outside.Position.Z))
	remotes.Breath.OnServerEvent:Fire(p)
	check(s.monster.state ~= "HuntLocker", "gasping with nothing around is fine")
	run(s, 5)
	-- right outside the door: it hears you
	s.monster.rig.model:PivotTo(CFrame.new(locker.outside.Position.X, s.monster.rig.rootHeight, locker.outside.Position.Z) * CFrame.new(0, 0, 7))
	remotes.Breath.OnServerEvent:Fire(p)
	check(s.monster.state == "HuntLocker", "gasp while it's right outside and it hears you")
	local pulled = run(s, 20, function()
		return #s.caught > 0
	end)
	check(pulled, "and it drags you out")
	s.chaos.destroy()
	check(#Engine.errors == 0, "no script errors (" .. #Engine.errors .. ")")
end

---------------------------------------------------------------------------
-- step the server without a round (lobby, night-server waiting room)
local function idle(game, seconds: number, until_: (() -> boolean)?): boolean
	local t = 0
	while t < seconds do
		Engine.time += 0.05
		Engine.runScheduled()
		game:GetService("RunService").Heartbeat:Fire(0.05)
		t += 0.05
		if until_ and until_() then
			return true
		end
	end
	return false
end

print("The lobby: four doors, the choice, the countdown")
do
	local game, _, mods = boot()
	local Lobby = mods.Lobby
	local launched = {}
	local open = true
	local lobby = Lobby.new({
		highest = function()
			return 3
		end,
		isOpen = function()
			return open
		end,
		launch = function(group, night)
			table.insert(launched, { group = group, night = night })
			for _, p in group do
				p:SetAttribute("Where", "between")
			end
		end,
	})
	local a, b, c = makePlayer(game, "A", 1), makePlayer(game, "B", 2), makePlayer(game, "C", 3)
	local function home(p)
		p:SetAttribute("Where", "lobby")
		placePlayer(p, Lobby.ORIGIN)
	end
	local function stand(p, i)
		placePlayer(p, lobby.pads[i].center)
	end
	for _, p in { a, b, c } do
		home(p)
	end
	check(#lobby.pads == 4, "four doors")

	stand(a, 1)
	idle(game, 0.3)
	check(lobby.pads[1].state == "choosing" and lobby.pads[1].leader == a, "stepping into an empty square asks you")
	lobby.choose(a, 1, 5, 1)
	check(#launched == 1 and launched[1].group[1] == a and launched[1].night == 3, "1 player goes straight in (and only to a night you've reached)")
	idle(game, 2.2)
	check(lobby.pads[1].state == "idle", "the door is free again")

	home(a)
	stand(b, 2)
	idle(game, 0.3)
	lobby.choose(b, 2, 2, 3)
	stand(c, 2)
	idle(game, 0.4)
	check(lobby.pads[2].state == "waiting" and lobby.pads[2].count.Text == "2 / 3", "3 players: it waits, and counts who's in (" .. lobby.pads[2].count.Text .. ")")
	check(lobby.pads[2].timer.Text == "10" or lobby.pads[2].timer.Text == "9", "counting down from 10 (" .. lobby.pads[2].timer.Text .. ")")
	idle(game, 5)
	check(#launched == 1 and tonumber(lobby.pads[2].timer.Text) <= 5, "still counting (" .. lobby.pads[2].timer.Text .. ")")
	idle(game, 5.5)
	check(#launched == 2 and #launched[2].group == 2 and launched[2].night == 2, "at 0 whoever's standing in it goes through")

	home(a)
	home(b)
	home(c)
	stand(a, 3)
	stand(b, 3)
	stand(c, 3)
	idle(game, 0.3)
	lobby.choose(lobby.pads[3].leader, 3, 1, 2)
	idle(game, 10.5)
	check(#launched == 3 and #launched[3].group == 2, "never more than the number chosen")
	local left = nil
	for _, p in { a, b, c } do
		if p:GetAttribute("Where") == "lobby" then
			left = p
		end
	end
	check(left ~= nil, "the one who didn't fit stays behind")

	for _, p in { a, b, c } do
		home(p)
	end
	idle(game, 2.5)
	stand(a, 4)
	idle(game, 0.3)
	home(a)
	idle(game, 0.3)
	check(lobby.pads[4].state == "idle", "walking out while choosing puts it back")
	stand(a, 4)
	idle(game, 0.3)
	lobby.cancel(a, 4)
	idle(game, 0.6)
	check(lobby.pads[4].state == "idle", "closing the choice: it doesn't ask again while you stand there")
	home(a)
	stand(b, 1)
	idle(game, 0.3)
	lobby.choose(b, 1, 1, 4)
	home(b)
	idle(game, 0.4)
	check(lobby.pads[1].state == "idle" and #launched == 3, "everyone walks out: it stops")

	open = false
	stand(c, 2)
	idle(game, 0.4)
	check(lobby.pads[2].state == "idle", "the doors don't open while a night is being played here")
	lobby.destroy()
	check(#Engine.errors == 0, "no script errors (" .. #Engine.errors .. ")")
end

print("A lobby server sends the group to a reserved server")
do
	Engine.placeId = 4242
	Engine.teleports = {}
	local game, _, mods = boot()
	local p = makePlayer(game, "Ares", 1)
	mods.runScript(mods.server.Main)
	idle(game, 1)
	check(p:GetAttribute("Where") == "lobby", "you start in the lobby")
	local padPart = game:GetService("Workspace").Lobby.Pad1
	placePlayer(p, padPart.Position)
	idle(game, 0.4)
	game:GetService("ReplicatedStorage").Remotes.Lobby.OnServerEvent:Fire(p, "choose", 1, 1, 1)
	idle(game, 0.5)
	local t = Engine.teleports[1]
	check(t ~= nil and t.placeId == 4242 and t.players[1] == p, "teleported to this place")
	check(t ~= nil and t.data ~= nil and t.data.night == 1 and t.data.count == 1, "with the night and how many are coming")
	Engine.placeId = nil
	check(#Engine.errors == 0, "no script errors (" .. #Engine.errors .. ")")
end

print("A night server plays the group's night, then sends everyone home")
do
	Engine.privateServerId = "reserved"
	Engine.teleports = {}
	Engine.saved = {} -- hasn't beaten anything: every night is open anyway
	Engine.joinData = { Ares = { night = 3, count = 1 } }
	local game, _, mods = boot()
	local p = makePlayer(game, "Ares", 1)
	mods.runScript(mods.server.Main)
	local GameState = game:GetService("ReplicatedStorage").GameState
	local started = idle(game, 25, function()
		return GameState:GetAttribute("Phase") == "Playing"
	end)
	check(started and GameState:GetAttribute("Night") == 3, "night 3 starts straight away (" .. tostring(GameState:GetAttribute("Night")) .. ")")
	check(p:GetAttribute("Where") == "night", "you're in it")
	local RoundManager = mods.require(mods.server.RoundManager)
	local Retry = game:GetService("ReplicatedStorage").Remotes.Retry
	RoundManager.caught(p, nil)
	idle(game, 1)
	check(#Engine.teleports == 0, "caught: it waits for your choice")
	Retry.OnServerEvent:Fire(p, "again")
	local again = idle(game, 5, function()
		return GameState:GetAttribute("Phase") == "Playing" and p:GetAttribute("Where") == "night"
	end)
	check(again, "TRY AGAIN (1 / 1): the night starts over")
	RoundManager.caught(p, nil)
	idle(game, 1)
	Retry.OnServerEvent:Fire(p, "lobby")
	local home = idle(game, 15, function()
		return #Engine.teleports > 0
	end)
	check(home and Engine.teleports[1].players[1] == p and Engine.teleports[1].data == nil, "BACK TO LOBBY: sent back to a lobby")
	Engine.privateServerId = nil
	Engine.joinData = {}
	Engine.saved = {}
	check(#Engine.errors == 0, "no script errors (" .. #Engine.errors .. ")")
end

print("A group's night: TRY AGAIN needs all of them")
do
	Engine.teleports = {}
	local game, _, mods = boot()
	local a, b = makePlayer(game, "A", 1), makePlayer(game, "B", 2)
	mods.runScript(mods.server.Main)
	idle(game, 1)
	local rs = game:GetService("ReplicatedStorage")
	local GameState = rs.GameState
	local pad1 = game:GetService("Workspace").Lobby.Pad1
	placePlayer(a, pad1.Position)
	idle(game, 0.4)
	rs.Remotes.Lobby.OnServerEvent:Fire(a, "choose", 1, 1, 2)
	placePlayer(b, pad1.Position)
	local function both(where: string): boolean
		return a:GetAttribute("Where") == where and b:GetAttribute("Where") == where
	end
	local started = idle(game, 14, function()
		return GameState:GetAttribute("Phase") == "Playing" and both("night")
	end)
	check(started, "the two of them go in together after the countdown")
	local RoundManager = mods.require(mods.server.RoundManager)
	local Retry = rs.Remotes.Retry
	RoundManager.caught(a, nil)
	RoundManager.caught(b, nil)
	idle(game, 1)
	Retry.OnServerEvent:Fire(a, "again")
	check(RoundManager.againCount() == 1, "one tries again: 1 / 2")
	idle(game, 2)
	check(GameState:GetAttribute("Phase") ~= "Playing", "one isn't enough")
	Retry.OnServerEvent:Fire(b, "again")
	check(idle(game, 5, function()
		return GameState:GetAttribute("Phase") == "Playing" and both("night")
	end), "2 / 2: it starts over for both of them")
	RoundManager.caught(a, nil)
	RoundManager.caught(b, nil)
	idle(game, 1)
	Retry.OnServerEvent:Fire(a, "again")
	Retry.OnServerEvent:Fire(b, "lobby")
	check(idle(game, 2, function()
		return b:GetAttribute("Where") == "lobby"
	end), "BACK TO LOBBY: straight back")
	check(idle(game, 5, function()
		return a:GetAttribute("Where") == "lobby" and GameState:GetAttribute("Phase") == "Lobby"
	end), "not all of them wanted to try again, so everyone's back")
	check(#Engine.errors == 0, "no script errors (" .. #Engine.errors .. ")")
end

check(#Engine.errors == 0, "no script errors anywhere (" .. #Engine.errors .. ")")
if failures > 0 then
	error(failures .. " check(s) failed")
end
print("simulation tests passed")
