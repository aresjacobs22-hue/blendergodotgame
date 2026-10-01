--!strict
-- The thing in the halls. Server-side brain, tuned per night (see Nights.luau):
--   Dormant     hidden away; now and then it APPEARS at the end of your corridor,
--               stares, and vanishes when you get close
--   Wander      roams, drifting towards wherever players are
--   Investigate heard something and goes to look
--   Chase       saw (or heard) you. Screams. Runs at you
--   Search      lost you; sniffs around the last place it saw you
--   HuntLocker  watched (or smelled) you climb into a locker, coming to pull you out
--   Kill        caught someone
-- The Statue has its own two states: Frozen (someone is looking) and Stalk.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Audio = require(ReplicatedStorage.Shared.Audio)
local Maze = require(ReplicatedStorage.Shared.Maze)
local Monsters = require(ReplicatedStorage.Shared.Monsters)
local Interactables = require(script.Parent.Interactables)
local WorldBuilder = require(script.Parent.WorldBuilder)

local Remotes = ReplicatedStorage.Remotes

type Layout = Maze.Layout
type Locker = Interactables.Locker

export type Hooks = {
	getPlayers: () -> { Player }, -- players still in the round (not caught, not escaped)
	onCaught: (player: Player, monster: Model) -> (),
	onAwake: () -> (),
	getLook: (player: Player) -> Vector3?, -- where that player's camera points
	setBlink: (on: boolean) -> (),
}

local MonsterAI = {}
MonsterAI.__index = MonsterAI

export type MonsterAI = typeof(setmetatable(
	{} :: {
		layout: Layout,
		world: WorldBuilder.World,
		interactables: Interactables.Interactables,
		hooks: Hooks,
		p: { [string]: any },
		rig: Monsters.Rig,
		humanoid: Humanoid,
		state: string,
		path: { Vector3 },
		pathIndex: number,
		pathGoal: Vector3?,
		lastRepath: number,
		target: Player?,
		lastSeenPos: Vector3?,
		lastSeenTime: number,
		aggression: number,
		frenzyUntil: number,
		lungeUntil: number,
		nextLunge: number,
		awake: boolean,
		awakeAt: number,
		nextApparition: number,
		apparitionTarget: Player?,
		apparitionEnds: number,
		sawHide: { [Player]: Locker },
		huntLocker: Locker?,
		pauseUntil: number,
		searchCenter: Vector3,
		searchUntil: number,
		lastScream: number,
		lastContact: number,
		stuckCheckAt: number,
		stuckPos: Vector3,
		stuckCount: number,
		sightParams: RaycastParams,
		moveParams: RaycastParams,
		noise: { position: Vector3, radius: number }?,
		nextBlink: number,
		blinkUntil: number,
		frozen: boolean,
		lastGrind: number,
		thinkAccum: number,
		connection: RBXScriptConnection?,
		destroyed: boolean,
		random: Random,
	},
	MonsterAI
))

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local rootOf = Interactables.rootOf

local function headOf(player: Player): BasePart?
	local character = player.Character
	return if character then character:FindFirstChild("Head") :: BasePart? else nil
end

