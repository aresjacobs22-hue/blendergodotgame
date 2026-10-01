--!strict
-- Maze layout generation + grid queries (BFS, paths, straight corridors).
-- Pure Luau with no Roblox APIs, so it runs under Lune for unit tests.
--
-- Grid: cells (x, z) with x in [0, width) and z in [0, depth). Cell (x, z) owns its
-- north (+z) and east (+x) edge; its south/west edges belong to the neighbour, so
-- boundary edges are stored on the virtual cells at x = -1 / z = -1.
--
-- Edge kinds: "wall", "open", "door" (house door), "doorway" (arch, no door),
-- "hole" (broken wall), "exit" (the locked exit door).

export type Cell = { x: number, z: number }
export type Locker = { x: number, z: number, side: string, house: boolean }
export type Writing = { x: number, z: number, side: string, text: string }
export type Layout = {
	seed: number,
	width: number,
	depth: number,
	cellSize: number,
	edges: { [string]: string },
	rooms: { [string]: string },
	house: { x0: number, z0: number, w: number, d: number },
	entrance: Cell,
	exitCell: Cell,
	keys: { Cell },
	batteries: { Cell },
	lockers: { Locker },
	lights: { Cell },
	writings: { Writing },
	deadEnds: { Cell },
	monsterSpawn: Cell,
	code: string,
}

export type MazeConfig = {
	CellSize: number,
	Width: number,
	Depth: number,
	HouseWidth: number,
	HouseDepth: number,
	DeadEndBraid: number,
	ExtraOpenings: number,
	KeyCount: number,
	BatteryCount: number,
	MazeLockerCount: number,
	WritingCount: number,
}

type Rng = (number?, number?) -> number

local Maze = {}

Maze.DIRS = { "N", "E", "S", "W" }
Maze.DX = { N = 0, E = 1, S = 0, W = -1 } :: { [string]: number }
Maze.DZ = { N = 1, E = 0, S = -1, W = 0 } :: { [string]: number }
Maze.OPPOSITE = { N = "S", S = "N", E = "W", W = "E" } :: { [string]: string }

local DIRS = Maze.DIRS
local DX = Maze.DX
local DZ = Maze.DZ

local PASSABLE: { [string]: boolean } = { open = true, door = true, doorway = true, hole = true }

-- The house blueprint, rows from south (by the exit) to north (towards the maze).
local HOUSE_ROOMS = {
	{ "living", "living", "hall", "kitchen", "kitchen" },
	{ "living", "living", "hall", "kitchen", "kitchen" },
	{ "bedroom", "bedroom", "hall", "study", "study" },
}

-- { relX, relZ, side, kind }
local HOUSE_LINKS: { { any } } = {
	{ 2, 1, "W", "door" }, -- hall -> living room
	{ 2, 2, "W", "door" }, -- hall -> bedroom
	{ 2, 1, "E", "doorway" }, -- hall -> kitchen
	{ 2, 2, "E", "door" }, -- hall -> study
	{ 4, 1, "N", "doorway" }, -- kitchen -> study
	{ 2, 2, "N", "doorway" }, -- hall -> maze (main entrance)
	{ 0, 2, "N", "hole" }, -- bedroom -> maze (broken wall)
	{ 4, 0, "E", "hole" }, -- kitchen -> maze (broken wall)
	{ 2, 0, "S", "exit" }, -- the way out
}

-- Hiding spots inside the house: { relX, relZ, side }
local HOUSE_LOCKERS: { { any } } = {
	{ 1, 2, "S" }, -- bedroom wardrobe
	{ 4, 2, "N" }, -- study wardrobe
}

