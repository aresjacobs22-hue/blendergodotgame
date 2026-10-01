-- Runs the real server scripts (world builder, interactables, monster AI) inside a
-- mocked Roblox under Lune, then plays out scenarios with a fake player:
--   lune run tests/sim.spec.luau
local roblox = require("@lune/roblox")
local Engine = require("./mock/engine")

local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

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
-- boot a fresh fake engine + load the server modules

local function boot()
	Engine.time = 0
	Engine.delayed = {}
	Engine.sleeping = {}
	local shared = Engine.folderFromDir("Shared", "src/ReplicatedStorage/Shared")
	local server = Engine.folderFromDir("Server", "src/ServerScriptService/Server")
	local game, workspace = Engine.makeGame(server, shared, nil, REMOTES)
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
	local require = Engine.makeLoader(globals)
	local rs = game:GetService("ReplicatedStorage")
	local sss = game:GetService("ServerScriptService")

	-- pretend the audio is uploaded so every sound code path runs
	local SoundIds = require(rs.Shared.SoundIds)
	SoundIds.SFX = 111
	SoundIds.Ambience = 222
	SoundIds.MusicBox = 333

	local mods = {
		Config = require(rs.Shared.Config),
		Maze = require(rs.Shared.Maze),
		Audio = require(rs.Shared.Audio),
		WorldBuilder = require(sss.Server.WorldBuilder),
		Interactables = require(sss.Server.Interactables),
		MonsterAI = require(sss.Server.MonsterAI),
		MonsterRig = require(sss.Server.MonsterRig),
	}
	Engine.Maze = mods.Maze
	return game, workspace, mods
end

local function makePlayer(game, name: string, userId: number)
	local players = game:GetService("Players")
	local player = Engine.newInstance("Player", name)
	player.DisplayName = name
	player.UserId = userId
	local character = Engine.newInstance("Model", name)
	local root = Engine.newInstance("Part", "HumanoidRootPart")
	root.Size = Vector3.new(2, 2, 1)
	root.Parent = character
	local head = Engine.newInstance("Part", "Head")
	head.Size = Vector3.new(1, 1, 1)
	head.Parent = character
	Engine.newInstance("Humanoid", "Humanoid").Parent = character
	character.PrimaryPart = root
	player.Character = character
	player.Parent = players
	local list = rawget(players, "_list") or {}
	table.insert(list, player)
	rawset(players, "_list", list)
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

-- one simulation tick: timers, AI heartbeat, then move the monster like a Humanoid would
local wallViolations = 0
local function tick(game, monster, dt: number)
	Engine.time += dt
	Engine.runScheduled()
	game:GetService("RunService").Heartbeat:Fire(dt)
	local root = monster.rig.root
	local humanoid = monster.rig.humanoid
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
			local inside = ax >= 0 and az >= 0 and bx >= 0 and bz >= 0
			if inside and not Engine.canCross(ax, az, bx, bz) then
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