function MonsterAI.new(layout: Layout, world: WorldBuilder.World, interactables: Interactables.Interactables, params: { [string]: any }, kind: string, hooks: Hooks): MonsterAI
	local rig = Monsters.build(kind)
	rig.model.Parent = workspace

	local sightParams = RaycastParams.new()
	sightParams.FilterType = Enum.RaycastFilterType.Include
	sightParams.FilterDescendantsInstances = { world.model }

	-- movement checks ignore furniture (it walks through it) and non-collidable decor
	local moveParams = RaycastParams.new()
	moveParams.FilterType = Enum.RaycastFilterType.Include
	moveParams.FilterDescendantsInstances = { world.model }
	moveParams.CollisionGroup = "Monster"
	moveParams.RespectCanCollide = true

	local now = os.clock()
	local random = Random.new(layout.seed + 99)
	local self = setmetatable({
		layout = layout,
		world = world,
		interactables = interactables,
		hooks = hooks,
		p = params,
		rig = rig,
		humanoid = rig.humanoid :: Humanoid,
		state = "Dormant",
		path = {},
		pathIndex = 1,
		pathGoal = nil,
		lastRepath = 0,
		target = nil,
		lastSeenPos = nil,
		lastSeenTime = -math.huge,
		aggression = 0,
		frenzyUntil = 0,
		lungeUntil = 0,
		nextLunge = 0,
		awake = false,
		awakeAt = now + params.AwakenAfter,
		nextApparition = now + random:NextNumber(params.ApparitionMin * 0.5, params.ApparitionMax * 0.6),
		apparitionTarget = nil,
		apparitionEnds = 0,
		sawHide = {},
		huntLocker = nil,
		pauseUntil = 0,
		searchCenter = Vector3.zero,
		searchUntil = 0,
		lastScream = -math.huge,
		lastContact = now,
		stuckCheckAt = 0,
		stuckPos = Vector3.zero,
		stuckCount = 0,
		sightParams = sightParams,
		moveParams = moveParams,
		noise = nil,
		nextBlink = now + random:NextNumber(params.BlinkMin, params.BlinkMax),
		blinkUntil = 0,
		frozen = false,
		lastGrind = 0,
		thinkAccum = 0,
		connection = nil,
		destroyed = false,
		random = random,
	}, MonsterAI)

	self:_park()
	self:_setState("Dormant")
	return self
end

function MonsterAI.start(self: MonsterAI)
	self.connection = RunService.Heartbeat:Connect(function(dt: number)
		self.thinkAccum += dt
		if self.thinkAccum >= 0.1 then
			self.thinkAccum = 0
			self:_think()
		end
	end)
end

function MonsterAI.destroy(self: MonsterAI)
	self.destroyed = true
	if self.connection then
		self.connection:Disconnect()
		self.connection = nil
	end
	self.hooks.setBlink(false)
	self.rig.model:Destroy()
end

-- Public hooks -----------------------------------------------------------------

function MonsterAI.setAggression(self: MonsterAI, progress: number)
	self.aggression = progress
	self:_updateSpeed()
end

function MonsterAI.hearNoise(self: MonsterAI, position: Vector3, radius: number)
	if not self.noise or radius > self.noise.radius then
		self.noise = { position = position, radius = radius }
	end
end

function MonsterAI.onPlayerHid(self: MonsterAI, player: Player, locker: Locker)
	-- it only knows which locker you're in if it was watching you a moment ago...
	if self.state == "Chase" and self.target == player and os.clock() - self.lastSeenTime < 0.8 then
		self.sawHide[player] = locker
		return
	end
	-- ...or if it can smell you, in which case it comes straight for the locker
	local sense = self.p.SenseHidden
	if sense > 0 and self.awake and self.state ~= "Kill" and (locker.inside.Position - self.rig.root.Position).Magnitude < sense then
		self.sawHide[player] = locker
		self.huntLocker = locker
		self:_setState("HuntLocker")
		self:_setPathTo(locker.outside.Position)
	end
end

-- It knows where everyone is for a while, and goes for the nearest (or a given) player.
function MonsterAI.frenzy(self: MonsterAI, seconds: number, target: Player?)
	if not self.awake then
		self:awaken()
	end
	self.frenzyUntil = os.clock() + seconds
	if self.p.Statue then
		return
	end
	local root = self.rig.root
	local chosen = target
	if not chosen or chosen:GetAttribute("Hiding") then
		local best = math.huge
		for _, player in self.hooks.getPlayers() do
			local proot = rootOf(player)
			if proot and not player:GetAttribute("Hiding") then
				local d = (proot.Position - root.Position).Magnitude
				if d < best then
					chosen, best = player, d
				end
			end
		end
	end
	if chosen and self.state ~= "Kill" then
		self.lastSeenTime = os.clock()
		self:_startChase(chosen)
	end
	self:_updateSpeed()
end

function MonsterAI.onExitOpened(self: MonsterAI)
	self:frenzy(self.p.FrenzyTime, nil)
end

function MonsterAI.forget(self: MonsterAI, player: Player)
	self.sawHide[player] = nil
	if self.target == player then
		self.target = nil
	end
	if self.apparitionTarget == player then
		self.apparitionTarget = nil
	end
end

