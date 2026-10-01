--!strict
-- Turns a Maze layout into a themed map: floors, walls, doorways, pillars/columns,
-- lamps, props, writing, the hub, and the exit tunnel. Interactive things (doors,
-- lockers, batteries, notes, the exit, objective items) are added afterwards.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Maze = require(ReplicatedStorage.Shared.Maze)
local Nights = require(ReplicatedStorage.Shared.Nights)
local Build = require(script.Parent.Build)
local Themes = require(script.Parent.Themes)

type Layout = Maze.Layout
type Style = Build.Style

export type World = {
	model: Model,
	ctx: Build.Ctx,
	theme: Themes.Theme,
	night: Nights.Night,
	spawnPoints: { CFrame },
	escapeZone: BasePart,
	exitLight: PointLight,
	exitFrame: CFrame, -- the exit edge; its Back face looks into the hub
	hiddenSpot: CFrame,
	notes: { Build.Note },
	lamps: { Build.Lamp },
	random: Random,
}

local WorldBuilder = {}

WorldBuilder.setupCollisionGroups = Build.setupCollisionGroups

local function buildEdges(ctx: Build.Ctx, theme: Themes.Theme)
	local layout = ctx.layout
	local W, D = layout.width, layout.depth
	local function styleOf(x: number, z: number): Style
		if Maze.inBounds(layout, x, z) and Maze.isHub(layout, x, z) then
			return theme.hubWall
		end
		return theme.wall
	end
	for z = -1, D - 1 do
		for x = -1, W - 1 do
			for _, dir in { "N", "E" } do
				local valid = if dir == "N" then (x >= 0 and x < W) else (z >= 0 and z < D)
				if valid then
					local kind = Maze.getEdge(layout, x, z, dir)
					local front = styleOf(x, z)
					local back = styleOf(x + Maze.DX[dir], z + Maze.DZ[dir])
					local frame = ctx.edgeFrame(x, z, dir)
					if kind == "wall" then
						Build.wallBox(ctx, ctx.structure, frame, ctx.C - ctx.T, ctx.H, 0, 0, front, back)
					elseif kind == "door" or kind == "doorway" then
						Build.wallWithOpening(ctx, ctx.structure, frame, ctx.doorWidth, ctx.doorHeight, front, back)
						Build.doorTrim(ctx, ctx.structure, frame, ctx.doorWidth, ctx.doorHeight, theme.trim)
					elseif kind == "exit" then
						Build.wallWithOpening(ctx, ctx.structure, frame, ctx.exitWidth, ctx.exitHeight, front, back)
						Build.doorTrim(ctx, ctx.structure, frame, ctx.exitWidth, ctx.exitHeight, theme.trim)
					elseif kind == "hole" then
						Build.brokenWall(ctx, ctx.structure, frame, front, back)
					end
				end
			end
		end
	end
end

local function buildPillars(ctx: Build.Ctx, theme: Themes.Theme)
	local layout = ctx.layout
	local W, D = layout.width, layout.depth
	local C, H, T = ctx.C, ctx.H, ctx.T
	for j = 0, D do
		for i = 0, W do
			if theme.columns then
				-- a colonnade: a column at every grid point, up to the far-away ceiling
				local top = ctx.ceiling
				ctx.part(ctx.structure, "Column", Vector3.new(top, 3.4, 3.4), CFrame.new(i * C, top / 2, j * C) * CFrame.Angles(0, 0, math.rad(90)), theme.trim.material, ctx.vary(theme.trim.color, 0.03), Enum.PartType.Cylinder)
				ctx.part(ctx.structure, "ColumnBase", Vector3.new(4.6, 1.4, 4.6), CFrame.new(i * C, 0.7, j * C), theme.wall.material, theme.wall.color, nil)
				ctx.part(ctx.structure, "ColumnCap", Vector3.new(4.6, 1.2, 4.6), CFrame.new(i * C, top - 0.6, j * C), theme.wall.material, theme.wall.color, nil)
			else
				local needed = false
				for _, ex in { i - 1, i } do
					if ex >= 0 and ex < W and Maze.getEdge(layout, ex, j - 1, "N") ~= "open" then
						needed = true
					end
				end
				for _, ez in { j - 1, j } do
					if ez >= 0 and ez < D and Maze.getEdge(layout, i - 1, ez, "E") ~= "open" then
						needed = true
					end
				end
				if needed then
					local hubCount = 0
					for _, c in { { i - 1, j - 1 }, { i, j - 1 }, { i - 1, j }, { i, j } } do
						if Maze.inBounds(layout, c[1], c[2]) and Maze.isHub(layout, c[1], c[2]) then
							hubCount += 1
						end
					end
					local style = if hubCount >= 2 then theme.hubWall else theme.wall
					ctx.part(ctx.structure, "Pillar", Vector3.new(T + 0.5, H, T + 0.5), CFrame.new(i * C, H / 2, j * C), style.material, ctx.vary(style.color, 0.1), nil)
				end
			end
		end
	end
end