local function setup(seed: number)
	local game, workspace, mods = boot()
	local layout = mods.Maze.generate(seed, mods.Config.Maze)
	Engine.layout = layout
	local world = mods.WorldBuilder.build(layout)

	local interactables
	local function s_interactables_removePadlock()
		interactables:removePadlock()
	end
	local caught: { any } = {}
	local escaped: { any } = {}
	local keys: { number } = {}
	local alive: { any } = {}
	local monster
	interactables = mods.Interactables.new(layout, world, {
		isAlive = function(p)
			return table.find(alive, p) ~= nil
		end,
		onKey = function(_p, index)
			table.insert(keys, index)
			s_interactables_removePadlock()
			monster:setAggression(#keys)
			monster:awaken()
		end,
		onHide = function(p, locker)
			monster:onPlayerHid(p, locker)
		end,
		onExitOpened = function()
			monster:onExitOpened()
		end,
		onEscaped = function(p)
			table.insert(escaped, p)
			local i = table.find(alive, p)
			if i then
				table.remove(alive, i)
			end
		end,
		onNoise = function(pos, radius)
			monster:hearNoise(pos, radius)
		end,
	})
	monster = mods.MonsterAI.new(layout, world, interactables, {
		getPlayers = function()
			return table.clone(alive)
		end,
		onCaught = function(p)
			table.insert(caught, p)
			local i = table.find(alive, p)
			if i then
				table.remove(alive, i)
			end
		end,
		onAwake = function() end,
	})
	monster:start()
	return {
		game = game,
		workspace = workspace,
		mods = mods,
		layout = layout,
		world = world,
		interactables = interactables,
		monster = monster,
		caught = caught,
		escaped = escaped,
		keys = keys,
		alive = alive,
	}
end

local function cellCenter(layout, c)
	return Vector3.new((c.x + 0.5) * layout.cellSize, 0, (c.z + 0.5) * layout.cellSize)
end

local function run(s, seconds: number, until_: (() -> boolean)?)
	local dt = 0.05
	local t = 0
	while t < seconds do
		tick(s.game, s.monster, dt)
		t += dt
		if until_ and until_() then
			return true, t
		end
	end
	return false, t
end

---------------------------------------------------------------------------
print("World construction")
do
	local s = setup(424242)
	local parts, lights, prompts = 0, 0, 0
	for _, d in s.world.model:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
		elseif d.ClassName == "PointLight" then
			lights += 1
		elseif d.ClassName == "ProximityPrompt" then
			prompts += 1
		end
	end
	print(string.format("  %d parts, %d point lights, %d prompts", parts, lights, prompts))
	check(parts > 500 and parts < 3000, "part count is sane")
	check(lights >= 15 and lights <= 45, "lamp count is sane")
	local rigParts = 0
	for _, d in s.monster.rig.model:GetDescendants() do
		if d:IsA("BasePart") then
			rigParts += 1
		end
	end
	check(rigParts > 30, "monster rig built (" .. rigParts .. " parts)")
	check(#s.interactables.lockers == #s.layout.lockers, "every locker built")
	check(#s.interactables.doors >= 3, "house doors built (" .. #s.interactables.doors .. ")")
	check(s.monster.state == "Dormant", "monster starts dormant")
	check(s.monster.rig.root.Position.Y < -100, "dormant monster is parked out of sight")
end

---------------------------------------------------------------------------
print("Dormant: apparitions, then it wakes up on its own")
do
	local s = setup(1001)
	local p = makePlayer(s.game, "Ares", 1)
	table.insert(s.alive, p)
	-- stand in a maze corridor right outside the house
	placePlayer(p, cellCenter(s.layout, s.layout.entrance))
	local apparitions = 0
	local wasApparition = false
	local woke, t = run(s, 120, function()
		local isApp = s.monster.state == "Apparition"
		if isApp and not wasApparition then
			apparitions += 1
		end
		wasApparition = isApp
		return s.monster.awake
	end)
	check(woke, string.format("woke up after %.0fs", t))
	print("  apparitions seen while dormant: " .. apparitions)
	check(s.monster.rig.root.Position.Y > 0, "awake monster is in the maze")
	check(not s.monster.rig.root.Anchored, "awake monster can move")
end

---------------------------------------------------------------------------
print("Hunting: a player standing still in the maze gets found")
do
	local total, found = 0, 0
	for seed = 1, 6 do
		local s = setup(seed * 7777)
		local p = makePlayer(s.game, "Ares", 1)
		table.insert(s.alive, p)
		local spot = s.layout.keys[1]
		placePlayer(p, cellCenter(s.layout, spot))
		s.monster:awaken()
		total += 1
		local ok, t = run(s, 300, function()
			return #s.caught > 0
		end)
		if ok then
			found += 1
		end
		print(string.format("  seed %d: %s after %.0fs", seed * 7777, if ok then "caught" else "not caught", t))
	end
	check(found >= 5, string.format("caught a stationary player in %d/%d mazes within 5 minutes", found, total))
	check(wallViolations == 0, "monster never walked through a wall (" .. wallViolations .. " violations)")
end

---------------------------------------------------------------------------
print("Chase -> hide in a locker while it watches -> pulled out")
do
	local s = setup(31337)
	local p = makePlayer(s.game, "Ares", 1)
	table.insert(s.alive, p)
	s.monster:awaken()
	-- put the player 2 cells in front of the monster in a straight corridor
	local mroot = s.monster.rig.root
	local mc = s.mods.Maze.cellOf(s.layout, mroot.Position.X, mroot.Position.Z)
	local placed = false
	for _, d in s.mods.Maze.DIRS do
		local runCells = s.mods.Maze.straightRun(s.layout, mc, d, 3)
		if #runCells >= 2 then
			placePlayer(p, cellCenter(s.layout, runCells[2]))
			s.monster.rig.model:PivotTo(CFrame.lookAt(mroot.Position, flat(p.Character.HumanoidRootPart.Position) + Vector3.new(0, mroot.Position.Y, 0)))
			placed = true
			break
		end
	end
	check(placed, "found a straight corridor for the test")
	local chased = run(s, 3, function()
		return s.monster.state == "Chase"
	end)
	check(chased, "it sees the player and starts chasing")
	-- jump into the nearest maze locker right now
	local locker = s.interactables.lockers[3]
	s.interactables:hide(p, locker)
	check(p:GetAttribute("Hiding") == true, "player is hiding")
	check(s.monster.sawHide[p] == locker, "it saw which locker")
	local pulled = run(s, 120, function()
		return #s.caught > 0
	end)
	check(s.monster.state == "Kill" or pulled, "it pulled the player out of the locker")
	check(p:GetAttribute("Hiding") == false, "player was dragged out")
end

---------------------------------------------------------------------------
print("Hide while unseen -> it gives up")
do
	local s = setup(2024)
	local p = makePlayer(s.game, "Ares", 1)
	table.insert(s.alive, p)
	s.monster:awaken()
	local locker = s.interactables.lockers[#s.interactables.lockers]
	placePlayer(p, locker.outside.Position)
	s.interactables:hide(p, locker)
	local caughtWhileHiding = run(s, 150, function()
		return #s.caught > 0 or s.monster.state == "HuntLocker"
	end)
	check(not caughtWhileHiding, "a hidden, unseen player survives 150s")
	s.interactables:leave(p, false)
	check(p:GetAttribute("Hiding") == false and not p.Character.HumanoidRootPart.Anchored, "leaving the locker frees the player")
end

---------------------------------------------------------------------------
print("Keys -> padlocks -> code -> exit -> escape")
do
	local s = setup(99)
	local p = makePlayer(s.game, "Ares", 1)
	table.insert(s.alive, p)
	local keyModels = {}
	for _, d in s.interactables.folder:GetChildren() do
		if string.match(d.Name, "^Key%d$") then
			table.insert(keyModels, d)
		end
	end
	check(#keyModels == 4, "4 keys exist")
	for _, model in keyModels do
		local prompt = model.Shaft:FindFirstChildOfClass("ProximityPrompt")
		prompt.Triggered:Fire(p)
	end
	check(#s.keys == 4, "picking up keys calls onKey 4 times")
	check(s.interactables.padlocksLeft == 0, "all padlocks fall off")
	check(s.monster.awake, "taking a key wakes the monster")

	local remotes = s.game:GetService("ReplicatedStorage").Remotes
	placePlayer(p, s.interactables.keypad.Position + Vector3.new(0, 0, 4))
	remotes.SubmitCode.OnServerEvent:Fire(p, "0000" == s.layout.code and "1111" or "0000")
	check(not s.interactables.exitOpen, "wrong code keeps the door shut")
	check(s.monster.noise ~= nil or s.monster.state == "Investigate", "the wrong-code buzzer makes noise")
	Engine.time += 1
	remotes.SubmitCode.OnServerEvent:Fire(p, s.layout.code)
	check(s.interactables.exitOpen, "right code opens the exit")
	run(s, 1)
	check(s.world.exitLight.Enabled, "the light outside comes on")
	check(s.monster.state == "Chase" and os.clock ~= nil, "exit opening sends it into a frenzy chase")
	s.world.escapeZone.Touched:Fire(p.Character.HumanoidRootPart)
	check(#s.escaped == 1, "touching the escape zone escapes")
end

---------------------------------------------------------------------------
print("Doors")
do
	local s = setup(5150)
	local door = s.interactables.doors[1]
	local was = door.isOpen
	s.interactables:setDoor(door, not was, false)
	check(door.isOpen ~= was and not door.busy, "doors toggle")
	s.interactables:setDoor(door, false, false)
	s.interactables:slamOpenNear(door.part.Position, 8)
	check(door.isOpen, "the monster slams doors open")
end

if #Engine.log > 0 then
	print("warnings logged: " .. #Engine.log)
	for i = 1, math.min(5, #Engine.log) do
		print("  " .. Engine.log[i])
	end
end

if failures > 0 then
	error(failures .. " check(s) failed")
end
print("simulation tests passed")