function MonsterAI.awaken(self: MonsterAI)
	if self.awake or self.destroyed then
		return
	end
	self.awake = true

	-- wake up in the maze cell farthest from every player
	local spawnCell = self.layout.monsterSpawn
	local players = self.hooks.getPlayers()
	if #players > 0 then
		local maps = {}
		for _, player in players do
			local proot = rootOf(player)
			if proot then
				table.insert(maps, Maze.distances(self.layout, Maze.cellOf(self.layout, proot.Position.X, proot.Position.Z)))
			end
		end
		local bestScore = -1
		for z = 0, self.layout.depth - 1 do
			for x = 0, self.layout.width - 1 do
				if not Maze.isHub(self.layout, x, z) then
					local score = math.huge
					for _, dist in maps do
						score = math.min(score, dist[Maze.key(x, z)] or 0)
					end
					if score > bestScore then
						bestScore = score
						spawnCell = { x = x, z = z }
					end
				end
			end
		end
	end
	local cx, cz = Maze.cellCenter(self.layout, spawnCell)
	self.rig.model:PivotTo(CFrame.new(cx, self.rig.rootHeight, cz))
	self:_release()
	self.humanoid:MoveTo(self.rig.root.Position) -- forget the walk target from where it was parked
	if self.rig.growl then
		self.rig.growl:Play()
	end
	if self.p.Statue then
		self:_setState("Stalk")
	else
		self:_setState("Wander")
		self:_pickWanderTarget()
	end
	self.hooks.onAwake()
end

-- Internals ----------------------------------------------------------------------

function MonsterAI._park(self: MonsterAI)
	self.rig.root.Anchored = true
	self.rig.model:PivotTo(self.world.hiddenSpot)
	self.humanoid:MoveTo(self.rig.root.Position)
end

function MonsterAI._release(self: MonsterAI)
	self.rig.root.Anchored = false
	pcall(function()
		self.rig.root:SetNetworkOwner(nil) -- the server drives it, never a nearby client
	end)
end

function MonsterAI._setState(self: MonsterAI, state: string)
	self.state = state
	self.rig.model:SetAttribute("State", state)
	if state ~= "Chase" and state ~= "HuntLocker" and state ~= "Kill" then
		self.rig.model:SetAttribute("TargetUserId", 0)
	end
	self:_updateSpeed()
end

function MonsterAI._chaseSpeed(self: MonsterAI): number
	local p = self.p
	local speed = p.ChaseSpeed + self.aggression * p.ChaseSpeedPerProgress
	local now = os.clock()
	if now < self.frenzyUntil then
		speed += p.FrenzyBonus
	end
	if now < self.lungeUntil then
		speed += p.LungeBonus
	end
	return speed
end

function MonsterAI._updateSpeed(self: MonsterAI)
	local p = self.p
	local s = self.state
	local speed = 0
	if s == "Wander" then
		speed = p.WanderSpeed
	elseif s == "Investigate" then
		speed = p.InvestigateSpeed
	elseif s == "Search" then
		speed = p.SearchSpeed
	elseif s == "Chase" then
		speed = self:_chaseSpeed()
	elseif s == "HuntLocker" then
		speed = self:_chaseSpeed() - 1
	elseif s == "Stalk" then
		speed = p.StatueSpeed + self.aggression * p.StatueSpeedPerProgress
	end
	self.humanoid.WalkSpeed = speed
	local growl = self.rig.growl
	if growl then
		local chasing = s == "Chase" or s == "HuntLocker"
		growl.PlaybackSpeed = if chasing then 1.12 else 0.92
		growl.Volume = if chasing then 1.9 else 1.2
	end
end

function MonsterAI._cellAt(self: MonsterAI, pos: Vector3): Maze.Cell
	return Maze.cellOf(self.layout, pos.X, pos.Z)
end

function MonsterAI._isActive(self: MonsterAI, player: Player): boolean
	for _, p in self.hooks.getPlayers() do
		if p == player then
			return true
		end
	end
	return false
end