local function buildExitTunnel(ctx: Build.Ctx, theme: Themes.Theme): (BasePart, PointLight)
	local layout = ctx.layout
	local x = (layout.exitCell.x + 0.5) * ctx.C
	local width = ctx.exitWidth + 2
	local height = math.min(ctx.H, ctx.exitHeight + 3)
	local length = 28
	local zMid = -length / 2
	ctx.styled(ctx.structure, "TunnelFloor", Vector3.new(width + 2, 1, length), CFrame.new(x, -0.5, zMid), theme.floor)
	ctx.styled(ctx.structure, "TunnelCeiling", Vector3.new(width + 2, 1, length), CFrame.new(x, height + 0.5, zMid), theme.ceiling)
	for _, sx in { -1, 1 } do
		ctx.styled(ctx.structure, "TunnelWall", Vector3.new(1, height, length), CFrame.new(x + sx * (width / 2 + 0.5), height / 2, zMid), theme.tunnel)
	end
	local glow = ctx.part(ctx.structure, "TheOutside", Vector3.new(width + 2, height, 0.5), CFrame.new(x, height / 2, -length), Enum.Material.Neon, Color3.new(1, 1, 1), nil)
	glow.CastShadow = false
	local light = Instance.new("PointLight")
	light.Range = 45
	light.Brightness = 4
	light.Shadows = true
	light.Enabled = false -- switched on when the exit opens
	light.Parent = glow
	local zone = ctx.decor(ctx.part(ctx.structure, "EscapeZone", Vector3.new(width, 12, 2), CFrame.new(x, 6, -12), Enum.Material.SmoothPlastic, Color3.new(1, 1, 1), nil))
	zone.CanTouch = true
	zone.Transparency = 1
	return zone, light
end

function WorldBuilder.build(layout: Layout, night: Nights.Night): World
	Build.setupCollisionGroups()
	local model = Instance.new("Model")
	model.Name = "World"
	local ctx = Build.new(layout, night, model)
	local theme = Themes[night.theme] or Themes.house
	local C = ctx.C
	local W, D = layout.width, layout.depth

	ctx.styled(ctx.structure, "Floor", Vector3.new(W * C + 2, 1, D * C + 2), CFrame.new(W * C / 2, -0.5, D * C / 2), theme.floor)
	ctx.styled(ctx.structure, "Ceiling", Vector3.new(W * C + 2, 1, D * C + 2), CFrame.new(W * C / 2, ctx.ceiling + 0.5, D * C / 2), theme.ceiling)
	for key, room in layout.rooms do
		local xs, zs = string.match(key, "^(%-?%d+),(%-?%d+)$")
		local cx, cz = tonumber(xs) :: number, tonumber(zs) :: number
		ctx.styled(ctx.structure, "HubFloor", Vector3.new(C, 1, C), CFrame.new((cx + 0.5) * C, -0.45, (cz + 0.5) * C), theme.hubFloor(room))
		ctx.styled(ctx.structure, "HubCeiling", Vector3.new(C, 1, C), CFrame.new((cx + 0.5) * C, ctx.ceiling + 0.45, (cz + 0.5) * C), theme.hubCeiling)
	end

	buildEdges(ctx, theme)
	buildPillars(ctx, theme)

	for _, c in layout.lights do
		theme.lamp(ctx, c, ctx.cellCenter(c.x, c.z))
	end
	theme.hubLamps(ctx)

	local texts = table.clone(theme.writings)
	for i = #texts, 2, -1 do
		local j = ctx.random:NextInteger(1, i)
		texts[i], texts[j] = texts[j], texts[i]
	end
	for i, w in layout.writings do
		local frame = ctx.sideFrame(w.x, w.z, w.side) * CFrame.new(ctx.random:NextNumber(-1.2, 1.2), ctx.random:NextNumber(5, math.min(7, ctx.H - 3)), -0.1)
		ctx.writing(frame, texts[(i - 1) % #texts + 1], theme.writingColor, theme.writingFont, theme.writingGlow)
	end

	local spotCells: { [string]: boolean } = {}
	for _, s in layout.spots do
		spotCells[Maze.key(s.x, s.z)] = true
	end
	for _, l in layout.lockers do
		spotCells[Maze.key(l.x, l.z)] = true -- keep clutter out of locker cells too
	end
	local roomCells: { [string]: boolean } = {}
	for _, block in layout.roomBlocks do
		for _, c in block do
			roomCells[Maze.key(c.x, c.z)] = true
		end
	end
	for z = 0, D - 1 do
		for x = 0, W - 1 do
			if not Maze.isHub(layout, x, z) then
				local k = Maze.key(x, z)
				theme.cell(ctx, x, z, { spot = spotCells[k] == true, room = roomCells[k] == true })
			end
		end
	end
	for _, block in layout.roomBlocks do
		theme.room(ctx, block)
	end
	theme.hub(ctx)
	theme.extra(ctx)

	Build.markFurniture(ctx.props)
	Build.markFurniture(ctx.lights)
	local escapeZone, exitLight = buildExitTunnel(ctx, theme)
	local spawnPoints = theme.spawns(ctx)

	model.Parent = workspace

	return {
		model = model,
		ctx = ctx,
		theme = theme,
		night = night,
		spawnPoints = spawnPoints,
		escapeZone = escapeZone,
		exitLight = exitLight,
		exitFrame = ctx.edgeFrame(layout.exitCell.x, layout.exitCell.z - 1, "N"),
		hiddenSpot = CFrame.new(W * C / 2, -300, D * C / 2),
		notes = ctx.notes,
		lamps = ctx.lamps,
		random = ctx.random,
	}
end

return WorldBuilder
