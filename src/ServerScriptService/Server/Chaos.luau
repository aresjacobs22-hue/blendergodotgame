--!strict
-- The curse and the chaos. Every round:
--   * one CURSE bends the rules for the whole night (see Shared/Curses):
--       blackout  most lamps are dead           shifting  walls slide up and down
--       hunted    it hears your heartbeat        phantoms  fake monsters (client side)
--       silent    it makes no sound              fog       you can't see far (lighting)
--   * random EVENTS go off every minute or so: the power fails, a phone rings near
--     you (answer it and you hear where it is, mostly; ignore it and it comes to the
--     phone), every door slams shut, a locker bangs, or you hear it charge at you when
--     nothing's there.
--   * the RAGE: when the way out opens (or at 5 AM) it gets furious.
-- It also listens for players letting their breath out inside a locker.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Audio = require(ReplicatedStorage.Shared.Audio)
local Curses = require(ReplicatedStorage.Shared.Curses)
local Maze = require(ReplicatedStorage.Shared.Maze)
local Nights = require(ReplicatedStorage.Shared.Nights)
local Dressing = require(script.Parent.Dressing)
local Interactables = require(script.Parent.Interactables)
local MonsterAI = require(script.Parent.MonsterAI)
local WorldBuilder = require(script.Parent.WorldBuilder)

local Remotes = ReplicatedStorage.Remotes
local GameState = ReplicatedStorage.GameState

export type Ctx = {
	night: Nights.Night,
	layout: Maze.Layout,
	world: WorldBuilder.World,
	interactables: Interactables.Interactables,
	monster: MonsterAI.MonsterAI,
	curse: Curses.Curse,
	getPlayers: () -> { Player }, -- players still in the round
	isAlive: (player: Player) -> boolean,
	notifyAll: (text: string, style: string?) -> (),
}

export type Chaos = { destroy: () -> (), shift: () -> (), event: (id: string) -> boolean }

local Chaos = {}

local rootOf = Interactables.rootOf

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