local WRITINGS = {
	"IT SEES YOU",
	"DON'T RUN",
	"FOUR KEYS\nFOUR NUMBERS",
	"HIDE",
	"IT HEARS YOUR FEET",
	"WHERE DID THE COLOR GO",
	"I WOKE UP HERE TOO",
	"TURN OFF YOUR LIGHT",
	"LISTEN FOR THE CLICKING",
	"IT WAS ME ALL ALONG",
	"NOT ALONE",
	"DON'T LOOK BEHIND YOU",
	"WAKE UP WAKE UP WAKE UP",
	"THE DOOR IS A LIE",
	"IT KNOWS THE LOCKERS",
	"STAY QUIET",
	"NO WAY OUT",
	"5 3 4 3", -- a red herring
}

function Maze.key(x: number, z: number): string
	return x .. "," .. z
end

function Maze.edgeKey(x: number, z: number, dir: string): string
	if dir == "N" then
		return x .. "," .. z .. ",N"
	elseif dir == "E" then
		return x .. "," .. z .. ",E"
	elseif dir == "S" then
		return x .. "," .. (z - 1) .. ",N"
	else
		return (x - 1) .. "," .. z .. ",E"
	end
end

-- Parses an edge key back into its owner cell and N/E direction.
function Maze.parseEdgeKey(key: string): (number, number, string)
	local xs, zs, dir = string.match(key, "^(%-?%d+),(%-?%d+),([NE])$")
	assert(xs and zs and dir, "bad edge key " .. key)
	return tonumber(xs) :: number, tonumber(zs) :: number, dir
end

function Maze.getEdge(layout: Layout, x: number, z: number, dir: string): string
	return layout.edges[Maze.edgeKey(x, z, dir)] or "wall"
end

function Maze.isPassable(kind: string): boolean
	return PASSABLE[kind] == true
end

function Maze.inBounds(layout: Layout, x: number, z: number): boolean
	return x >= 0 and x < layout.width and z >= 0 and z < layout.depth
end

function Maze.isHouse(layout: Layout, x: number, z: number): boolean
	return layout.rooms[Maze.key(x, z)] ~= nil
end

function Maze.roomOf(layout: Layout, x: number, z: number): string?
	return layout.rooms[Maze.key(x, z)]
end

function Maze.neighbors(layout: Layout, x: number, z: number): { Cell }
	local result = {}
	for _, d in DIRS do
		local nx, nz = x + DX[d], z + DZ[d]
		if Maze.inBounds(layout, nx, nz) and PASSABLE[Maze.getEdge(layout, x, z, d)] then
			table.insert(result, { x = nx, z = nz })
		end
	end
	return result
end

function Maze.passableCount(layout: Layout, x: number, z: number): number
	return #Maze.neighbors(layout, x, z)
end

-- Breadth-first step distances from `from` to every reachable cell.
function Maze.distances(layout: Layout, from: Cell): { [string]: number }
	local dist: { [string]: number } = { [Maze.key(from.x, from.z)] = 0 }
	local queue = { from }
	local head = 1
	while head <= #queue do
		local c = queue[head]
		head += 1
		local d = dist[Maze.key(c.x, c.z)]
		for _, n in Maze.neighbors(layout, c.x, c.z) do
			local k = Maze.key(n.x, n.z)
			if dist[k] == nil then
				dist[k] = d + 1
				table.insert(queue, n)
			end
		end
	end
	return dist
end

-- Shortest path of cells from `from` to `to` (both included), or nil.
function Maze.findPath(layout: Layout, from: Cell, to: Cell): { Cell }?
	local startKey = Maze.key(from.x, from.z)
	local goalKey = Maze.key(to.x, to.z)
	if startKey == goalKey then
		return { from }
	end
	local parent: { [string]: Cell } = {}
	local seen: { [string]: boolean } = { [startKey] = true }
	local queue = { from }
	local head = 1
	while head <= #queue do
		local c = queue[head]
		head += 1
		for _, n in Maze.neighbors(layout, c.x, c.z) do
			local k = Maze.key(n.x, n.z)
			if not seen[k] then
				seen[k] = true
				parent[k] = c
				if k == goalKey then
					local path = { n }
					local cur = c
					while Maze.key(cur.x, cur.z) ~= startKey do
						table.insert(path, 1, cur)
						cur = parent[Maze.key(cur.x, cur.z)]
					end
					table.insert(path, 1, from)
					return path
				end
				table.insert(queue, n)
			end
		end
	end
	return nil
