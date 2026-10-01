-- Unit tests for the maze generator. Run with Lune:  lune run tests/maze.spec.luau
local Maze = require("../src/ReplicatedStorage/Shared/Maze")

local cfg = {
	CellSize = 12,
	Width = 13,
	Depth = 13,
	HouseWidth = 5,
	HouseDepth = 3,
	DeadEndBraid = 0.35,
	ExtraOpenings = 6,
	KeyCount = 4,
	BatteryCount = 5,
	MazeLockerCount = 9,
	WritingCount = 12,
}

local failures = 0
local function check(cond: boolean, msg: string)
	if not cond then
		failures += 1
		print("FAIL: " .. msg)
	end
end

local function key(c)
	return Maze.key(c.x, c.z)
end

local SEEDS = 300
local stats = { keys = 0, lockers = 0, lights = 0, deadEnds = 0, writings = 0 }

for seed = 1, SEEDS do
	local layout = Maze.generate(seed * 7919, cfg)
	local tag = " (seed " .. seed * 7919 .. ")"

	-- determinism
	local again = Maze.generate(seed * 7919, cfg)
	check(again.code == layout.code and key(again.monsterSpawn) == key(layout.monsterSpawn), "deterministic" .. tag)

	-- every cell (house + maze) reachable from the bedroom spawn
	local spawn = { x = layout.house.x0, z = layout.house.z0 + 2 }
	local dist = Maze.distances(layout, spawn)
	local reachable = 0
	for _ in dist do
		reachable += 1
	end
	check(reachable == layout.width * layout.depth, "all cells reachable, got " .. reachable .. tag)

	-- keys
	check(#layout.keys == cfg.KeyCount, "key count" .. tag)
	local seen = {}
	for _, k in layout.keys do
		check(not Maze.isHouse(layout, k.x, k.z), "key outside house" .. tag)
		check(not seen[key(k)], "keys in distinct cells" .. tag)
		seen[key(k)] = true
		check(Maze.findPath(layout, k, layout.exitCell) ~= nil, "path from key to exit" .. tag)
	end

	-- the exit edge exists and is not passable for the monster
	check(Maze.getEdge(layout, layout.exitCell.x, layout.exitCell.z, "S") == "exit", "exit edge" .. tag)

	-- code
	check(#layout.code == cfg.KeyCount and string.match(layout.code, "^%d+$") ~= nil, "code digits" .. tag)

	-- lockers sit against real walls
	for _, l in layout.lockers do
		check(Maze.getEdge(layout, l.x, l.z, l.side) == "wall", "locker against a wall" .. tag)
	end

	-- writings sit on real walls
	for _, w in layout.writings do
		check(Maze.getEdge(layout, w.x, w.z, w.side) == "wall", "writing on a wall" .. tag)
	end

	-- paths are contiguous and only cross passable edges
	local path = Maze.findPath(layout, layout.monsterSpawn, spawn)
	check(path ~= nil, "monster can reach the bedroom" .. tag)
	if path then
		for i = 2, #path do
			local a, b = path[i - 1], path[i]
			check(math.abs(a.x - b.x) + math.abs(a.z - b.z) == 1, "path steps are adjacent" .. tag)
		end
		check(#path - 1 == dist[key(layout.monsterSpawn)], "BFS path is shortest" .. tag)
	end

	-- straight runs never pass through walls
	for _, d in Maze.DIRS do
		local run = Maze.straightRun(layout, layout.entrance, d, 8)
		local prev = layout.entrance
		for _, c in run do
			check(Maze.isPassable(Maze.getEdge(layout, prev.x, prev.z, d)), "straight run passable" .. tag)
			prev = c
		end
	end

	-- edge key round trip
	local x, z, dir = Maze.parseEdgeKey(Maze.edgeKey(3, 4, "W"))
	check(x == 2 and z == 4 and dir == "E", "edge key round trip")

	stats.keys += #layout.keys
	stats.lockers += #layout.lockers
	stats.lights += #layout.lights
	stats.deadEnds += #layout.deadEnds
	stats.writings += #layout.writings
end

print(string.format(
	"avg per maze: lockers %.1f, lamps %.1f, dead ends %.1f, writings %.1f",
	stats.lockers / SEEDS,
	stats.lights / SEEDS,
	stats.deadEnds / SEEDS,
	stats.writings / SEEDS
))

-- Print one maze so a human can eyeball it.
local layout = Maze.generate(12345, cfg)
local rows = {}
for z = layout.depth - 1, 0, -1 do
	local top, mid = "", ""
	for x = 0, layout.width - 1 do
		local n = Maze.getEdge(layout, x, z, "N")
		local w = Maze.getEdge(layout, x, z, "W")
		top ..= "+" .. (n == "wall" and "---" or (n == "open" and "   " or " " .. string.sub(n, 1, 1) .. " "))
		local ch = " "
		if Maze.isHouse(layout, x, z) then
			ch = "."
		end
		for i, k in layout.keys do
			if k.x == x and k.z == z then
				ch = tostring(i)
			end
		end
		if layout.monsterSpawn.x == x and layout.monsterSpawn.z == z then
			ch = "M"
		end
		mid ..= (w == "wall" and "|" or (w == "open" and " " or string.sub(w, 1, 1))) .. " " .. ch .. " "
	end
	table.insert(rows, top .. "+")
	table.insert(rows, mid .. "|")
end
local bottom = ""
for x = 0, layout.width - 1 do
	local s = Maze.getEdge(layout, x, 0, "S")
	bottom ..= "+" .. (s == "wall" and "---" or " " .. string.sub(s, 1, 1) .. " ")
end
table.insert(rows, bottom .. "+")
print(table.concat(rows, "\n"))
print("code: " .. layout.code)

if failures > 0 then
	error(failures .. " check(s) failed")
end
print("maze tests passed (" .. SEEDS .. " seeds)")