function Chaos.start(ctx: Ctx): Chaos
	local layout = ctx.layout
	local world = ctx.world
	local wctx = world.ctx
	local monster = ctx.monster
	local random = Random.new(layout.seed + 31)
	local alive = true
	local connections: { RBXScriptConnection } = {}
	local folder = Instance.new("Folder")
	folder.Name = "Chaos"
	folder.Parent = world.model

	local function loop(first: number, minWait: number, maxWait: number, fn: () -> ())
		task.spawn(function()
			task.wait(first)
			while alive do
				fn()
				task.wait(random:NextNumber(minWait, maxWait))
			end
		end)
	end

	local function visiblePlayers(): { Player }
		local out = {}
		for _, p in ctx.getPlayers() do
			if p:GetAttribute("Hiding") ~= true and rootOf(p) then
				table.insert(out, p)
			end
		end
		return out
	end

	-- Curse: BLACKOUT ------------------------------------------------------------
	local function blackout()
		for _, lamp in world.lamps do
			if lamp.cell and random:NextNumber() < 0.7 then
				lamp.light.Enabled = false
				lamp.bulb:SetAttribute("Dead", true)
				lamp.bulb.Color = lamp.bulb.Color:Lerp(Color3.new(0, 0, 0), 0.85)
			end
		end
	end

	-- Curse: SHIFTING WALLS --------------------------------------------------------
	type Shifter = { key: string, part: BasePart, up: CFrame, down: CFrame, raised: boolean }
	local shifters: { Shifter } = {}

	local function buildShifters()
		local rooms: { [string]: boolean } = {}
		for _, block in layout.roomBlocks do
			for _, c in block do
				rooms[Maze.key(c.x, c.z)] = true
			end
		end
		local edges = Dressing.openEdges(wctx, rooms)
		for i = #edges, 2, -1 do
			local j = random:NextInteger(1, i)
			edges[i], edges[j] = edges[j], edges[i]
		end
		local C, H, T = wctx.C, wctx.H, wctx.T
		local entrance = layout.entrance
		for _, e in edges do
			if #shifters >= 16 then
				break
			end
			local nx, nz = e.x + Maze.DX[e.dir], e.z + Maze.DZ[e.dir]
			local touchesEntrance = (e.x == entrance.x and e.z == entrance.z) or (nx == entrance.x and nz == entrance.z)
			if not touchesEntrance then
				local frame = wctx.edgeFrame(e.x, e.z, e.dir)
				local down = frame * CFrame.new(0, -H / 2 - 0.6, 0)
				local up = frame * CFrame.new(0, H / 2, 0)
				local part: BasePart = wctx.styled(folder, "ShiftingWall", Vector3.new(C - T, H, T), down, world.theme.wall)
				table.insert(shifters, { key = Maze.edgeKey(e.x, e.z, e.dir), part = part, up = up, down = down, raised = false })
			end
		end
	end

	local function everyCellReachable(): boolean
		local count = 0
		for _ in Maze.distances(layout, layout.entrance) do
			count += 1
		end
		return count >= layout.width * layout.depth
	end

	local function someoneIn(s: Shifter): boolean
		local mid = s.up.Position
		local reach = wctx.C * 0.5 + 1.5
		for _, p in ctx.getPlayers() do
			local r = rootOf(p)
			if r and flat(r.Position - mid).Magnitude < reach then
				return true
			end
		end
		return flat(monster.rig.root.Position - mid).Magnitude < reach + 1
	end

	local function moveWall(s: Shifter, raise: boolean)
		s.raised = raise
		layout.edges[s.key] = if raise then "wall" else "open"
		TweenService:Create(s.part, TweenInfo.new(2.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { CFrame = if raise then s.up else s.down }):Play()
		Audio.play("WallShift", s.part, 1.5, random:NextNumber(0.9, 1.1), 120)
	end

	local firstShift = true
	local function shift()
		for _, s in shifters do
			if s.raised then
				moveWall(s, false)
			end
		end
		local order = table.clone(shifters)
		for i = #order, 2, -1 do
			local j = random:NextInteger(1, i)
			order[i], order[j] = order[j], order[i]
		end
		local wanted = random:NextInteger(3, 5)
		local raised = 0
		for _, s in order do
			if raised >= wanted then
				break
			end
			if not someoneIn(s) then
				layout.edges[s.key] = "wall"
				if everyCellReachable() then
					raised += 1
					moveWall(s, true)
				else
					layout.edges[s.key] = "open"
				end
			end
		end
		monster:mapChanged()
		if firstShift and raised > 0 then
			firstShift = false
			ctx.notifyAll("You hear stone grinding. The walls are moving.", "danger")
		end
	end

	-- Curse: HUNTED ---------------------------------------------------------------------
	local function heartbeatHeard()
		if not monster.awake then
			return
		end
		local players = visiblePlayers()
		if #players == 0 then
			return
		end
		local p = players[random:NextInteger(1, #players)]
		local r = rootOf(p)
		if r then
			monster:hearNoise(r.Position, 100000)
			Remotes.Chaos:FireClient(p, "hunted")
		end
	end

	-- Events --------------------------------------------------------------------------------
	-- Where the voice on the phone makes you hear it: where it really is, except when the
	-- voice lies (then somewhere random). Nothing while it's still asleep.
	local function phoneHint(): Vector3?
		local mroot = monster.rig.root
		if not monster.awake or mroot.Position.Y < -100 then
			return nil
		end
		if random:NextNumber() < 0.2 then
			local fake = wctx.cellCenter(random:NextInteger(0, layout.width - 1), random:NextInteger(0, layout.depth - 1))
			return fake + Vector3.new(0, 4, 0)
		end
		return mroot.Position
	end

	local function phone(): boolean
		local players = visiblePlayers()
		if #players == 0 then
			return false
		end
		local p = players[random:NextInteger(1, #players)]
		local r = rootOf(p) :: BasePart
		local pc = Maze.cellOf(layout, r.Position.X, r.Position.Z)
		local dist = Maze.distances(layout, pc)
		local options: { { x: number, z: number, side: string } } = {}
		for z = 0, layout.depth - 1 do
			for x = 0, layout.width - 1 do
				local d = dist[Maze.key(x, z)]
				if d and d >= 2 and d <= 5 then
					for _, side in wctx.wallSides(x, z) do
						table.insert(options, { x = x, z = z, side = side })
					end
				end
			end
		end
		if #options == 0 then
			return false
		end
		local spot = options[random:NextInteger(1, #options)]
		local wall = wctx.sideFrame(spot.x, spot.z, spot.side)
		local model = Instance.new("Model")
		model.Name = "Phone"
		model.Parent = folder
		local body = wctx.part(model, "PhoneBody", Vector3.new(1.3, 1.9, 0.5), wall * CFrame.new(random:NextNumber(-2, 2), 5.2, -0.3), Enum.Material.SmoothPlastic, Color3.fromRGB(28, 26, 26), nil)
		local handset = wctx.decor(wctx.part(model, "Handset", Vector3.new(0.4, 1.7, 0.4), body.CFrame * CFrame.new(0.75, 0, -0.1), Enum.Material.SmoothPlastic, Color3.fromRGB(22, 20, 20), nil))
		wctx.decor(wctx.part(model, "Cord", Vector3.new(0.08, 2.2, 0.08), handset.CFrame * CFrame.new(0, -1.9, 0), Enum.Material.SmoothPlastic, Color3.fromRGB(15, 15, 15), nil))
		local bulb = wctx.decor(wctx.part(model, "RingLight", Vector3.new(0.25, 0.25, 0.25), body.CFrame * CFrame.new(0, 0.7, -0.27), Enum.Material.Neon, Color3.fromRGB(255, 60, 40), Enum.PartType.Ball))
		local glow = Instance.new("PointLight")
		glow.Range = 7
		glow.Brightness = 1.2
		glow.Color = Color3.fromRGB(255, 60, 40)
		glow.Parent = bulb
		local ring = Audio.create("PhoneRingLoop", body, 1.5)
		if ring then
			ring.RollOffMode = Enum.RollOffMode.InverseTapered
			ring.RollOffMinDistance = 8
			ring.RollOffMaxDistance = 130
			ring:Play()
		end
		ctx.notifyAll("Somewhere close, a phone is ringing.")
		local answered = false
		local prompt = Interactables.prompt(body, "Answer", "Phone", 0.3, 8)
		local function hangUp()
			answered = true
			prompt.Enabled = false
			glow.Enabled = false
			bulb.Color = Color3.fromRGB(40, 10, 8)
			if ring then
				ring:Destroy()
			end
		end
		prompt.Triggered:Connect(function(player: Player)
			if answered or not alive or not ctx.isAlive(player) then
				return
			end
			hangUp()
			Audio.play("PhonePickup", body, 1, 1, 40)
			Remotes.Chaos:FireClient(player, "phone", phoneHint())
		end)
		task.delay(20, function()
			if answered or not alive then
				return
			end
			hangUp()
			-- nobody picked up. Something else heard it ringing.
			monster:hearNoise(body.Position, 240)
		end)
		Debris:AddItem(model, 90)
		return true
	end

	local function lockerBang(): boolean
		local players = visiblePlayers()
		if #players == 0 or #ctx.interactables.lockers == 0 then
			return false
		end
		local r = rootOf(players[random:NextInteger(1, #players)]) :: BasePart
		local best: Interactables.Locker? = nil
		local bestDist = 60
		for _, l in ctx.interactables.lockers do
			local d = (l.anchor.Position - r.Position).Magnitude
			if not l.occupant and d < bestDist and d > 8 then
				best, bestDist = l, d
			end
		end
		if not best then
			return false
		end
		Audio.play("LockerBang", best.anchor, 1.8, random:NextNumber(0.9, 1.1), 90)
		return true
	end

	local function falseChase(): boolean
		if monster.p.Statue then
			return false
		end
		local players = visiblePlayers()
		if #players == 0 then
			return false
		end
		Remotes.Chaos:FireClient(players[random:NextInteger(1, #players)], "falseChase")
		return true
	end

	local function powerFailure(): boolean
		if GameState:GetAttribute("Blackout") == true then
			return false
		end
		GameState:SetAttribute("Blackout", true)
		ctx.notifyAll("The power is failing...", "danger")
		task.delay(random:NextNumber(8, 12), function()
			if alive then
				GameState:SetAttribute("Blackout", false)
			end
		end)
		return true
	end

	local function slam(): boolean
		if ctx.interactables:slamAll() == 0 then
			return false
		end
		ctx.notifyAll("Every door in the place just slammed shut.", "danger")
		return true
	end

	local EVENTS: { [string]: () -> boolean } = {
		blackout = powerFailure,
		phone = phone,
		slam = slam,
		falseChase = falseChase,
		lockerBang = lockerBang,
	}
	local WEIGHTS: { { id: string, weight: number } } = {
		{ id = "blackout", weight = 3 },
		{ id = "phone", weight = 4 },
		{ id = "slam", weight = 2 },
		{ id = "falseChase", weight = 2 },
		{ id = "lockerBang", weight = 2 },
	}
	local lastEvent = ""

	local function randomEvent()
		local total = 0
		for _, w in WEIGHTS do
			if w.id ~= lastEvent then
				total += w.weight
			end
		end
		for _ = 1, 4 do
			local pick = random:NextNumber() * total
			for _, w in WEIGHTS do
				local id = w.id
				if id ~= lastEvent then
					pick -= w.weight
					if pick <= 0 then
						if EVENTS[id]() then
							lastEvent = id
							return
						end
						break
					end
				end
			end
		end
	end

	-- Rage --------------------------------------------------------------------------------
	local raged = false
	local function rage()
		if raged or not alive then
			return
		end
		raged = true
		GameState:SetAttribute("Rage", true)
		ctx.notifyAll("It's FURIOUS.", "danger")
		monster:frenzy(12, nil)
		if not monster.silent then
			Audio.play("RageSting", monster.rig.head, 2.2, 1, 260)
		end
	end
	table.insert(connections, GameState:GetAttributeChangedSignal("ExitOpen"):Connect(function()
		if GameState:GetAttribute("ExitOpen") == true then
			task.delay(1.5, rage)
		end
	end))
	table.insert(connections, GameState:GetAttributeChangedSignal("Hour"):Connect(function()
		local hour = GameState:GetAttribute("Hour")
		if typeof(hour) == "number" and hour >= 5 then
			rage()
		end
	end))

	-- Holding your breath -----------------------------------------------------------------
	local lastBreath: { [Player]: number } = {}
	table.insert(connections, Remotes.Breath.OnServerEvent:Connect(function(player: Player)
		local now = os.clock()
		if not alive or not ctx.isAlive(player) or now - (lastBreath[player] or -math.huge) < 4 then
			return
		end
		lastBreath[player] = now
		local locker = ctx.interactables:lockerOf(player)
		if locker and monster.awake and (monster.rig.root.Position - locker.inside.Position).Magnitude < 22 then
			monster:revealHider(player, locker)
		end
	end))

	-- Start ---------------------------------------------------------------------------------
	local curse = ctx.curse.id
	if curse == "blackout" then
		blackout()
	elseif curse == "silent" then
		monster:setSilent(true)
	elseif curse == "shifting" then
		buildShifters()
		loop(25, 36, 50, shift)
	elseif curse == "hunted" then
		loop(55, 36, 52, heartbeatHeard)
	end
	loop(random:NextNumber(55, 75), 50, 85, randomEvent)

	return {
		destroy = function()
			alive = false
			for _, c in connections do
				c:Disconnect()
			end
			GameState:SetAttribute("Blackout", false)
			GameState:SetAttribute("Rage", false)
		end,
		shift = shift,
		event = function(id: string): boolean
			local fn = EVENTS[id]
			return fn ~= nil and fn()
		end,
	}
end

return Chaos