end

-- Cells reachable by walking in a straight line (excluding the start cell).
function Maze.straightRun(layout: Layout, from: Cell, dir: string, maxSteps: number): { Cell }
	local run = {}
	local x, z = from.x, from.z
	for _ = 1, maxSteps do
		if not PASSABLE[Maze.getEdge(layout, x, z, dir)] then
			break
		end
		x += DX[dir]
		z += DZ[dir]
		if not Maze.inBounds(layout, x, z) then
			break
		end
		table.insert(run, { x = x, z = z })
	end
	return run
end

function Maze.cellOf(layout: Layout, worldX: number, worldZ: number): Cell
	local x = math.clamp(math.floor(worldX / layout.cellSize), 0, layout.width - 1)
	local z = math.clamp(math.floor(worldZ / layout.cellSize), 0, layout.depth - 1)
	return { x = x, z = z }
end

function Maze.cellCenter(layout: Layout, c: Cell): (number, number)
	return (c.x + 0.5) * layout.cellSize, (c.z + 0.5) * layout.cellSize
end

-- Park-Miller "minimal standard" generator: deterministic everywhere (Roblox + Lune).
function Maze.makeRng(seed: number): Rng
	local state = math.floor(math.abs(seed)) % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	return function(a: number?, b: number?): number
		state = (state * 16807) % 2147483647
		local r = (state - 1) / 2147483646
		if a ~= nil and b ~= nil then
			return a + math.floor(r * (b - a + 1))
		end
		return r
	end
end

local function shuffle<T>(list: { T }, rng: Rng)
	for i = #list, 2, -1 do
		local j = rng(1, i)
		list[i], list[j] = list[j], list[i]
	end
end

local function manhattan(a: Cell, b: Cell): number
	return math.abs(a.x - b.x) + math.abs(a.z - b.z)
end

