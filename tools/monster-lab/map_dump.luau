-- Builds a night's map with the real server code (inside the mocked engine from
-- tests/mock) and writes every part, light and sign to JSON for map_render.
--   lune run tools/monster-lab/map_dump.luau <night 1-5> <seed> <out.json> [monster cell x,z]
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Engine = require("../../tests/mock/engine")

local CFrame = Engine.CFrame
local Vector3 = roblox.Vector3

local REMOTES = { "Ready", "Notify", "Jumpscare", "OpenKeypad", "SubmitCode", "LeaveHiding", "Flashlight", "Battery", "RoundResult", "Apparition", "Escaped", "Look", "Throw", "Phone", "Event" }

local nightIndex = tonumber(process.args[1]) or 1
local seed = tonumber(process.args[2]) or 1234
local outPath = process.args[3] or "map.json"

local shared = Engine.folderFromDir("Shared", "src/ReplicatedStorage/Shared")
local server = Engine.folderFromDir("Server", "src/ServerScriptService/Server")
local game, workspace = Engine.makeGame(server, shared, nil, REMOTES)
local require_ = Engine.makeLoader({
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
	os = { clock = function()
		return Engine.time
	end, time = os.time, date = os.date },
	typeof = Engine.typeof,
	warn = function() end,
})
local rs = game:GetService("ReplicatedStorage")
local sss = game:GetService("ServerScriptService")
local Maze = require_(rs.Shared.Maze)
local Nights = require_(rs.Shared.Nights)
local WorldBuilder = require_(sss.Server.WorldBuilder)
local Interactables = require_(sss.Server.Interactables)
local Exit = require_(sss.Server.Exit)
local MonsterAI = require_(sss.Server.MonsterAI)
local Objectives = require_(sss.Server.Objectives)
local Monsters = require_(rs.Shared.Monsters)
Engine.Maze = Maze

local night = Nights.get(nightIndex)
local layout = Maze.generate(seed, night.maze)
Engine.layout = layout
local world = WorldBuilder.build(layout, night)
local exit = Exit.new(world)
local monster
local interactables = Interactables.new(layout, world, {
	isAlive = function()
		return false
	end,
	onHide = function() end,
	onNoise = function() end,
})
local params = Nights.monsterParams(night)
if night.monsterKind == "Statue" then
	params.Variant = Monsters.STATUE_VARIANTS[(seed % 2) + 1]
end
monster = MonsterAI.new(layout, world, interactables, params, night.monsterKind, {
	getPlayers = function()
		return {}
	end,
	onCaught = function() end,
	onAwake = function() end,
	getLook = function()
		return nil
	end,
	setBlink = function() end,
})
Objectives.start({
	night = night,
	layout = layout,
	world = world,
	interactables = interactables,
	monster = monster,
	exit = exit,
	isAlive = function()
		return false
	end,
	notifyAll = function() end,
	notify = function() end,
	setProgress = function() end,
	winAll = function() end,
})

-- optionally stand the monster in a cell (for "it's in the corridor" shots)
local mx, mz = string.match(process.args[4] or "", "^(%-?%d+),(%-?%d+)$")
if mx then
	local cx, cz = Maze.cellCenter(layout, { x = tonumber(mx) :: number, z = tonumber(mz) :: number })
	local face = Vector3.new(layout.entrance.x, 0, layout.entrance.z) - Vector3.new(tonumber(mx) :: number, 0, tonumber(mz) :: number)
	local pos = Vector3.new(cx, monster.rig.rootHeight, cz)
	monster.rig.model:PivotTo(if face.Magnitude > 0.1 then CFrame.lookAt(pos, pos + face) else CFrame.new(pos))
	monster.rig.model:SetAttribute("Shown", true)
end

local function r(x: number): number
	return math.floor(x * 1000 + 0.5) / 1000
end
local function color(c): { number }
	return { r(c.R), r(c.G), r(c.B) }
end

