-- Unit tests for the maze generator, for every night's settings.
-- Run with Lune:  lune run tests/maze.spec.luau
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Engine = require("./mock/engine")

local shared = Engine.folderFromDir("Shared", "src/ReplicatedStorage/Shared")
local require = Engine.makeLoader({
	Color3 = roblox.Color3,
	Vector3 = roblox.Vector3,
	typeof = Engine.typeof,
})
local Maze = require(shared.Maze)
local Nights = require(shared.Nights)

local failures = 0
local function check(cond: boolean, msg: string)
	if not cond then
		failures += 1
		if failures < 30 then
			print("FAIL: " .. msg)
		end
	end
end

local function key(c)
	return Maze.key(c.x, c.z)
end

local function draw(layout)
	local rows = {}
	local spotAt = {}
	for i, k in layout.spots do
		spotAt[key(k)] = tostring(i)
	end
	for z = layout.depth - 1, 0, -1 do
		local top, mid = "", ""
		for x = 0, layout.width - 1 do
			local n = Maze.getEdge(layout, x, z, "N")
			local w = Maze.getEdge(layout, x, z, "W")
			top ..= "+" .. (if n == "wall" then "---" elseif n == "open" then "   " else " " .. string.sub(n, 1, 1) .. " ")
			local ch = if Maze.isHub(layout, x, z) then "." else " "
			ch = spotAt[Maze.key(x, z)] or ch
			if layout.monsterSpawn.x == x and layout.monsterSpawn.z == z then
				ch = "M"
			end
			mid ..= (if w == "wall" then "|" elseif w == "open" then " " else string.sub(w, 1, 1)) .. " " .. ch .. " "
		end
		table.insert(rows, top .. "+")
		table.insert(rows, mid .. "|")
	end
	local bottom = ""
	for x = 0, layout.width - 1 do
		local s = Maze.getEdge(layout, x, 0, "S")
		bottom ..= "+" .. (if s == "wall" then "---" else " " .. string.sub(s, 1, 1) .. " ")
	end
	table.insert(rows, bottom .. "+")
	return table.concat(rows, "\n")
end

local SEEDS = 120

for _, night in Nights.list do
	local cfg = night.maze
	local stats = { lockers = 0, lights = 0, deadEnds = 0, writings = 0, rooms = 0, spots = 0 }
	for seed = 1, SEEDS do
		local s = seed * 7919 + night.index
		local layout = Maze.generate(s, cfg)
		local tag = " (" .. night.id .. " seed " .. s .. ")"

		local again = Maze.generate(s, cfg)
		check(again.code == layout.code and key(again.monsterSpawn) == key(layout.monsterSpawn), "deterministic" .. tag)

		-- every cell reachable from where you wake up
		local start = { x = layout.hub.x0, z = layout.hub.z0 + layout.hub.d - 1 }
		local dist = Maze.distances(layout, start)
		local reachable = 0
		for _ in dist do
			reachable += 1
		end
		check(reachable == layout.width * layout.depth, "all cells reachable, got " .. reachable .. tag)

		check(#layout.spots == cfg.SpotCount, "objective spot count " .. #layout.spots .. tag)
		local seen = {}
		for _, k in layout.spots do
			check(not Maze.isHub(layout, k.x, k.z), "spot outside the hub" .. tag)
			check(not seen[key(k)], "spots in distinct cells" .. tag)
			seen[key(k)] = true
			check(Maze.findPath(layout, k, layout.exitCell) ~= nil, "path from spot to exit" .. tag)
		end
		for i = 1, #layout.spots do
			for j = i + 1, #layout.spots do
				local a, b = layout.spots[i], layout.spots[j]
				check(math.abs(a.x - b.x) + math.abs(a.z - b.z) >= 2, "spots are spread out" .. tag)
			end
		end

		check(Maze.getEdge(layout, layout.exitCell.x, layout.exitCell.z, "S") == "exit", "exit edge" .. tag)
		check(#layout.code == math.max(cfg.SpotCount, 1) and string.match(layout.code, "^%d+$") ~= nil, "code digits" .. tag)

		local lockerCount = 0
		for _, l in layout.lockers do
			check(Maze.getEdge(layout, l.x, l.z, l.side) == "wall", "locker against a wall" .. tag)
			if not l.house then
				lockerCount += 1
			end
		end
		check(lockerCount <= cfg.LockerCount, "locker count" .. tag)
		for _, w in layout.writings do
			check(Maze.getEdge(layout, w.x, w.z, w.side) == "wall", "writing on a wall" .. tag)
		end

		for _, block in layout.roomBlocks do
			check(#block == 4, "rooms are 2x2" .. tag)
			local a = block[1]
			check(Maze.getEdge(layout, a.x, a.z, "E") == "open" and Maze.getEdge(layout, a.x, a.z, "N") == "open", "room interior is open" .. tag)
		end

		local path = Maze.findPath(layout, layout.monsterSpawn, start)
		check(path ~= nil, "monster can reach the hub" .. tag)
		if path then
			for i = 2, #path do
				local a, b = path[i - 1], path[i]
				check(math.abs(a.x - b.x) + math.abs(a.z - b.z) == 1, "path steps are adjacent" .. tag)
			end
			check(#path - 1 == dist[key(layout.monsterSpawn)], "BFS path is shortest" .. tag)
		end

		stats.lockers += #layout.lockers
		stats.lights += #layout.lights
		stats.deadEnds += #layout.deadEnds
		stats.writings += #layout.writings
		stats.rooms += #layout.roomBlocks
		stats.spots += #layout.spots
	end
	print(string.format(
		"%-8s lockers %4.1f  lamps %4.1f  dead ends %4.1f  writings %4.1f  rooms %3.1f",
		night.id,
		stats.lockers / SEEDS,
		stats.lights / SEEDS,
		stats.deadEnds / SEEDS,
		stats.writings / SEEDS,
		stats.rooms / SEEDS
	))
end

local x, z, dir = Maze.parseEdgeKey(Maze.edgeKey(3, 4, "W"))
check(x == 2 and z == 4 and dir == "E", "edge key round trip")

if process.args[1] == "draw" then
	for _, night in Nights.list do
		print(night.name)
		print(draw(Maze.generate(12345, night.maze)))
	end
end

if failures > 0 then
	error(failures .. " check(s) failed")
end
print("maze tests passed (" .. SEEDS .. " seeds x " .. Nights.count .. " nights)")