function Maze.generate(seed: number, cfg: MazeConfig): Layout
	assert(cfg.HouseWidth == 5 and cfg.HouseDepth == 3, "the house blueprint is 5 x 3 cells")
	assert(cfg.Width >= 9 and cfg.Depth >= 6, "maze too small for the house")

	local rng = Maze.makeRng(seed)
	local W, D = cfg.Width, cfg.Depth
	local x0 = math.floor((W - cfg.HouseWidth) / 2)
	local z0 = 0

	local layout: Layout = {
		seed = seed,
		width = W,
		depth = D,
		cellSize = cfg.CellSize,
		edges = {},
		rooms = {},
		house = { x0 = x0, z0 = z0, w = cfg.HouseWidth, d = cfg.HouseDepth },
		entrance = { x = x0 + 2, z = z0 + cfg.HouseDepth },
		exitCell = { x = x0 + 2, z = z0 },
		keys = {},
		batteries = {},
		lockers = {},
		lights = {},
		writings = {},
		deadEnds = {},
		monsterSpawn = { x = 0, z = D - 1 },
		code = "",
	}
	local edges = layout.edges

	local function setEdge(x: number, z: number, dir: string, kind: string)
		edges[Maze.edgeKey(x, z, dir)] = kind
	end

	-- 1. The house: rooms, open floor inside rooms, then doors/holes/exit.
	for rz = 0, cfg.HouseDepth - 1 do
		for rx = 0, cfg.HouseWidth - 1 do
			layout.rooms[Maze.key(x0 + rx, z0 + rz)] = HOUSE_ROOMS[rz + 1][rx + 1]
		end
	end
	for rz = 0, cfg.HouseDepth - 1 do
		for rx = 0, cfg.HouseWidth - 1 do
			local room = HOUSE_ROOMS[rz + 1][rx + 1]
			if rx + 1 < cfg.HouseWidth and HOUSE_ROOMS[rz + 1][rx + 2] == room then
				setEdge(x0 + rx, z0 + rz, "E", "open")
			end
			if rz + 1 < cfg.HouseDepth and HOUSE_ROOMS[rz + 2][rx + 1] == room then
				setEdge(x0 + rx, z0 + rz, "N", "open")
			end
		end
	end
	for _, link in HOUSE_LINKS do
		setEdge(x0 + (link[1] :: number), z0 + (link[2] :: number), link[3] :: string, link[4] :: string)
	end

	local function isMaze(x: number, z: number): boolean
		return Maze.inBounds(layout, x, z) and layout.rooms[Maze.key(x, z)] == nil
	end

	-- 2. Carve the maze with a randomized depth-first search from the house entrance.
	local visited: { [string]: boolean } = {}
	local stack: { Cell } = { layout.entrance }
	visited[Maze.key(layout.entrance.x, layout.entrance.z)] = true
	while #stack > 0 do
		local c = stack[#stack]
		local options = {}
		for _, d in DIRS do
			local nx, nz = c.x + DX[d], c.z + DZ[d]
			if isMaze(nx, nz) and not visited[Maze.key(nx, nz)] then
				table.insert(options, d)
			end
		end
		if #options == 0 then
			table.remove(stack)
		else
			local d = options[rng(1, #options)]
			setEdge(c.x, c.z, d, "open")
			local n = { x = c.x + DX[d], z = c.z + DZ[d] }
			visited[Maze.key(n.x, n.z)] = true
			table.insert(stack, n)
		end
	end

	local mazeCells: { Cell } = {}
	for z = 0, D - 1 do
		for x = 0, W - 1 do
			if isMaze(x, z) then
				table.insert(mazeCells, { x = x, z = z })
			end
		end
	end

	local function openRandomWall(c: Cell): boolean
		local options = {}
		for _, d in DIRS do
			if isMaze(c.x + DX[d], c.z + DZ[d]) and Maze.getEdge(layout, c.x, c.z, d) == "wall" then
				table.insert(options, d)
			end
		end
		if #options == 0 then
			return false
		end
		setEdge(c.x, c.z, options[rng(1, #options)], "open")
		return true
	end

	-- 3. Braid: knock through some dead ends and a few random walls so there are loops
	--    to run around. A pure tree maze is a death trap with a monster in it.
	for _, c in mazeCells do
		if Maze.passableCount(layout, c.x, c.z) == 1 and rng() < cfg.DeadEndBraid then
			openRandomWall(c)
		end
	end
	for _ = 1, cfg.ExtraOpenings do
		openRandomWall(mazeCells[rng(1, #mazeCells)])
	end

	-- 4. Place things.
	local dist = Maze.distances(layout, layout.entrance)
	local used: { [string]: boolean } = {}

	local deadEnds: { Cell } = {}
	for _, c in mazeCells do
		if Maze.passableCount(layout, c.x, c.z) == 1 then
			table.insert(deadEnds, c)
		end
	end
	layout.deadEnds = deadEnds

	-- Keys: far from the house and spread apart (greedy farthest-point sampling).
	while #layout.keys < cfg.KeyCount do
		local best: Cell? = nil
		local bestScore = -math.huge
		for _, c in deadEnds do
			local k = Maze.key(c.x, c.z)
			if not used[k] and (dist[k] or 0) >= 5 then
				local sep = 0
				if #layout.keys > 0 then
					sep = math.huge
					for _, other in layout.keys do
						sep = math.min(sep, manhattan(c, other))
					end
				end
				local score = (dist[k] or 0) * 0.6 + sep * 1.5 + rng() * 0.5
				if score > bestScore then
					best, bestScore = c, score
				end
			end
		end
		if best == nil then
			-- not enough dead ends: fall back to the farthest free maze cell
			for _, c in mazeCells do
				local k = Maze.key(c.x, c.z)
				if not used[k] and (dist[k] or 0) > bestScore then
					best, bestScore = c, dist[k] or 0
				end
			end
		end
		local chosen = best :: Cell
		used[Maze.key(chosen.x, chosen.z)] = true
		table.insert(layout.keys, chosen)
	end

	-- Batteries: leftover dead ends first, then random corridor cells.
	local pool = table.clone(deadEnds)
	shuffle(pool, rng)
	local extra = table.clone(mazeCells)
	shuffle(extra, rng)
	for _, c in extra do
		table.insert(pool, c)
	end
	for _, c in pool do
		if #layout.batteries >= cfg.BatteryCount then
			break
		end
		local k = Maze.key(c.x, c.z)
		if not used[k] and (dist[k] or 0) >= 2 then
			used[k] = true
			table.insert(layout.batteries, c)
		end
	end

	-- Hiding lockers: fixed ones in the house, spread-out ones along maze corridors.
	local lockerSides: { [string]: boolean } = {}
	for _, l in HOUSE_LOCKERS do
		local x, z, side = x0 + (l[1] :: number), z0 + (l[2] :: number), l[3] :: string
		table.insert(layout.lockers, { x = x, z = z, side = side, house = true })
		lockerSides[Maze.key(x, z) .. side] = true
	end
	local corridor = table.clone(mazeCells)
	shuffle(corridor, rng)
	local mazeLockers: { Cell } = {}
	for _, c in corridor do
		if #mazeLockers >= cfg.MazeLockerCount then
			break
		end
		local k = Maze.key(c.x, c.z)
		if not used[k] and Maze.passableCount(layout, c.x, c.z) >= 2 then
			local farEnough = true
			for _, other in mazeLockers do
				if manhattan(c, other) < 3 then
					farEnough = false
					break
				end
			end
			if farEnough then
				local sides = {}
				for _, d in DIRS do
					if Maze.getEdge(layout, c.x, c.z, d) == "wall" then
						table.insert(sides, d)
					end
				end
				if #sides > 0 then
					local side = sides[rng(1, #sides)]
					used[k] = true
					table.insert(mazeLockers, c)
					table.insert(layout.lockers, { x = c.x, z = c.z, side = side, house = false })
					lockerSides[k .. side] = true
				end
			end
		end
	end

	-- Ceiling lamps in the maze: sparse, never two in neighbouring cells.
	local lampOrder = table.clone(mazeCells)
	shuffle(lampOrder, rng)
	for _, c in lampOrder do
		local spaced = true
		for _, other in layout.lights do
			if manhattan(c, other) < 3 then
				spaced = false
				break
			end
		end
		if spaced and rng() < 0.6 then
			table.insert(layout.lights, c)
		end
	end

	-- Scrawled writing on maze walls.
	local texts = table.clone(WRITINGS)
	shuffle(texts, rng)
	local wallOrder = table.clone(mazeCells)
	shuffle(wallOrder, rng)
	for _, c in wallOrder do
		if #layout.writings >= math.min(cfg.WritingCount, #texts) then
			break
		end
		local sides = {}
		for _, d in DIRS do
			if Maze.getEdge(layout, c.x, c.z, d) == "wall" and not lockerSides[Maze.key(c.x, c.z) .. d] then
				table.insert(sides, d)
			end
		end
		if #sides > 0 then
			table.insert(layout.writings, {
				x = c.x,
				z = c.z,
				side = sides[rng(1, #sides)],
				text = texts[#layout.writings + 1],
			})
		end
	end

	-- The monster starts as far from the house as possible.
	local farthest = layout.entrance
	local farDist = -1
	for _, c in mazeCells do
		local d = dist[Maze.key(c.x, c.z)] or -1
		if d > farDist then
			farthest, farDist = c, d
		end
	end
	layout.monsterSpawn = farthest

	-- The exit code (never all the same digit).
	repeat
		local digits = {}
		for i = 1, cfg.KeyCount do
			digits[i] = tostring(rng(0, 9))
		end
		layout.code = table.concat(digits)
	until not string.match(layout.code, "^(%d)%1+$")

	return layout
end

return Maze