local parts, lights, texts = {}, {}, {}
for _, d in workspace:GetDescendants() do
	if d:IsA("BasePart") then
		local cf = d.CFrame
		if cf.Position.Y < -100 or d.Name == "HumanoidRootPart" or d.Name == "EscapeZone" then
			continue
		end
		local tr = d.Transparency or 0
		local mesh = d:FindFirstChildWhichIsA("SpecialMesh")
		local shape = if d.Shape then d.Shape.Name else "Block"
		if mesh then
			shape = "Mesh" .. mesh.MeshType.Name
		end
		if tr < 1 then
			local c = { cf:GetComponents() }
			for k, v in c do
				c[k] = r(v)
			end
			table.insert(parts, {
				name = d.Name,
				size = { r(d.Size.X), r(d.Size.Y), r(d.Size.Z) },
				cf = c,
				color = color(d.Color),
				material = if d.Material then d.Material.Name else "Plastic",
				shape = shape,
				transparency = tr,
				reflectance = d.Reflectance or 0,
				shadow = d.CastShadow ~= false,
			})
		end
		for _, child in d:GetChildren() do
			if child:IsA("Light") then
				local p = cf.Position
				local face = if child.Face then child.Face.Name else "Front"
				local dirs = { Front = Vector3.new(0, 0, -1), Back = Vector3.new(0, 0, 1), Top = Vector3.new(0, 1, 0), Bottom = Vector3.new(0, -1, 0), Right = Vector3.new(1, 0, 0), Left = Vector3.new(-1, 0, 0) }
				local dir = cf:VectorToWorldSpace(dirs[face] or Vector3.new(0, 0, -1))
				table.insert(lights, {
					kind = child.ClassName,
					pos = { r(p.X), r(p.Y), r(p.Z) },
					dir = { r(dir.X), r(dir.Y), r(dir.Z) },
					color = color(child.Color or roblox.Color3.new(1, 1, 1)),
					range = child.Range,
					brightness = child.Brightness,
					angle = child.Angle or 90,
					enabled = child.Enabled ~= false,
					shadows = child.Shadows == true,
				})
			elseif child:IsA("SurfaceGui") then
				local label = child:FindFirstChildWhichIsA("TextLabel")
				if label and label.Text and label.Text ~= "" then
					local c = { cf:GetComponents() }
					for k, v in c do
						c[k] = r(v)
					end
					table.insert(texts, {
						text = label.Text,
						cf = c,
						size = { r(d.Size.X), r(d.Size.Y) },
						color = color(label.TextColor3 or roblox.Color3.new(1, 1, 1)),
						glow = child.LightInfluence == 0,
						rotation = label.Rotation or 0,
					})
				end
			end
		end
	end
end

local l = night.lighting
local spawns = {}
for _, s in world.spawnPoints do
	local p, look = s.Position, s.LookVector
	table.insert(spawns, { pos = { r(p.X), r(p.Y), r(p.Z) }, look = { r(look.X), r(look.Y), r(look.Z) } })
end
local edges = {}
for k, v in layout.edges do
	edges[k] = v
end
fs.writeFile(outPath, serde.encode("json", {
	night = night.index,
	id = night.id,
	theme = night.theme,
	cellSize = layout.cellSize,
	width = layout.width,
	depth = layout.depth,
	ceiling = night.maze.CeilingHeight,
	wallHeight = night.maze.WallHeight,
	hub = layout.hub,
	entrance = layout.entrance,
	edges = edges,
	rooms = layout.roomBlocks,
	lights = lights,
	parts = parts,
	texts = texts,
	spawns = spawns,
	lighting = {
		ambient = color(l.Ambient),
		fog = color(l.FogColor),
		fogStart = l.FogStart,
		fogEnd = l.FogEnd,
		saturation = l.Saturation,
		contrast = l.Contrast,
		brightness = l.Brightness,
		tint = color(l.Tint),
		bloom = l.Bloom,
		exposure = l.Exposure,
	},
}))
print(string.format("night %d seed %d: %d parts, %d lights, %d texts", nightIndex, seed, #parts, #lights, #texts))