-- Waypoints through the maze: edge midpoints (doorways are centred on them) and
-- cell centres, ending exactly at the goal.
function MonsterAI._setPathTo(self: MonsterAI, goal: Vector3): boolean
	local root = self.rig.root
	local cells = Maze.findPath(self.layout, self:_cellAt(root.Position), self:_cellAt(goal))
	self.pathGoal = goal
	self.pathIndex = 1
	if not cells then
		self.path = {}
		return false
	end
	local C = self.layout.cellSize
	local y = root.Position.Y
	local points = {}
	for i = 2, #cells do
		local a, b = cells[i - 1], cells[i]
		table.insert(points, Vector3.new((a.x + b.x + 1) * C / 2, y, (a.z + b.z + 1) * C / 2))
		if i < #cells then
			local cx, cz = Maze.cellCenter(self.layout, b)
			table.insert(points, Vector3.new(cx, y, cz))
		end
	end
	table.insert(points, Vector3.new(goal.X, y, goal.Z))
	self.path = points
	return true
end

-- Returns true once the path is finished.
function MonsterAI._followPath(self: MonsterAI): boolean
	local root = self.rig.root
	local p = self.path[self.pathIndex]
	while p and flat(p - root.Position).Magnitude < 2.2 do
		self.pathIndex += 1
		p = self.path[self.pathIndex]
	end
	if not p then
		self.path = {}
		return true
	end
	self.humanoid:MoveTo(p)
	return false
end

function MonsterAI._clearLine(self: MonsterAI, goal: Vector3): boolean
	local origin = self.rig.root.Position
	local direction = Vector3.new(goal.X, origin.Y, goal.Z) - origin
	if direction.Magnitude < 1 then
		return true
	end
	return workspace:Spherecast(origin, 1.3, direction, self.moveParams) == nil
end

-- Go straight at a point when nothing's in the way, otherwise path to it.
function MonsterAI._moveToward(self: MonsterAI, goal: Vector3, now: number)
	if self:_clearLine(goal) then
		self.path = {}
		self.humanoid:MoveTo(Vector3.new(goal.X, self.rig.root.Position.Y, goal.Z))
	else
		local goalMoved = self.pathGoal == nil or flat((self.pathGoal :: Vector3) - goal).Magnitude > 6
		if #self.path == 0 or goalMoved or now - self.lastRepath > 0.8 then
			self.lastRepath = now
			self:_setPathTo(goal)
		end
		self:_followPath()
	end
end

function MonsterAI._canSee(self: MonsterAI, player: Player, ignoreCone: boolean): (boolean, Vector3?)
	local p = self.p
	if player:GetAttribute("Hiding") then
		return false, nil
	end
	local proot, phead = rootOf(player), headOf(player)
	if not proot or not phead then
		return false, nil
	end
	local eye = self.rig.head.Position
	local toTarget = phead.Position - eye
	local dist = toTarget.Magnitude
	local range = if player:GetAttribute("Flashlight") then p.SightRangeFlashlight else p.SightRange
	local speed = flat(proot.AssemblyLinearVelocity).Magnitude
	if speed > 0.5 and speed < 6.5 then
		range *= p.SneakSightMultiplier
	end
	range = math.max(range, p.CloseSense) -- even a blind thing notices you bump into it
	if dist > range then
		return false, nil
	end
	if not ignoreCone and dist > p.CloseSense then
		local look = flat(self.rig.root.CFrame.LookVector)
		local dir = flat(toTarget)
		if look.Magnitude > 0.01 and dir.Magnitude > 0.01 and look.Unit:Dot(dir.Unit) < p.ViewDot then
			return false, nil
		end
	end
	if workspace:Raycast(eye, toTarget, self.sightParams) then
		return false, nil
	end
	return true, proot.Position
end

function MonsterAI._lookForPlayers(self: MonsterAI): (Player?, Vector3?)
	local best: Player? = nil
	local bestPos: Vector3? = nil
	local bestDist = math.huge
	local root = self.rig.root
	for _, player in self.hooks.getPlayers() do
		local seen, pos = self:_canSee(player, self.state == "Chase" and player == self.target)
		if seen and pos then
			local d = (pos - root.Position).Magnitude
			if player == self.target then
				d *= 0.5 -- stick with the current target
			end
			if d < bestDist then
				best, bestPos, bestDist = player, pos, d
			end
		end
	end
	return best, bestPos
end

-- How far a player's footsteps carry right now (path studs).
function MonsterAI._noiseRadius(self: MonsterAI, player: Player): number
	local proot = rootOf(player)
	if not proot or player:GetAttribute("Hiding") then
		return 0
	end
	local speed = flat(proot.AssemblyLinearVelocity).Magnitude
	return if speed > 14 then self.p.HearSprint elseif speed > 6.5 then self.p.HearWalk else 0
end

-- Returns the loudest thing it can hear: (position, path distance, player?)
function MonsterAI._listen(self: MonsterAI): (Vector3?, number, Player?)
	local dist = Maze.distances(self.layout, self:_cellAt(self.rig.root.Position))
	local C = self.layout.cellSize
	local best: Vector3? = nil
	local bestDist = math.huge
	local bestPlayer: Player? = nil
	local function consider(position: Vector3, radius: number, player: Player?)
		local cell = self:_cellAt(position)
		local d = (dist[Maze.key(cell.x, cell.z)] or math.huge) * C
		if d <= radius and d < bestDist then
			best, bestDist, bestPlayer = position, d, player
		end
	end
	for _, player in self.hooks.getPlayers() do
		local radius = self:_noiseRadius(player)
		local proot = rootOf(player)
		if radius > 0 and proot then
			consider(proot.Position, radius, player)
		end
	end
	local noise = self.noise
	if noise then
		self.noise = nil
		consider(noise.position, noise.radius, nil)
	end
	return best, bestDist, bestPlayer
end

function MonsterAI._pickWanderTarget(self: MonsterAI)
	local W, D = self.layout.width, self.layout.depth
	local cell: Maze.Cell? = nil
	local players = self.hooks.getPlayers()
	local now = os.clock()
	local instinct = self.p.HuntingInstinct
	if #players > 0 then
		local proot = rootOf(players[self.random:NextInteger(1, #players)])
		if proot then
			local pc = self:_cellAt(proot.Position)
			if now - self.lastContact > instinct then
				-- it's been too quiet: it "smells" you and heads straight for where you are
				self.lastContact = now - instinct * 0.5
				cell = pc
			elseif self.random:NextNumber() < 0.7 then
				local r = self.random:NextInteger(1, 4)
				cell = {
					x = math.clamp(pc.x + self.random:NextInteger(-r, r), 0, W - 1),
					z = math.clamp(pc.z + self.random:NextInteger(-r, r), 0, D - 1),
				}
			end
		end
	end
	local chosen = cell or { x = self.random:NextInteger(0, W - 1), z = self.random:NextInteger(0, D - 1) }
	local cx, cz = Maze.cellCenter(self.layout, chosen)
	self:_setPathTo(Vector3.new(cx, 0, cz))
end

function MonsterAI._investigate(self: MonsterAI, position: Vector3)
	if self.state == "Investigate" and self.pathGoal and flat(self.pathGoal - position).Magnitude < 8 then
		return
	end
	self:_setState("Investigate")
	self.pauseUntil = 0
	self:_setPathTo(position)
end

function MonsterAI._beginSearch(self: MonsterAI, around: Vector3, duration: number)
	self:_setState("Search")
	self.searchCenter = around
	self.searchUntil = os.clock() + duration
	self.pauseUntil = 0
	self:_setPathTo(around)
end

function MonsterAI._startChase(self: MonsterAI, player: Player)
	local wasChasing = self.state == "Chase"
	self.target = player
	self.huntLocker = nil
	self:_setState("Chase")
	self.rig.model:SetAttribute("TargetUserId", player.UserId)
	self.path = {}
	local scream = Monsters.SCREAMS[self.rig.kind]
	if scream and not wasChasing and os.clock() - self.lastScream > 10 then
		self.lastScream = os.clock()
		Audio.play(scream, self.rig.head, 2.2, self.random:NextNumber(0.92, 1.05), 170)
	end
end

function MonsterAI._updateChase(self: MonsterAI, now: number)
	local p = self.p
	local root = self.rig.root
	local target = self.target
	if not target or not self:_isActive(target) then
		self:_beginSearch(self.lastSeenPos or root.Position, p.SearchTime)
		return
	end
	if target:GetAttribute("Hiding") then
		local locker = self.sawHide[target]
		if locker then
			self.huntLocker = locker
			self:_setState("HuntLocker")
			self:_setPathTo(locker.outside.Position)
		else
			self:_beginSearch(self.lastSeenPos or root.Position, p.SearchTime)
		end
		return
	end
	-- blind hunters keep tracking a target while it keeps making noise
	if p.HearChaseRange > 0 then
		local proot = rootOf(target)
		local radius = self:_noiseRadius(target)
		if proot and radius > 0 then
			local dist = Maze.distances(self.layout, self:_cellAt(root.Position))
			local c = self:_cellAt(proot.Position)
			if (dist[Maze.key(c.x, c.z)] or math.huge) * self.layout.cellSize <= radius then
				self.lastSeenPos = proot.Position
				self.lastSeenTime = now
			end
		end
	end
	local frenzy = now < self.frenzyUntil
	if not frenzy and now - self.lastSeenTime > p.LoseSightTime then
		self:_beginSearch(self.lastSeenPos or root.Position, p.SearchTime)
		return
	end
	local proot = rootOf(target)
	if not proot then
		return
	end
	-- lunge when it gets close
	if p.LungeRange > 0 and now >= self.nextLunge and (proot.Position - root.Position).Magnitude < p.LungeRange then
		self.lungeUntil = now + 1.1
		self.nextLunge = now + 4
		self:_updateSpeed()
		task.delay(1.15, function()
			if not self.destroyed then
				self:_updateSpeed()
			end
		end)
	end
	-- for a moment after losing sight it still "knows" where you went
	local goal = if frenzy or now - self.lastSeenTime < 1 then proot.Position else (self.lastSeenPos or proot.Position)
	self:_moveToward(goal, now)
end

function MonsterAI._updateHuntLocker(self: MonsterAI)
	local root = self.rig.root
	local locker = self.huntLocker
	local victim = if locker then locker.occupant else nil
	if not locker or not victim or not self:_isActive(victim) then
		self.huntLocker = nil
		self:_beginSearch(root.Position, 6)
		return
	end
	if flat(locker.outside.Position - root.Position).Magnitude < 4.5 then
		self.huntLocker = nil
		self.interactables:leave(victim, true) -- yank them out
		self:_catch(victim)
		return
	end
	if #self.path == 0 then
		self:_setPathTo(locker.outside.Position)
	end
	self:_followPath()
end

function MonsterAI._updateSearch(self: MonsterAI, now: number)
	if now > self.searchUntil then
		self:_setState("Wander")
		self:_pickWanderTarget()
		return
	end
	if now < self.pauseUntil then
		return
	end
	if self:_followPath() then
		self.pauseUntil = now + self.random:NextNumber(0.8, 2.2) -- stop... listen...
		local c = self:_cellAt(self.searchCenter)
		local nx = math.clamp(c.x + self.random:NextInteger(-2, 2), 0, self.layout.width - 1)
		local nz = math.clamp(c.z + self.random:NextInteger(-2, 2), 0, self.layout.depth - 1)
		local cx, cz = Maze.cellCenter(self.layout, { x = nx, z = nz })
		self:_setPathTo(Vector3.new(cx, 0, cz))
	end
end

function MonsterAI._catch(self: MonsterAI, player: Player)
	local previous = self.state
	self:_setState("Kill")
	self.sawHide[player] = nil
	self.target = nil
	self.path = {}
	local root = self.rig.root
	self.humanoid:MoveTo(root.Position)
	root.Anchored = true
	local proot = rootOf(player)
	if proot then
		proot.Anchored = true
		local facing = flat(proot.Position - root.Position)
		if facing.Magnitude > 0.1 then
			self.rig.model:PivotTo(CFrame.lookAt(root.Position, root.Position + facing))
		end
	end
	self.rig.model:SetAttribute("TargetUserId", player.UserId)
	self.hooks.onCaught(player, self.rig.model)
	task.delay(2.8, function()
		if self.destroyed then
			return
		end
		if self.p.Statue then
			self.frozen = false
			self:_release()
			self:_setState(if previous == "Frozen" then "Stalk" else previous)
			return
		end
		self:_release()
		self:_beginSearch(root.Position, 6)
	end)
end

function MonsterAI._tryApparition(self: MonsterAI)
	local p = self.p
	local now = os.clock()
	self.nextApparition = now + self.random:NextNumber(p.ApparitionMin, p.ApparitionMax)
	if not p.Apparitions then
		return
	end
	local candidates = {}
	for _, player in self.hooks.getPlayers() do
		if not player:GetAttribute("Hiding") and rootOf(player) then
			table.insert(candidates, player)
		end
	end
	if #candidates == 0 then
		return
	end
	local player = candidates[self.random:NextInteger(1, #candidates)]
	local proot = rootOf(player) :: BasePart
	local pc = self:_cellAt(proot.Position)
	local look = flat(proot.CFrame.LookVector)
	local best: Maze.Cell? = nil
	local bestScore = -math.huge
	-- down a straight corridor, preferably the one they're facing
	for _, d in Maze.DIRS do
		local run = Maze.straightRun(self.layout, pc, d, 7)
		if #run >= 3 then
			local score = look:Dot(Vector3.new(Maze.DX[d], 0, Maze.DZ[d])) + self.random:NextNumber() * 0.4
			if score > bestScore then
				bestScore = score
				best = run[math.min(#run, self.random:NextInteger(3, 6))]
			end
		end
	end
	if not best then
		return
	end
	local cx, cz = Maze.cellCenter(self.layout, best)
	local pos = Vector3.new(cx, self.rig.rootHeight, cz)
	self.rig.model:PivotTo(CFrame.lookAt(pos, Vector3.new(proot.Position.X, pos.Y, proot.Position.Z)))
	self.apparitionTarget = player
	self.apparitionEnds = now + 7
	self:_setState("Apparition")
end

function MonsterAI._updateApparition(self: MonsterAI)
	local player = self.apparitionTarget
	local proot = if player then rootOf(player) else nil
	local root = self.rig.root
	if not player or not proot or not self:_isActive(player) or os.clock() > self.apparitionEnds or flat(proot.Position - root.Position).Magnitude < 24 then
		self:_vanish()
		return
	end
	local pos = root.Position
	self.rig.model:PivotTo(CFrame.lookAt(pos, Vector3.new(proot.Position.X, pos.Y, proot.Position.Z)))
end

function MonsterAI._vanish(self: MonsterAI)
	Remotes.Apparition:FireAllClients(self.rig.root.Position)
	self.apparitionTarget = nil
	self:_park()
	self:_setState("Dormant")
end

function MonsterAI._checkStuck(self: MonsterAI, now: number)
	if now < self.stuckCheckAt then
		return
	end
	self.stuckCheckAt = now + 2
	local pos = self.rig.root.Position
	local moving = self.humanoid.WalkSpeed > 0 and #self.path > 0 and now >= self.pauseUntil and not self.rig.root.Anchored
	if moving and flat(pos - self.stuckPos).Magnitude < 1.5 then
		self.stuckCount += 1
		if self.stuckCount >= 2 then
			-- still stuck: hop to the next waypoint
			local p = self.path[self.pathIndex]
			if p then
				self.rig.model:PivotTo(CFrame.new(p.X, self.rig.rootHeight, p.Z) * self.rig.root.CFrame.Rotation)
			end
			self.stuckCount = 0
		elseif self.pathGoal then
			self:_setPathTo(self.pathGoal)
		end
	else
		self.stuckCount = 0
	end
	self.stuckPos = pos
end

-- Statue ------------------------------------------------------------------------

-- Is any player looking at it right now? (Camera direction comes from the clients.)
function MonsterAI._isWatched(self: MonsterAI): boolean
	if os.clock() < self.blinkUntil then
		return false -- everyone's eyes are closed
	end
	local head = self.rig.head
	local body = self.rig.root.Position + Vector3.new(0, 1.5, 0)
	for _, player in self.hooks.getPlayers() do
		local phead = headOf(player)
		if phead and not player:GetAttribute("Hiding") then
			local look = self.hooks.getLook(player)
			if not look then
				local proot = rootOf(player)
				look = if proot then proot.CFrame.LookVector else nil
			end
			if look then
				for _, point in { head.Position, body } do
					local to = point - phead.Position
					if to.Magnitude < 170 and look.Unit:Dot(to.Unit) > 0.55 then
						if not workspace:Raycast(phead.Position, to, self.sightParams) then
							return true
						end
					end
				end
			end
		end
	end
	return false
end

function MonsterAI._thinkStatue(self: MonsterAI, now: number)
	local p = self.p
	if not self.awake then
		if now >= self.awakeAt then
			self:awaken()
		end
		return
	end
	if self.state == "Kill" then
		return
	end
	-- every so often, everybody blinks
	if now >= self.nextBlink then
		self.nextBlink = now + self.random:NextNumber(p.BlinkMin, p.BlinkMax) * (if now < self.frenzyUntil then 0.5 else 1)
		self.blinkUntil = now + p.BlinkTime
		self.hooks.setBlink(true)
		task.delay(p.BlinkTime, function()
			if not self.destroyed then
				self.hooks.setBlink(false)
			end
		end)
	end

	local root = self.rig.root
	if self:_isWatched() then
		if not self.frozen then
			self.frozen = true
			self.humanoid:MoveTo(root.Position)
			root.Anchored = true
			self:_setState("Frozen")
		end
		return
	end
	if self.frozen then
		self.frozen = false
		self:_release()
		self.rig.model:SetAttribute("Pose", self.random:NextInteger(1, #Monsters.STATUE_POSES))
		self:_setState("Stalk")
	end

	-- nobody's looking: go for the nearest player
	local best: Player? = nil
	local bestDist = math.huge
	for _, player in self.hooks.getPlayers() do
		local proot = rootOf(player)
		if proot then
			local d = (proot.Position - root.Position).Magnitude
			if d < bestDist then
				best, bestDist = player, d
			end
		end
	end
	if not best then
		return
	end
	local proot = rootOf(best) :: BasePart
	if bestDist < p.CatchDistance + 0.5 then
		self:_catch(best)
		return
	end
	-- stone grinding when it moves close to someone
	if bestDist < 45 and now - self.lastGrind > 1.6 then
		self.lastGrind = now
		Audio.play("StatueGrind", root, 1.4, self.random:NextNumber(0.85, 1.1), 70)
	end
	self.rig.model:SetAttribute("TargetUserId", best.UserId)
	self:_moveToward(proot.Position, now)
end

-- Main loop ------------------------------------------------------------------------

function MonsterAI._think(self: MonsterAI)
	if self.destroyed then
		return
	end
	local p = self.p
	local now = os.clock()

	if p.Statue then
		self:_thinkStatue(now)
		return
	end

	local state = self.state
	if state == "Dormant" then
		if now >= self.awakeAt then
			self:awaken()
		elseif now >= self.nextApparition then
			self:_tryApparition()
		end
		return
	elseif state == "Apparition" then
		if now >= self.awakeAt then
			self:awaken()
		else
			self:_updateApparition()
		end
		return
	elseif state == "Kill" then
		return
	end

	local root = self.rig.root
	self.interactables:slamOpenNear(root.Position, 8)
	self:_checkStuck(now)

	-- within arm's reach?
	for _, player in self.hooks.getPlayers() do
		if not player:GetAttribute("Hiding") then
			local proot = rootOf(player)
			if proot and flat(proot.Position - root.Position).Magnitude < p.CatchDistance and math.abs(proot.Position.Y - root.Position.Y) < 7 then
				self:_catch(player)
				return
			end
		end
	end

	-- eyes
	local seen, seenPos = self:_lookForPlayers()
	if seen and seenPos and self.state ~= "HuntLocker" then
		if self.state ~= "Chase" or self.target ~= seen then
			self:_startChase(seen)
		end
		self.lastSeenPos = seenPos
		self.lastSeenTime = now
		self.lastContact = now
	end

	local s = self.state
	if s == "Chase" then
		self:_updateChase(now)
	elseif s == "HuntLocker" then
		self:_updateHuntLocker()
	elseif s == "Investigate" then
		if self:_followPath() then
			self:_beginSearch(root.Position, 7)
		end
	elseif s == "Search" then
		self:_updateSearch(now)
	elseif s == "Wander" then
		if now >= self.pauseUntil and self:_followPath() then
			self.pauseUntil = now + self.random:NextNumber(0.5, 2.5)
			self:_pickWanderTarget()
		end
	end

	-- ears (only when it isn't already after someone)
	if self.state == "Wander" or self.state == "Search" or self.state == "Investigate" then
		local heard, heardDist, heardPlayer = self:_listen()
		if heard then
			self.lastContact = now
			if heardPlayer and p.HearChaseRange > 0 and heardDist <= p.HearChaseRange then
				-- blind hunters lock on to close sounds
				self.lastSeenPos = heard
				self.lastSeenTime = now
				self:_startChase(heardPlayer)
			else
				self:_investigate(heard)
			end
		end
	end
end

return MonsterAI
