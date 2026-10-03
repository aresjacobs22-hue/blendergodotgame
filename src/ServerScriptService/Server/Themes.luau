--!strict
-- The look of each night's map: materials, lamps, props, hub decor, wall writing.
--   house       grey concrete maze around a house                        (night 1)
--   sanatorium  a 1950s isolation wing: white tile, a checkered floor    (night 2)
--   drain       vaulted Victorian storm drains, the moon through grates  (night 3)
--   gallery     a museum after dark: skylights, paintings, dust sheets   (night 4)
--   unmade      the house from night 1, coming apart in the dark         (night 5)
-- Each one is a single believable place, in black and white, with a few deliberate
-- things in it instead of clutter.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Maze = require(ReplicatedStorage.Shared.Maze)
local Monsters = require(ReplicatedStorage.Shared.Monsters)
local Build = require(script.Parent.Build)
local Dressing = require(script.Parent.Dressing)

type Ctx = Build.Ctx
type Style = Build.Style
type Cell = Maze.Cell

export type CellInfo = { spot: boolean, room: boolean }

export type Theme = {
	wall: Style,
	hubWall: Style,
	floor: Style,
	hubFloor: (room: string) -> Style,
	ceiling: Style,
	hubCeiling: Style,
	trim: Style,
	tunnel: Style,
	locker: Style,
	columns: boolean,
	portholes: boolean?, -- round windows in the exit doors
	-- how tall the wall on an edge is (default: full height); walls that stop short get a broken top
	edgeHeight: ((ctx: Ctx, x: number, z: number, dir: string) -> number)?,
	writings: { string },
	writingColor: Color3,
	writingFont: Enum.Font,
	writingGlow: boolean,
	exitStyle: string,
	lamp: (ctx: Ctx, cell: Cell?, position: Vector3) -> (),
	hubLamps: (ctx: Ctx) -> (),
	cell: (ctx: Ctx, x: number, z: number, info: CellInfo) -> (),
	room: (ctx: Ctx, block: { Cell }) -> (),
	hub: (ctx: Ctx) -> (),
	extra: (ctx: Ctx) -> (),
	spawns: (ctx: Ctx) -> { CFrame },
}

local Themes: { [string]: Theme } = {}

local UP = CFrame.Angles(0, 0, math.rad(90)) -- turns a Cylinder (X axis) upright

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function solid(ctx: Ctx, name: string, size: Vector3, cf: CFrame, material: Enum.Material, color: Color3, shape: Enum.PartType?): Part
	return ctx.part(ctx.props, name, size, cf, material, color, shape)
end

local function deco(ctx: Ctx, name: string, size: Vector3, cf: CFrame, material: Enum.Material, color: Color3, shape: Enum.PartType?): Part
	return ctx.decor(ctx.part(ctx.props, name, size, cf, material, color, shape)) :: Part
end

-- Wall faces of hub cells (except the exit), for hanging hub decor.
local function hubWalls(ctx: Ctx): { { cell: Cell, side: string } }
	local out = {}
	local hub = ctx.layout.hub
	for rz = 0, hub.d - 1 do
		for rx = 0, hub.w - 1 do
			local x, z = hub.x0 + rx, hub.z0 + rz
			for _, side in Maze.DIRS do
				local kind = Maze.getEdge(ctx.layout, x, z, side)
				local nx, nz = x + Maze.DX[side], z + Maze.DZ[side]
				if kind == "wall" and not (Maze.inBounds(ctx.layout, nx, nz) and Maze.isHub(ctx.layout, nx, nz)) then
					table.insert(out, { cell = { x = x, z = z }, side = side })
				end
			end
		end
	end
	return out
end

local function hallSpawns(ctx: Ctx): { CFrame }
	local hub = ctx.layout.hub
	local cx = ctx.hubOrigin.X + hub.w * ctx.C / 2
	local z0 = ctx.hubOrigin.Z + ctx.C * 0.6
	local points = {}
	for i = 0, 5 do
		local pos = Vector3.new(cx + (i % 3 - 1) * 4, 3.5, z0 + math.floor(i / 3) * 4)
		table.insert(points, CFrame.lookAt(pos, pos + Vector3.new(0, 0, 1)))
	end
	return points
end

local function hubCellLamps(ctx: Ctx, theme: Theme)
	local hub = ctx.layout.hub
	for rz = 0, hub.d - 1 do
		for rx = 0, hub.w - 1 do
			theme.lamp(ctx, nil, ctx.cellCenter(hub.x0 + rx, hub.z0 + rz))
		end
	end
end

local function noop() end

-- Which of the map's 2x2 rooms this is (1 = first).
local function roomIndex(ctx: Ctx, block: { Cell }): number
	return table.find(ctx.layout.roomBlocks, block) or 1
end

local function randomSide(ctx: Ctx, sides: { string }): string
	return sides[ctx.random:NextInteger(1, #sides)]
end

---------------------------------------------------------------------------
-- NIGHT 1: THE HOUSE

local HOUSE_FLOORS: { [string]: Style } = {
	hall = { material = Enum.Material.WoodPlanks, color = rgb(88, 74, 62) },
	living = { material = Enum.Material.WoodPlanks, color = rgb(98, 82, 68) },
	bedroom = { material = Enum.Material.Carpet, color = rgb(78, 76, 80) },
	kitchen = { material = Enum.Material.CeramicTiles, color = rgb(150, 150, 146) },
	study = { material = Enum.Material.WoodPlanks, color = rgb(80, 68, 58) },
}

local function portrait(ctx: Ctx, frame: CFrame)
	solid(ctx, "PortraitFrame", Vector3.new(3.6, 4.6, 0.3), frame * CFrame.new(0, 0, -0.15), Enum.Material.Wood, rgb(45, 36, 30))
	local canvas = deco(ctx, "Portrait", Vector3.new(3, 4, 0.05), frame * CFrame.new(0, 0, -0.33), Enum.Material.SmoothPlastic, rgb(38, 38, 38))
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 1
	gui.Parent = canvas
	local function blob(name: string, pos: UDim2, size: UDim2, color: Color3): Frame
		local f = Instance.new("Frame")
		f.Name = name
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = pos
		f.Size = size
		f.BackgroundColor3 = color
		f.BorderSizePixel = 0
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = f
		f.Parent = gui
		return f
	end
	blob("Body", UDim2.fromScale(0.5, 1.05), UDim2.fromScale(0.95, 0.5), rgb(20, 20, 20))
	local face = blob("Face", UDim2.fromScale(0.5, 0.42), UDim2.fromScale(0.5, 0.5), rgb(205, 200, 190))
	face.Rotation = ctx.random:NextNumber(-8, 8)
	blob("EyeL", UDim2.fromScale(0.41, 0.38), UDim2.fromScale(0.11, 0.09), Color3.new(0, 0, 0))
	blob("EyeR", UDim2.fromScale(0.59, 0.38), UDim2.fromScale(0.11, 0.09), Color3.new(0, 0, 0))
	blob("Mouth", UDim2.fromScale(0.5, 0.55), UDim2.fromScale(0.16, 0.12), Color3.new(0, 0, 0))
end

local function ceilingLamp(ctx: Ctx, cell: Cell?, position: Vector3, color: Color3, brightness: number, range: number)
	local H = ctx.ceiling
	ctx.decor(ctx.part(ctx.lights, "LampBase", Vector3.new(2.8, 0.3, 2.8), CFrame.new(position.X, H - 0.15, position.Z), Enum.Material.Metal, rgb(45, 45, 45), nil))
	local bulb = ctx.decor(ctx.part(ctx.lights, "Bulb", Vector3.new(1.5, 0.35, 1.5), CFrame.new(position.X, H - 0.45, position.Z), Enum.Material.Neon, rgb(215, 212, 200), nil))
	bulb.CastShadow = false
	local light = Instance.new("PointLight")
	light.Range = range
	light.Brightness = brightness
	light.Color = color
	light.Shadows = true
	light.Parent = bulb
	bulb:SetAttribute("Buzz", ctx.random:NextNumber() < 0.4)
	ctx.addLamp(bulb, light, cell)
end

local function hangingLamp(ctx: Ctx, position: Vector3, brightness: number, color: Color3)
	local H = ctx.ceiling
	local bulbY = H - 3.2
	ctx.decor(ctx.part(ctx.lights, "Cord", Vector3.new(0.12, H - bulbY, 0.12), CFrame.new(position.X, (H + bulbY) / 2, position.Z), Enum.Material.Plastic, rgb(20, 20, 20), nil))
	ctx.decor(ctx.part(ctx.lights, "Shade", Vector3.new(2.2, 0.9, 2.2), CFrame.new(position.X, bulbY + 0.55, position.Z), Enum.Material.Fabric, rgb(120, 116, 110), nil))
	local bulb = ctx.decor(ctx.part(ctx.lights, "Bulb", Vector3.new(0.9, 0.9, 0.9), CFrame.new(position.X, bulbY, position.Z), Enum.Material.Neon, rgb(215, 212, 200), Enum.PartType.Ball))
	bulb.CastShadow = false
	local light = Instance.new("PointLight")
	light.Range = 24
	light.Brightness = brightness
	light.Color = color
	light.Shadows = true
	light.Parent = bulb
	ctx.addLamp(bulb, light, nil)
end

local function houseProps(ctx: Ctx)
	local O = ctx.hubOrigin
	local random = ctx.random
	local function box(name: string, size: Vector3, x: number, yBottom: number, z: number, material: Enum.Material, color: Color3, rotY: number?): Part
		return solid(ctx, name, size, CFrame.new(O + Vector3.new(x, yBottom + size.Y / 2, z)) * CFrame.Angles(0, rotY or 0, 0), material, color)
	end
	local function wallFrame(x: number, y: number, z: number, facing: Vector3): CFrame
		local pos = O + Vector3.new(x, y, z)
		return CFrame.lookAt(pos, pos + facing)
	end
	local function note(x: number, y: number, z: number)
		ctx.note(CFrame.new(O + Vector3.new(x, y + 0.025, z)) * CFrame.Angles(0, random:NextNumber(-0.4, 0.4), 0))
	end
	local wood = Enum.Material.Wood
	local darkWood = rgb(62, 50, 42)
	local fabric = Enum.Material.Fabric

	-- bedroom: you wake up here
	box("BedFrame", Vector3.new(6, 1.6, 8), 3.6, 0, 29.1, wood, darkWood)
	box("Headboard", Vector3.new(6, 4.2, 0.5), 3.6, 0, 24.85, wood, darkWood)
	box("Mattress", Vector3.new(5.6, 0.9, 7.4), 3.6, 1.6, 29.3, fabric, rgb(196, 194, 188))
	box("Pillow", Vector3.new(3.6, 0.6, 1.5), 3.6, 2.5, 26.2, fabric, rgb(220, 218, 214))
	box("Blanket", Vector3.new(5.8, 0.3, 4.6), 3.7, 2.5, 31.0, fabric, rgb(70, 70, 78), 0.06)
	box("Nightstand", Vector3.new(2.2, 2.4, 2), 8, 0, 25.6, wood, darkWood)
	box("BrokenLamp", Vector3.new(0.6, 1.3, 0.6), 8.4, 2.4, 25.4, Enum.Material.Metal, rgb(80, 80, 80), 0.3)
	note(7.7, 2.4, 25.9)
	box("ChairSeat", Vector3.new(2.2, 0.35, 2.2), 21.4, 2.1, 33.6, wood, darkWood, math.rad(45))
	box("ChairBack", Vector3.new(2.2, 3.2, 0.3), 22.2, 2.45, 34.4, wood, darkWood, math.rad(45))
	for _, l in { { 20.7, 33.6 }, { 21.4, 32.9 }, { 22.1, 33.6 }, { 21.4, 34.3 } } do
		box("ChairLeg", Vector3.new(0.3, 2.1, 0.3), l[1], 0, l[2], wood, darkWood)
	end
	portrait(ctx, wallFrame(18, 6.2, 35.5, Vector3.new(0, 0, -1)))

	-- living room
	local couch = rgb(104, 100, 96)
	box("CouchBase", Vector3.new(3.6, 2, 9), 2.9, 0, 12, fabric, couch)
	box("CouchBack", Vector3.new(1.2, 4.2, 9), 1.1, 0, 12, fabric, couch)
	box("CouchArm", Vector3.new(3.6, 3, 1), 2.9, 0, 7, fabric, couch)
	box("CouchArm", Vector3.new(3.6, 3, 1), 2.9, 0, 17, fabric, couch)
	ctx.decor(box("Rug", Vector3.new(10, 0.1, 8), 8, 0.05, 12, fabric, rgb(56, 56, 60)))
	box("CoffeeTable", Vector3.new(3, 1.6, 5), 8.5, 0, 12, wood, darkWood)
	box("TVStand", Vector3.new(2.4, 2.4, 6.4), 22.2, 0, 6, wood, darkWood)
	box("TV", Vector3.new(1, 3.4, 5.4), 22.5, 2.4, 6, Enum.Material.SmoothPlastic, rgb(16, 16, 16))
	local screen = ctx.sign(wallFrame(21.95, 4.1, 6, Vector3.new(-1, 0, 0)), Vector2.new(4.8, 2.9), "NO SIGNAL\n\nSTAY ASLEEP", rgb(150, 150, 150), rgb(46, 46, 46), true, Enum.Font.SpecialElite)
	local tvLight = Instance.new("PointLight")
	tvLight.Range = 10
	tvLight.Brightness = 0.6
	tvLight.Shadows = true
	tvLight.Parent = screen
	ctx.addLamp(screen, tvLight, nil)
	box("Bookshelf", Vector3.new(8, 9, 2), 12, 0, 1.55, wood, darkWood)
	for shelf = 0, 2 do
		local x = 8.6
		while x < 15.2 do
			local w = random:NextNumber(0.35, 0.8)
			local h = random:NextNumber(1.4, 2.2)
			box("Book", Vector3.new(w, h, 1.4), x + w / 2, 1 + shelf * 2.8, 2.0, fabric, ctx.vary(rgb(110, 104, 98), 0.4))
			x += w + random:NextNumber(0.02, 0.4)
		end
	end
	portrait(ctx, wallFrame(0.5, 7, 12, Vector3.new(1, 0, 0)))

	-- hall: the grandfather clock is stuck at midnight
	box("ClockBody", Vector3.new(1.8, 8.6, 1.6), 25.4, 0, 8, wood, darkWood)
	ctx.sign(wallFrame(26.33, 6.8, 8, Vector3.new(1, 0, 0)), Vector2.new(1.3, 1.3), "XII", rgb(30, 30, 30), rgb(200, 196, 186), false, Enum.Font.Fondamento)
	box("CoatRack", Vector3.new(0.4, 7, 0.4), 25.6, 0, 2.2, wood, darkWood)
	ctx.decor(box("Runner", Vector3.new(4, 0.1, 30), 30, 0.05, 18, fabric, rgb(60, 58, 58)))
	portrait(ctx, wallFrame(24.5, 6.5, 24, Vector3.new(1, 0, 0)))
	portrait(ctx, wallFrame(35.5, 6.5, 6, Vector3.new(-1, 0, 0)))

	-- kitchen
	box("Counter", Vector3.new(18, 3.4, 2.6), 47, 0, 1.8, wood, rgb(150, 146, 140))
	box("Countertop", Vector3.new(18.4, 0.3, 2.9), 47, 3.4, 1.8, Enum.Material.Marble, rgb(200, 200, 195))
	box("Cabinets", Vector3.new(18, 3, 1.6), 47, 7.2, 1.3, wood, rgb(140, 136, 130))
	box("Fridge", Vector3.new(3.2, 7.5, 3), 57.9, 0, 14, Enum.Material.Metal, rgb(186, 186, 186))
	box("TableTop", Vector3.new(6, 0.3, 4), 46, 2.9, 13, wood, darkWood)
	for _, l in { { 43.4, 11.4 }, { 48.6, 11.4 }, { 43.4, 14.6 }, { 48.6, 14.6 } } do
		box("TableLeg", Vector3.new(0.3, 2.9, 0.3), l[1], 0, l[2], wood, darkWood)
	end
	box("KitchenChair", Vector3.new(2, 2, 2), 46, 0, 16.2, wood, darkWood)
	box("KitchenChair", Vector3.new(2, 2, 2), 41.6, 0, 13, wood, darkWood, math.rad(70))
	note(46.5, 3.2, 13)

	-- study
	box("Desk", Vector3.new(6, 3, 2.6), 42, 0, 34.2, wood, darkWood)
	box("DeskChair", Vector3.new(2, 2, 2), 42, 0, 31.6, wood, darkWood)
	box("Bookshelf", Vector3.new(2, 9, 8), 58.5, 0, 30, wood, darkWood)
	note(41.2, 3, 34.0)
	portrait(ctx, wallFrame(42, 6.5, 24.5, Vector3.new(0, 0, 1)))
end

-- a lamp on a bracket, halfway up a corridor wall
local function sconce(ctx: Ctx, cell: Cell?, wall: CFrame, color: Color3)
	local at = wall * CFrame.new(0, 7.4, -0.5)
	ctx.decor(ctx.part(ctx.lights, "Bracket", Vector3.new(0.3, 0.3, 1), at * CFrame.new(0, -0.6, 0.25), Enum.Material.Metal, rgb(70, 66, 60), nil))
	ctx.decor(ctx.part(ctx.lights, "Shade", Vector3.new(1.3, 1.2, 1.2), at * UP, Enum.Material.Fabric, rgb(170, 164, 152), Enum.PartType.Cylinder))
	local bulb = ctx.decor(ctx.part(ctx.lights, "Bulb", Vector3.new(0.6, 0.6, 0.6), at * CFrame.new(0, -0.45, 0), Enum.Material.Neon, rgb(225, 218, 200), Enum.PartType.Ball))
	bulb.CastShadow = false
	local light = Instance.new("PointLight")
	light.Range = 18
	light.Brightness = ctx.random:NextNumber(1.0, 1.4)
	light.Color = color
	light.Shadows = true
	light.Parent = bulb
	bulb:SetAttribute("Buzz", ctx.random:NextNumber() < 0.3)
	ctx.addLamp(bulb, light, cell)
end

local function grandfatherClock(ctx: Ctx, wall: CFrame)
	local at = wall * CFrame.new(ctx.random:NextNumber(-3, 3), 0, -1)
	solid(ctx, "ClockBody", Vector3.new(1.8, 8.6, 1.6), at * CFrame.new(0, 4.3, 0), Enum.Material.Wood, rgb(52, 42, 36))
	ctx.sign(at * CFrame.new(0, 6.8, -0.82), Vector2.new(1.3, 1.3), "XII", rgb(30, 30, 30), rgb(200, 196, 186), false, Enum.Font.Fondamento)
	deco(ctx, "Pendulum", Vector3.new(0.15, 2.4, 0.1), at * CFrame.new(0, 3.4, -0.82), Enum.Material.Metal, rgb(160, 150, 110))
end

Themes.house = {
	-- the maze is the house now: papered walls, wood floors, panelling
	wall = { material = Enum.Material.Plaster, color = rgb(128, 124, 118) },
	hubWall = { material = Enum.Material.Plaster, color = rgb(170, 164, 154) },
	floor = { material = Enum.Material.WoodPlanks, color = rgb(64, 56, 50) },
	hubFloor = function(room: string): Style
		return HOUSE_FLOORS[room] or HOUSE_FLOORS.hall
	end,
	ceiling = { material = Enum.Material.Plaster, color = rgb(66, 66, 64) },
	hubCeiling = { material = Enum.Material.Plaster, color = rgb(128, 126, 122) },
	trim = { material = Enum.Material.Wood, color = rgb(70, 58, 50) },
	tunnel = { material = Enum.Material.Plaster, color = rgb(128, 124, 118) },
	locker = { material = Enum.Material.Wood, color = rgb(70, 58, 50) },
	columns = false,
	writings = {
		"WAKE UP", "IIII IIII IIII", "NOT YET", "6", "IT'S STILL HERE", "SHH", "BEHIND", "GREY", "WAKE UP WAKE UP",
		"HOW LONG", "DON'T", "HELP",
	},
	writingColor = rgb(28, 22, 22),
	writingFont = Enum.Font.PermanentMarker,
	writingGlow = false,
	exitStyle = "double",
	lamp = function(ctx: Ctx, cell: Cell?, position: Vector3)
		local sides = if cell then ctx.wallSides(cell.x, cell.z) else {}
		if cell and #sides > 0 and ctx.random:NextNumber() < 0.4 then
			sconce(ctx, cell, ctx.sideFrame(cell.x, cell.z, randomSide(ctx, sides)), ctx.night.lighting.LampColor)
		else
			ceilingLamp(ctx, cell, position, ctx.night.lighting.LampColor, ctx.random:NextNumber(1.1, 1.7), 20)
		end
	end,
	hubLamps = function(ctx: Ctx)
		local O = ctx.hubOrigin
		for _, spot in { { 12, 12, 1.3 }, { 48, 12, 1.4 }, { 12, 30, 0.8 }, { 48, 30, 1.0 }, { 30, 18, 1.2 }, { 30, 5, 0.9 } } do
			hangingLamp(ctx, O + Vector3.new(spot[1], 0, spot[2]), spot[3], ctx.night.lighting.LampColor)
		end
	end,
	cell = function(ctx: Ctx, x: number, z: number, info: CellInfo)
		local random = ctx.random
		local C, T, H = ctx.C, ctx.T, ctx.H
		local sides = ctx.wallSides(x, z)
		-- panelling and a picture rail on every wall
		for _, side in sides do
			local f = ctx.sideFrame(x, z, side)
			deco(ctx, "Wainscot", Vector3.new(C - T - 0.1, 3.6, 0.14), f * CFrame.new(0, 1.8, -0.07), Enum.Material.Wood, rgb(50, 42, 36))
			deco(ctx, "ChairRail", Vector3.new(C - T - 0.1, 0.3, 0.26), f * CFrame.new(0, 3.7, -0.13), Enum.Material.Wood, rgb(68, 56, 48))
			deco(ctx, "Cornice", Vector3.new(C - T - 0.1, 0.45, 0.3), f * CFrame.new(0, H - 0.25, -0.15), Enum.Material.Plaster, rgb(150, 146, 140))
		end
		if info.room or info.spot or #sides == 0 then
			return
		end
		-- windows in the outside walls, with nothing behind them
		for _, side in sides do
			if Dressing.isBoundary(ctx, x, z, side) and random:NextNumber() < 0.35 then
				Dressing.window(ctx, ctx.sideFrame(x, z, side), 4.6, rgb(84, 80, 78))
				return
			end
		end
		local f = ctx.sideFrame(x, z, randomSide(ctx, sides))
		local roll = random:NextNumber()
		if Maze.passableCount(ctx.layout, x, z) == 1 and roll < 0.55 then
			-- dead ends: furniture under dust sheets. One of them is the shape of a person.
			local kind = if random:NextNumber() < 0.4 then "person" elseif random:NextNumber() < 0.5 then "tall" else "low"
			Dressing.sheeted(ctx, f * CFrame.new(random:NextNumber(-2, 2), 0, -2.6) * CFrame.Angles(0, math.pi, 0), kind)
		elseif roll < 0.12 then
			Dressing.fakeDoor(ctx, f * CFrame.new(random:NextNumber(-2.5, 2.5), 0, 0), rgb(84, 70, 60))
		elseif roll < 0.22 then
			portrait(ctx, f * CFrame.new(random:NextNumber(-2.5, 2.5), 6.4, 0))
		elseif roll < 0.32 then
			Dressing.tableLamp(ctx, f, { x = x, z = z }, #ctx.lamps < 44 and random:NextNumber() < 0.55)
		elseif roll < 0.37 then
			-- a chair, facing the wall
			Dressing.chair(ctx, f * CFrame.new(random:NextNumber(-3, 3), 0, -1.7) * CFrame.Angles(0, math.pi, 0), rgb(56, 46, 40), false)
		elseif roll < 0.42 then
			Dressing.mirror(ctx, f)
		elseif roll < 0.46 then
			grandfatherClock(ctx, f)
		end
	end,
	room = function(ctx: Ctx, block: { Cell })
		local i = roomIndex(ctx, block)
		if i % 3 == 1 then
			Dressing.diningRoom(ctx, block, block[1])
		elseif i % 3 == 2 then
			Dressing.nursery(ctx, block)
		else
			Dressing.bathroom(ctx, block)
		end
	end,
	hub = houseProps,
	extra = noop,
	spawns = function(ctx: Ctx): { CFrame }
		local points = {}
		for _, s in { { 10, 33.5 }, { 13, 33.5 }, { 10, 29.5 }, { 13, 29.5 }, { 16, 33.5 }, { 16, 30.5 } } do
			local pos = ctx.hubOrigin + Vector3.new(s[1], 3.5, s[2])
			table.insert(points, CFrame.lookAt(pos, pos + Vector3.new(1, 0, 0)))
		end
		return points
	end,
}

---------------------------------------------------------------------------
-- Shared by the nights below

local WARD_SIGNS = { "WARD B", "ISOLATION  >", "<  RADIOLOGY", "NO VISITORS", "QUIET PLEASE", "ROOM 13", "STAFF ONLY", "SURGERY  >", "PEDIATRICS", "<  MORGUE" }

local function wardBed(ctx: Ctx, frame: CFrame)
	local metal = Enum.Material.Metal
	local fabric = Enum.Material.Fabric
	solid(ctx, "BedFrame", Vector3.new(3.4, 0.4, 7), frame * CFrame.new(0, 2, 0), metal, rgb(185, 185, 182))
	solid(ctx, "Mattress", Vector3.new(3.1, 0.6, 6.6), frame * CFrame.new(0, 2.5, 0), fabric, rgb(225, 225, 220))
	deco(ctx, "Sheet", Vector3.new(3.3, 0.2, 4.2), frame * CFrame.new(0.1, 2.85, 1.1) * CFrame.Angles(0, ctx.random:NextNumber(-0.15, 0.15), 0), fabric, rgb(200, 205, 200))
	deco(ctx, "Pillow", Vector3.new(2.4, 0.5, 1.2), frame * CFrame.new(0, 3, -2.7), fabric, rgb(235, 235, 230))
	solid(ctx, "Headboard", Vector3.new(3.4, 2.6, 0.25), frame * CFrame.new(0, 2.9, -3.45), metal, rgb(170, 170, 168))
	for _, lx in { -1.5, 1.5 } do
		for _, lz in { -3.2, 3.2 } do
			deco(ctx, "BedLeg", Vector3.new(0.2, 1.8, 0.2), frame * CFrame.new(lx, 0.9, lz), metal, rgb(120, 120, 118))
		end
	end
end

-- The nurse station, waiting chairs, ward signs, a clock stopped at 3:33 and the EXIT sign.
local function nurseStation(ctx: Ctx)
	local hub = ctx.layout.hub
	local O = ctx.hubOrigin
	local C = ctx.C
	local W = hub.w * C
	-- nurse station near the west wall, waiting chairs on the east
	solid(ctx, "Counter", Vector3.new(2.2, 3.6, 9), CFrame.new(O + Vector3.new(6, 1.8, C * 1.4)), Enum.Material.Marble, rgb(200, 196, 190))
	solid(ctx, "Counter", Vector3.new(6, 3.6, 2.2), CFrame.new(O + Vector3.new(8.9, 1.8, C * 1.4 - 3.4)), Enum.Material.Marble, rgb(200, 196, 190))
	solid(ctx, "Monitor", Vector3.new(1.6, 1.2, 0.3), CFrame.new(O + Vector3.new(7, 4.2, C * 1.4)) * CFrame.Angles(0, math.rad(90), 0), Enum.Material.SmoothPlastic, rgb(25, 25, 28))
	for i = 0, 3 do
		local p = O + Vector3.new(W - 2.2, 0, 4 + i * 2.6)
		solid(ctx, "WaitingChair", Vector3.new(2, 0.4, 2), CFrame.new(p + Vector3.new(0, 1.7, 0)), Enum.Material.Plastic, rgb(70, 90, 110))
		solid(ctx, "WaitingChairBack", Vector3.new(0.3, 2.2, 2), CFrame.new(p + Vector3.new(0.9, 2.8, 0)), Enum.Material.Plastic, rgb(70, 90, 110))
	end
	local walls = hubWalls(ctx)
	for i = 1, 2 do
		local w = walls[(i * 3) % #walls + 1]
		ctx.note(ctx.sideFrame(w.cell.x, w.cell.z, w.side) * CFrame.new(0, 3.4, -1.2))
	end
	for i, w in walls do
		if i % 2 == 0 then
			ctx.sign(ctx.sideFrame(w.cell.x, w.cell.z, w.side) * CFrame.new(0, 7.5, -0.08), Vector2.new(4, 1), WARD_SIGNS[i % #WARD_SIGNS + 1], rgb(20, 20, 20), rgb(225, 225, 220), false, Enum.Font.GothamBold)
		end
	end
	-- the clock stopped at 3:33
	local w = walls[1]
	ctx.sign(ctx.sideFrame(w.cell.x, w.cell.z, w.side) * CFrame.new(2.5, 9, -0.08), Vector2.new(2, 1), "3:33", rgb(255, 60, 50), rgb(10, 10, 10), true, Enum.Font.Code)
	-- glowing EXIT sign above the doors, facing in
	local e = ctx.layout.exitCell
	ctx.sign(ctx.sideFrame(e.x, e.z, "S") * CFrame.new(0, ctx.exitHeight + 1.1, -0.15), Vector2.new(4, 1.2), "EXIT", rgb(230, 255, 230), rgb(20, 160, 60), true, Enum.Font.GothamBlack)
end

local function cagedLamp(ctx: Ctx, cell: Cell?, position: Vector3, powered: boolean)
	local H = ctx.ceiling
	local y = H - 1.2
	local bulb = ctx.decor(ctx.part(ctx.lights, "Bulb", Vector3.new(1, 1, 1), CFrame.new(position.X, y, position.Z), Enum.Material.Neon, if powered then rgb(200, 255, 220) else rgb(40, 46, 42), Enum.PartType.Ball))
	bulb.CastShadow = false
	for a = 0, 3 do
		ctx.decor(ctx.part(ctx.lights, "Cage", Vector3.new(0.08, 1.5, 0.08), CFrame.new(position.X, y, position.Z) * CFrame.Angles(0, a * math.pi / 2, 0) * CFrame.new(0.6, 0, 0), Enum.Material.Metal, rgb(60, 60, 60), nil))
	end
	ctx.decor(ctx.part(ctx.lights, "Mount", Vector3.new(0.3, 0.9, 0.3), CFrame.new(position.X, H - 0.45, position.Z), Enum.Material.Metal, rgb(50, 50, 50), nil))
	local light = Instance.new("PointLight")
	light.Range = 20
	light.Brightness = if powered then 0.7 else 1.4
	light.Color = ctx.night.lighting.LampColor
	light.Shadows = true
	light.Enabled = powered
	light.Parent = bulb
	bulb:SetAttribute("Buzz", ctx.random:NextNumber() < 0.5)
	bulb:SetAttribute("OnColor", rgb(200, 255, 220))
	ctx.addLamp(bulb, light, cell)
end

-- Two dead pumps, the MAIN POWER panel the generators bring back, and the lift sign.
local function pumpHall(ctx: Ctx)
	local O = ctx.hubOrigin
	local hub = ctx.layout.hub
	local C = ctx.C
	local W = hub.w * C
	for i = 0, 1 do
		solid(ctx, "Pump", Vector3.new(6, 3.2, 3.2), CFrame.new(O + Vector3.new(3.5, 2.2, 6 + i * 9)) * CFrame.Angles(0, math.rad(90), 0), Enum.Material.Metal, rgb(70, 90, 80), Enum.PartType.Cylinder)
	end
	local panel = solid(ctx, "Panel", Vector3.new(5, 4.5, 1), CFrame.new(O + Vector3.new(W - 1.2, 2.25, C * 1.5)) * CFrame.Angles(0, math.rad(-90), 0), Enum.Material.Metal, rgb(70, 72, 70))
	local screen = ctx.sign(panel.CFrame * CFrame.new(0, 0.6, -0.55), Vector2.new(4, 2), "MAIN POWER\nOFFLINE", rgb(255, 80, 60), rgb(10, 10, 10), true, Enum.Font.Code)
	screen.Name = "PowerPanel"
	local walls = hubWalls(ctx)
	local w = walls[1]
	ctx.note(ctx.sideFrame(w.cell.x, w.cell.z, w.side) * CFrame.new(0, 3.4, -1.2))
	local e = ctx.layout.exitCell
	ctx.sign(ctx.sideFrame(e.x, e.z, "S") * CFrame.new(0, ctx.exitHeight + 1, -0.15), Vector2.new(5, 1.1), "SERVICE LIFT", rgb(255, 210, 60), rgb(25, 25, 20), true, Enum.Font.GothamBlack)
end

local function bust(ctx: Ctx, at: CFrame)
	solid(ctx, "Plinth", Vector3.new(2.2, 4, 2.2), at * CFrame.new(0, 2, 0), Enum.Material.Marble, rgb(210, 210, 206))
	local marble = Enum.Material.Marble
	solid(ctx, "Shoulders", Vector3.new(1.8, 0.9, 1), at * CFrame.new(0, 4.45, 0), marble, rgb(232, 232, 228))
	local head = solid(ctx, "BustHead", Vector3.new(0.95, 1.2, 1), at * CFrame.new(0, 5.4, 0) * CFrame.Angles(0, ctx.random:NextNumber(-1, 1), 0), marble, rgb(232, 232, 228))
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = head
end

-- Decoy statues: some of these are just statues. A mix of both kinds, so you can't tell
-- the real one by its shape.
local function decoyStatues(ctx: Ctx, count: number)
	local layout = ctx.layout
	local spots: { [string]: boolean } = {}
	for _, s in layout.spots do
		spots[Maze.key(s.x, s.z)] = true
	end
	local placed = 0
	local tries = 0
	while placed < count and tries < 80 do
		tries += 1
		local x = ctx.random:NextInteger(0, layout.width - 1)
		local z = ctx.random:NextInteger(0, layout.depth - 1)
		local k = Maze.key(x, z)
		if not Maze.isHub(layout, x, z) and not spots[k] and (math.abs(x - layout.entrance.x) + math.abs(z - layout.entrance.z)) > 1 then
			spots[k] = true
			placed += 1
			local variant = Monsters.STATUE_VARIANTS[ctx.random:NextInteger(1, #Monsters.STATUE_VARIANTS)]
			local rig = Monsters.build("Statue", { preview = true, decoy = true, variant = variant })
			Monsters.applyStatuePose(rig, ctx.random:NextInteger(1, #Monsters.STATUE_POSES), nil)
			local center = ctx.cellCenter(x, z)
			rig.model:PivotTo(CFrame.new(center + Vector3.new(ctx.random:NextNumber(-3, 3), rig.rootHeight, ctx.random:NextNumber(-3, 3))) * CFrame.Angles(0, ctx.random:NextNumber(0, 6.28), 0))
			Monsters.solve(rig)
			rig.model.Name = "Statue"
			rig.model.Parent = ctx.props
			local blocker = ctx.part(ctx.props, "StatueBase", Vector3.new(2.6, 8, 2.4), rig.root.CFrame * CFrame.new(0, -0.4, 0), Enum.Material.Marble, rgb(200, 200, 196), nil)
			blocker.Transparency = 1
		end
	end
end

---------------------------------------------------------------------------
-- Helpers for the trim and the dead ends

local OPPOSITE: { [string]: string } = { N = "S", S = "N", E = "W", W = "E" }

type Band = { y: number, h: number, depth: number, material: Enum.Material, color: Color3 }

local function band(y: number, h: number, depth: number, material: Enum.Material, color: Color3): Band
	return { y = y, h = h, depth = depth, material = material, color = color }
end

-- The opening in an edge: its width and height (0, 0 for a solid wall), or nil when
-- there's no wall there at all.
local function opening(ctx: Ctx, kind: string): (number?, number)
	if kind == "wall" then
		return 0, 0
	elseif kind == "door" or kind == "doorway" then
		return ctx.doorWidth, ctx.doorHeight
	elseif kind == "exit" then
		return ctx.exitWidth, ctx.exitHeight
	elseif kind == "hole" then
		return 6, math.min(9.5, ctx.H - 1.5)
	end
	return nil, 0
end

-- Horizontal bands (skirting, tiles, rails, cornices) along every wall of a cell. They
-- run either side of a doorway and straight across above it, so the trim reads as one
-- line through the whole building.
local function wallBands(ctx: Ctx, x: number, z: number, bands: { Band })
	local length = ctx.C - ctx.T - 0.1
	for _, side in Maze.DIRS do
		local w, h = opening(ctx, Maze.getEdge(ctx.layout, x, z, side))
		if w then
			local f = ctx.sideFrame(x, z, side)
			local seg = (length - w) / 2 - 0.45
			for _, b in bands do
				local y = b.y + b.h / 2
				if w == 0 or b.y >= h + 0.5 then
					deco(ctx, "Band", Vector3.new(length, b.h, b.depth), f * CFrame.new(0, y, -b.depth / 2), b.material, b.color)
				elseif seg > 0.2 then
					for _, sx in { -1, 1 } do
						deco(ctx, "Band", Vector3.new(seg, b.h, b.depth), f * CFrame.new(sx * (w / 2 + 0.45 + seg / 2), y, -b.depth / 2), b.material, b.color)
					end
				end
			end
		end
	end
end

local function eachHubCell(ctx: Ctx, fn: (x: number, z: number) -> ())
	local hub = ctx.layout.hub
	for rz = 0, hub.d - 1 do
		for rx = 0, hub.w - 1 do
			fn(hub.x0 + rx, hub.z0 + rz)
		end
	end
end

-- The closed end of a dead end (the side opposite its one way in).
local function deadEndSide(ctx: Ctx, x: number, z: number): string?
	for _, d in Maze.DIRS do
		if Maze.isPassable(Maze.getEdge(ctx.layout, x, z, d)) then
			return OPPOSITE[d]
		end
	end
	return nil
end

-- The wall at the closed end of a dead end, looking back down the corridor.
local function deadEndBack(ctx: Ctx, x: number, z: number): CFrame?
	local side = deadEndSide(ctx, x, z)
	return if side then ctx.sideFrame(x, z, side) else nil
end

---------------------------------------------------------------------------
-- NIGHT 2: THE RED WARD (a sanatorium's isolation wing)

local SAN_TILE = rgb(214, 214, 208)

local function sanBands(_ctx: Ctx): { Band }
	return {
		band(0, 0.7, 0.18, Enum.Material.Marble, rgb(26, 26, 28)),
		band(0.7, 5.5, 0.12, Enum.Material.CeramicTiles, SAN_TILE),
		band(6.2, 0.3, 0.2, Enum.Material.CeramicTiles, rgb(34, 34, 36)),
	}
end

-- Black and white floor tiles, lined up across the whole wing.
local function checkerFloor(ctx: Ctx, x: number, z: number)
	local n = 4 -- big tiles: every tile is a part, and the wing has a lot of floor
	local s = ctx.C / n
	for i = 0, n - 1 do
		for j = 0, n - 1 do
			if (x * n + i + z * n + j) % 2 == 0 then
				local tile = deco(ctx, "FloorTile", Vector3.new(s, 0.04, s), CFrame.new(x * ctx.C + (i + 0.5) * s, 0.07, z * ctx.C + (j + 0.5) * s), Enum.Material.Marble, rgb(178, 178, 174))
				tile.Reflectance = 0.05
				tile.CastShadow = false
			end
		end
	end
end

-- A long fluorescent fitting. One in five is dead.
local function tubeLamp(ctx: Ctx, cell: Cell?, position: Vector3)
	local random = ctx.random
	local H = ctx.ceiling
	local axis = if cell then Dressing.straightAxis(ctx, cell.x, cell.z) else nil
	local base = CFrame.new(position.X, H, position.Z) * CFrame.Angles(0, if axis == "NS" then math.rad(90) else 0, 0)
	local dead = random:NextNumber() < 0.2
	ctx.decor(ctx.part(ctx.lights, "Fixture", Vector3.new(5.4, 0.3, 1.4), base * CFrame.new(0, -0.15, 0), Enum.Material.Metal, rgb(120, 120, 118), nil))
	local tube = ctx.decor(ctx.part(ctx.lights, "Bulb", Vector3.new(5, 0.12, 1.1), base * CFrame.new(0, -0.36, 0), if dead then Enum.Material.SmoothPlastic else Enum.Material.Neon, if dead then rgb(60, 60, 62) else rgb(230, 234, 240), nil))
	tube.CastShadow = false
	if dead then
		return
	end
	local light = Instance.new("PointLight")
	light.Range = 22
	light.Brightness = random:NextNumber(1.2, 1.6)
	light.Color = ctx.night.lighting.LampColor
	light.Shadows = true
	light.Parent = tube
	tube:SetAttribute("Buzz", random:NextNumber() < 0.35)
	ctx.addLamp(tube, light, cell)
end

-- The only colour in the wing: a red lamp over some of the doors.
local function emergencyLamp(ctx: Ctx, frame: CFrame, y: number)
	local box = ctx.decor(ctx.part(ctx.lights, "EmergencyLamp", Vector3.new(1.6, 0.55, 0.5), frame * CFrame.new(0, y, -(ctx.T / 2 + 0.28)), Enum.Material.Neon, rgb(190, 22, 16), nil))
	box.CastShadow = false
	local light = Instance.new("PointLight")
	light.Range = 10
	light.Brightness = 0.9
	light.Color = rgb(255, 40, 28)
	light.Shadows = false
	light.Parent = box
	ctx.addLamp(box, light, nil)
end

local function wheelchair(ctx: Ctx, base: CFrame)
	local seat = rgb(40, 40, 44)
	solid(ctx, "Seat", Vector3.new(2, 0.3, 2), base * CFrame.new(0, 1.8, 0), Enum.Material.Fabric, seat)
	solid(ctx, "Back", Vector3.new(2, 2, 0.3), base * CFrame.new(0, 2.9, 1), Enum.Material.Fabric, seat)
	for _, sx in { -1.15, 1.15 } do
		deco(ctx, "Wheel", Vector3.new(0.15, 2.4, 2.4), base * CFrame.new(sx, 1.2, 0.3), Enum.Material.Metal, rgb(90, 90, 90), Enum.PartType.Cylinder)
		deco(ctx, "Handle", Vector3.new(0.15, 0.15, 0.8), base * CFrame.new(sx * 0.8, 3.9, 1.35), Enum.Material.Metal, rgb(120, 120, 120))
	end
	deco(ctx, "Footrest", Vector3.new(1.6, 0.15, 0.7), base * CFrame.new(0, 0.6, -1.2), Enum.Material.Metal, rgb(110, 110, 110))
end

local function ivStand(ctx: Ctx, base: CFrame)
	deco(ctx, "Pole", Vector3.new(7, 0.15, 0.15), base * CFrame.new(0, 3.5, 0) * UP, Enum.Material.Metal, rgb(180, 180, 180), Enum.PartType.Cylinder)
	local bag = deco(ctx, "Bag", Vector3.new(0.7, 1.1, 0.25), base * CFrame.new(0.35, 6.2, 0), Enum.Material.Glass, rgb(220, 225, 220))
	bag.Transparency = 0.4
	for a = 0, 2 do
		deco(ctx, "Foot", Vector3.new(1.4, 0.12, 0.15), base * CFrame.Angles(0, a * 2.09, 0) * CFrame.new(0.6, 0.1, 0), Enum.Material.Metal, rgb(150, 150, 150))
	end
end

-- An iron bed with its head against a wall (the wall frame looks into the room).
local function ironBed(ctx: Ctx, wall: CFrame, offset: number, occupied: boolean)
	local bed = wall * CFrame.new(offset, -1.2, -4) * CFrame.Angles(0, math.pi, 0)
	wardBed(ctx, bed)
	if occupied then
		Dressing.egg(deco(ctx, "Body", Vector3.new(2, 0.9, 5.4), bed * CFrame.new(0, 3.35, 0.5), Enum.Material.Fabric, rgb(206, 206, 202)))
		Dressing.egg(deco(ctx, "BodyHead", Vector3.new(1.2, 0.8, 1.3), bed * CFrame.new(0, 3.4, -2.4), Enum.Material.Fabric, rgb(206, 206, 202)))
	end
end

-- A high window above the tiles: wired glass, nothing but dark behind it.
local function highWindow(ctx: Ctx, wall: CFrame)
	local w, h = 5, math.min(3.6, ctx.H - 7.6)
	if h < 1.5 then
		return
	end
	local at = wall * CFrame.new(ctx.random:NextNumber(-1.5, 1.5), 6.9 + h / 2, 0)
	local frame = rgb(46, 46, 48)
	solid(ctx, "WindowFrame", Vector3.new(w + 0.6, h + 0.6, 0.3), at * CFrame.new(0, 0, -0.15), Enum.Material.Metal, frame)
	local glass = deco(ctx, "WindowGlass", Vector3.new(w, h, 0.06), at * CFrame.new(0, 0, -0.33), Enum.Material.Glass, rgb(14, 15, 18))
	glass.Reflectance = 0.25
	for i = 1, 2 do
		deco(ctx, "Mullion", Vector3.new(0.14, h, 0.1), at * CFrame.new(-w / 2 + i * w / 3, 0, -0.38), Enum.Material.Metal, frame)
	end
	deco(ctx, "Mullion", Vector3.new(w, 0.14, 0.1), at * CFrame.new(0, 0, -0.38), Enum.Material.Metal, frame)
end

local function hospitalBench(ctx: Ctx, wall: CFrame)
	local at = wall * CFrame.new(ctx.random:NextNumber(-2, 2), 0, -1.2)
	local wood = rgb(80, 70, 60)
	solid(ctx, "Bench", Vector3.new(5.6, 0.3, 1.6), at * CFrame.new(0, 1.8, 0), Enum.Material.Wood, wood)
	deco(ctx, "BenchBack", Vector3.new(5.6, 1.2, 0.2), at * CFrame.new(0, 3.2, 0.75), Enum.Material.Wood, wood)
	for _, sx in { -2.4, 2.4 } do
		deco(ctx, "BenchLeg", Vector3.new(0.2, 1.65, 1.4), at * CFrame.new(sx, 0.82, 0), Enum.Material.Metal, rgb(60, 60, 60))
	end
end

-- A ward: iron beds along the walls in pairs, a curtain between each pair.
local function sanatoriumWard(ctx: Ctx, block: { Cell })
	local random = ctx.random
	local lockerSides: { [string]: boolean } = {}
	for _, l in ctx.layout.lockers do
		lockerSides[Maze.key(l.x, l.z) .. l.side] = true
	end
	local c = Dressing.blockCenter(ctx, block)
	deco(ctx, "Lino", Vector3.new(ctx.C * 2 - ctx.T, 0.05, ctx.C * 2 - ctx.T), CFrame.new(c + Vector3.new(0, 0.03, 0)), Enum.Material.SmoothPlastic, rgb(104, 106, 104))
	local H = ctx.ceiling
	for _, cell in block do
		local side: string? = nil
		for _, s in ctx.wallSides(cell.x, cell.z) do
			if not lockerSides[Maze.key(cell.x, cell.z) .. s] then
				side = s
				break
			end
		end
		if side then
			local wall = ctx.sideFrame(cell.x, cell.z, side)
			for _, off in { -2.9, 2.9 } do
				ironBed(ctx, wall, off, random:NextNumber() < 0.4)
			end
			deco(ctx, "CurtainRail", Vector3.new(0.15, 0.15, 7.5), wall * CFrame.new(0, H - 1.2, -3.75), Enum.Material.Metal, rgb(150, 150, 150))
			local drawn = random:NextNumber(3, 7)
			local curtain = deco(ctx, "Curtain", Vector3.new(0.08, H - 3.4, drawn), wall * CFrame.new(0, (H - 1.2) / 2 + 0.9, -(drawn / 2 + 0.2)), Enum.Material.Fabric, rgb(196, 198, 194))
			curtain.Transparency = 0.15
		end
	end
end

Themes.sanatorium = {
	wall = { material = Enum.Material.Plaster, color = rgb(104, 108, 104) },
	hubWall = { material = Enum.Material.Plaster, color = rgb(110, 112, 108) },
	floor = { material = Enum.Material.Marble, color = rgb(34, 34, 36), reflect = 0.06 },
	hubFloor = function(_room: string): Style
		return { material = Enum.Material.Marble, color = rgb(34, 34, 36), reflect = 0.06 }
	end,
	ceiling = { material = Enum.Material.Plaster, color = rgb(140, 140, 136) },
	hubCeiling = { material = Enum.Material.Plaster, color = rgb(140, 140, 136) },
	trim = { material = Enum.Material.Wood, color = rgb(62, 64, 62) },
	tunnel = { material = Enum.Material.CeramicTiles, color = SAN_TILE },
	locker = { material = Enum.Material.Metal, color = rgb(150, 154, 156) },
	columns = false,
	portholes = true,
	writings = {
		"SHH", "ROOM 13", "UNDER", "IIII IIII", "NURSE", "LOOK DOWN", "STAY", "NO", "IT CRAWLS", "WHO",
	},
	writingColor = rgb(110, 8, 8),
	writingFont = Enum.Font.PermanentMarker,
	writingGlow = false,
	exitStyle = "double",
	lamp = tubeLamp,
	hubLamps = function(ctx: Ctx)
		hubCellLamps(ctx, Themes.sanatorium)
	end,
	cell = function(ctx: Ctx, x: number, z: number, info: CellInfo)
		local random = ctx.random
		wallBands(ctx, x, z, sanBands(ctx))
		if info.room then
			return
		end
		checkerFloor(ctx, x, z)
		if info.spot then
			return
		end
		local sides = ctx.wallSides(x, z)
		for _, side in sides do
			if Dressing.isBoundary(ctx, x, z, side) and random:NextNumber() < 0.4 then
				highWindow(ctx, ctx.sideFrame(x, z, side))
			end
		end
		if Maze.passableCount(ctx.layout, x, z) == 1 then
			-- the end of a corridor: someone left something here and walked away
			local back = deadEndBack(ctx, x, z)
			if back and random:NextNumber() < 0.7 then
				local roll = random:NextNumber()
				if roll < 0.3 then
					wheelchair(ctx, back * CFrame.new(0, 0, -2.6) * CFrame.Angles(0, math.pi, 0))
				elseif roll < 0.6 then
					ironBed(ctx, back, 0, true)
				elseif roll < 0.8 then
					Dressing.chair(ctx, back * CFrame.new(-0.8, 0, -1.8) * CFrame.Angles(0, math.pi, 0), rgb(70, 72, 74), false)
					ivStand(ctx, back * CFrame.new(1.6, 0, -2.4))
				else
					wardBed(ctx, back * CFrame.new(0.8, -1.2, -4.4) * CFrame.Angles(0, math.rad(80), 0))
				end
			end
			return
		end
		-- the corridors stay almost bare
		if #sides > 0 then
			local f = ctx.sideFrame(x, z, randomSide(ctx, sides))
			local roll = random:NextNumber()
			if roll < 0.07 then
				hospitalBench(ctx, f)
			elseif roll < 0.1 then
				wheelchair(ctx, f * CFrame.new(random:NextNumber(-3, 3), 0, -1.6) * CFrame.Angles(0, math.rad(90), 0))
			end
		end
	end,
	room = function(ctx: Ctx, block: { Cell })
		local i = roomIndex(ctx, block)
		if i == 1 then
			Dressing.operatingRoom(ctx, block, block[1])
		elseif i == 2 then
			Dressing.morgue(ctx, block)
		else
			sanatoriumWard(ctx, block)
		end
	end,
	hub = function(ctx: Ctx)
		eachHubCell(ctx, function(x: number, z: number)
			wallBands(ctx, x, z, sanBands(ctx))
			checkerFloor(ctx, x, z)
		end)
		nurseStation(ctx)
	end,
	extra = function(ctx: Ctx)
		-- a number beside every door, and a red lamp over some of them
		local layout = ctx.layout
		local number = 10
		for z = 0, layout.depth - 1 do
			for x = 0, layout.width - 1 do
				for _, dir in { "N", "E" } do
					local kind = Maze.getEdge(layout, x, z, dir)
					if (kind == "door" or kind == "doorway") and not Maze.isHub(layout, x, z) then
						number += 1
						local frame = ctx.edgeFrame(x, z, dir)
						local face = -(ctx.T / 2 + 0.06)
						ctx.sign(frame * CFrame.new(ctx.doorWidth / 2 + 1.3, 7.6, face), Vector2.new(1.1, 0.7), tostring(number), rgb(220, 220, 214), rgb(22, 22, 24), false, Enum.Font.GothamBold)
						if ctx.random:NextNumber() < 0.2 then
							emergencyLamp(ctx, frame, ctx.doorHeight + 0.9)
						end
					end
				end
			end
		end
		-- plastic strip curtains across a few corridors: you see shapes through them
		local rooms: { [string]: boolean } = {}
		for _, block in layout.roomBlocks do
			for _, c in block do
				rooms[Maze.key(c.x, c.z)] = true
			end
		end
		local C, H = ctx.C, ctx.H
		for _, e in Dressing.openEdges(ctx, rooms) do
			if ctx.random:NextNumber() < 0.05 then
				local frame = ctx.edgeFrame(e.x, e.z, e.dir)
				deco(ctx, "CurtainRail", Vector3.new(C - 1, 0.3, 0.3), frame * CFrame.new(0, H - 1.2, 0), Enum.Material.Metal, rgb(150, 150, 150))
				local n = 12
				for i = 0, n - 1 do
					local strip = deco(ctx, "PlasticStrip", Vector3.new((C - 1) / n + 0.15, H - 1.6, 0.05), frame * CFrame.new(-(C - 1) / 2 + (i + 0.5) * (C - 1) / n, (H - 1.6) / 2 + 0.2, (i % 2) * 0.06), Enum.Material.Glass, rgb(210, 214, 212))
					strip.Transparency = 0.55
					strip.CastShadow = false
				end
			end
		end
	end,
	spawns = hallSpawns,
}

---------------------------------------------------------------------------
-- NIGHT 3: THE DROWNED TUNNELS (storm drains)

-- A caged bulb on a bracket, low on a tunnel wall. Dead until the power's back on.
local function wallCage(ctx: Ctx, cell: Cell?, wall: CFrame, powered: boolean)
	local at = wall * CFrame.new(0, 4.6, -0.85)
	ctx.decor(ctx.part(ctx.lights, "Bracket", Vector3.new(0.25, 0.25, 0.9), wall * CFrame.new(0, 4.6, -0.4), Enum.Material.Metal, rgb(50, 50, 50), nil))
	local bulb = ctx.decor(ctx.part(ctx.lights, "Bulb", Vector3.new(0.8, 0.8, 0.8), at, Enum.Material.Neon, if powered then rgb(255, 236, 200) else rgb(40, 40, 38), Enum.PartType.Ball))
	bulb.CastShadow = false
	for a = 0, 3 do
		ctx.decor(ctx.part(ctx.lights, "Cage", Vector3.new(0.07, 1.2, 0.07), at * CFrame.Angles(0, a * math.pi / 2, 0) * CFrame.new(0.5, 0, 0), Enum.Material.Metal, rgb(55, 55, 55), nil))
	end
	local light = Instance.new("PointLight")
	light.Range = 20
	light.Brightness = if powered then 0.8 else 1.3
	light.Color = ctx.night.lighting.LampColor
	light.Shadows = true
	light.Enabled = powered
	light.Parent = bulb
	bulb:SetAttribute("Buzz", ctx.random:NextNumber() < 0.4)
	bulb:SetAttribute("OnColor", rgb(255, 236, 200))
	ctx.addLamp(bulb, light, cell)
end

-- A barrel vault over a straight stretch of tunnel: brick laid round an arch from wall
-- to wall. base is the cell centre with X across the tunnel and Z along it.
local function vault(ctx: Ctx, base: CFrame, span: number, spring: number, crown: number, depth: number, thick: number, color: Color3, name: string)
	local a, b = span / 2, crown - spring
	local n = 10
	for i = 0, n - 1 do
		local t0, t1 = math.pi * i / n, math.pi * (i + 1) / n
		local x0, y0 = a * math.cos(t0), b * math.sin(t0)
		local x1, y1 = a * math.cos(t1), b * math.sin(t1)
		local dx, dy = x1 - x0, y1 - y0
		local tm = (t0 + t1) / 2
		-- push each plank outward by half its thickness so the inside face sits on the curve
		local nx, ny = b * math.cos(tm), a * math.sin(tm)
		local nl = math.sqrt(nx * nx + ny * ny)
		local cx = (x0 + x1) / 2 + nx / nl * thick / 2
		local cy = (y0 + y1) / 2 + ny / nl * thick / 2
		deco(ctx, name, Vector3.new(math.sqrt(dx * dx + dy * dy) + 0.15, thick, depth), base * CFrame.new(cx, spring + cy, 0) * CFrame.Angles(0, 0, math.atan2(dy, dx)), Enum.Material.Brick, ctx.vary(color, 0.04))
	end
end

-- A storm grate in the crown of the vault: the moon comes through it.
local function stormGrate(ctx: Ctx, base: CFrame, crown: number)
	local sky = deco(ctx, "GrateSky", Vector3.new(3, 0.1, 3), base * CFrame.new(0, crown - 0.02, 0), Enum.Material.Neon, rgb(120, 126, 136))
	sky.CastShadow = false
	for i = -2, 2 do
		deco(ctx, "GrateBar", Vector3.new(0.22, 0.25, 3.3), base * CFrame.new(i * 0.62, crown - 0.15, 0), Enum.Material.Metal, rgb(24, 24, 24)).CastShadow = false
	end
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Bottom
	spot.Angle = 50
	spot.Range = crown + 4
	spot.Brightness = 1.6
	spot.Color = rgb(200, 212, 230)
	spot.Shadows = true
	spot.Parent = sky
	local haze = deco(ctx, "LightShaft", Vector3.new(crown, 2.8, 2.8), base * CFrame.new(0, crown / 2, 0) * UP, Enum.Material.SmoothPlastic, rgb(200, 210, 225), Enum.PartType.Cylinder)
	haze.Transparency = 0.95
	haze.CastShadow = false
end

-- A culvert mouth in the end wall, a trickle still coming out of it.
local function culvert(ctx: Ctx, wall: CFrame)
	local at = wall * CFrame.new(0, 3.4, 0)
	local turn = CFrame.Angles(0, math.rad(90), 0)
	deco(ctx, "CulvertRing", Vector3.new(0.9, 5.8, 5.8), at * CFrame.new(0, 0, -0.3) * turn, Enum.Material.Concrete, rgb(96, 96, 92), Enum.PartType.Cylinder)
	deco(ctx, "CulvertMouth", Vector3.new(0.3, 4.8, 4.8), at * CFrame.new(0, 0, -0.62) * turn, Enum.Material.SmoothPlastic, rgb(4, 4, 4), Enum.PartType.Cylinder)
	local trickle = deco(ctx, "Trickle", Vector3.new(1.1, 1.1, 0.12), wall * CFrame.new(0, 0.55, -0.8), Enum.Material.Glass, rgb(70, 76, 78))
	trickle.Transparency = 0.45
	local pool = deco(ctx, "Pool", Vector3.new(5, 0.06, 3.5), wall * CFrame.new(0, 0.05, -2.2), Enum.Material.Glass, rgb(10, 12, 12))
	pool.Reflectance = 0.55
end

-- An iron ladder up to a manhole, a little grey light coming down it.
local function manhole(ctx: Ctx, wall: CFrame)
	local H = ctx.H
	local x = ctx.random:NextNumber(-2, 2)
	local iron = rgb(64, 60, 56)
	for _, sx in { -0.75, 0.75 } do
		deco(ctx, "LadderRail", Vector3.new(0.2, H, 0.2), wall * CFrame.new(x + sx, H / 2, -0.5), Enum.Material.CorrodedMetal, iron)
	end
	for y = 1, H - 0.5, 1.1 do
		deco(ctx, "LadderRung", Vector3.new(1.5, 0.14, 0.14), wall * CFrame.new(x, y, -0.5), Enum.Material.CorrodedMetal, iron)
	end
	local hole = deco(ctx, "Manhole", Vector3.new(0.12, 3.2, 3.2), wall * CFrame.new(x, H - 0.05, -1.3) * UP, Enum.Material.Neon, rgb(70, 74, 82), Enum.PartType.Cylinder)
	hole.CastShadow = false
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Left -- the cylinder is stood up: its Left face looks down
	spot.Angle = 45
	spot.Range = H + 2
	spot.Brightness = 0.9
	spot.Color = rgb(200, 212, 230)
	spot.Shadows = true
	spot.Parent = hole
end

-- A white depth board with the water line marked far above your head.
local function depthGauge(ctx: Ctx, wall: CFrame)
	local x = ctx.random:NextNumber(-3, 3)
	deco(ctx, "GaugeBoard", Vector3.new(1, 5.6, 0.1), wall * CFrame.new(x, 3.2, -0.42), Enum.Material.SmoothPlastic, rgb(206, 204, 196))
	for i = 1, 4 do
		local y = 0.6 + i * 1.25
		deco(ctx, "GaugeMark", Vector3.new(0.5, 0.12, 0.05), wall * CFrame.new(x - 0.2, y, -0.5), Enum.Material.SmoothPlastic, rgb(20, 20, 20))
		ctx.sign(wall * CFrame.new(x + 0.22, y + 0.3, -0.5), Vector2.new(0.45, 0.5), tostring(i), rgb(20, 20, 20), nil, false, Enum.Font.GothamBold)
	end
	deco(ctx, "Tideline", Vector3.new(ctx.C - ctx.T - 0.2, 0.35, 0.05), wall * CFrame.new(0, 8, -0.04), Enum.Material.Concrete, rgb(36, 36, 34))
end

-- The cistern: a forest of stone columns standing in black water, brick arches between
-- them, a plank walkway and a rowboat.
local function drainCistern(ctx: Ctx, block: { Cell })
	local random = ctx.random
	local c = Dressing.blockCenter(ctx, block)
	local H = ctx.ceiling
	local inner = ctx.C * 2 - ctx.T
	local water = deco(ctx, "DeepWater", Vector3.new(inner, 0.1, inner), CFrame.new(c + Vector3.new(0, 0.35, 0)), Enum.Material.Glass, rgb(8, 10, 10))
	water.Reflectance = 0.6
	water.CastShadow = false
	local stone = rgb(104, 102, 96)
	local g = ctx.C * 0.66
	for i = -1, 1 do
		for j = -1, 1 do
			local p = c + Vector3.new(i * g, 0, j * g)
			solid(ctx, "Column", Vector3.new(H - 2.2, 1.7, 1.7), CFrame.new(p + Vector3.new(0, 1 + (H - 2.2) / 2, 0)) * UP, Enum.Material.Concrete, ctx.vary(stone, 0.05), Enum.PartType.Cylinder)
			deco(ctx, "ColumnBase", Vector3.new(2.5, 1, 2.5), CFrame.new(p + Vector3.new(0, 0.5, 0)), Enum.Material.Concrete, stone)
			deco(ctx, "Capital", Vector3.new(2.7, 1.2, 2.7), CFrame.new(p + Vector3.new(0, H - 0.6, 0)), Enum.Material.Concrete, stone)
		end
	end
	for k = -1, 1 do
		for m = -1, 0 do
			local mid = (m + 0.5) * g
			deco(ctx, "Arch", Vector3.new(g - 1.6, 1.6, 1.3), CFrame.new(c + Vector3.new(mid, H - 0.8, k * g)), Enum.Material.Brick, rgb(80, 76, 70))
			deco(ctx, "Arch", Vector3.new(1.3, 1.6, g - 1.6), CFrame.new(c + Vector3.new(k * g, H - 0.8, mid)), Enum.Material.Brick, rgb(80, 76, 70))
		end
	end
	-- planks laid across the water between two rows of columns
	local wz = c.Z + g / 2
	deco(ctx, "Walkway", Vector3.new(inner - 2, 0.25, 2.2), CFrame.new(c.X, 0.55, wz), Enum.Material.Wood, rgb(60, 52, 44))
	for px = -2, 2 do
		deco(ctx, "WalkwayPost", Vector3.new(0.3, 1.2, 0.3), CFrame.new(c.X + px * 4.8, 0.3, wz + 1.15), Enum.Material.Wood, rgb(48, 42, 36))
	end
	-- a rowboat tied up in the corner, half full of water
	local boat = CFrame.new(c + Vector3.new(-g * 0.55, 0, -g * 0.5)) * CFrame.Angles(0, random:NextNumber(0.2, 0.6), 0)
	solid(ctx, "Boat", Vector3.new(3.2, 1, 7.4), boat * CFrame.new(0, 0.75, 0), Enum.Material.Wood, rgb(54, 46, 40))
	local inside = deco(ctx, "BoatWater", Vector3.new(2.6, 0.1, 6.6), boat * CFrame.new(0, 1.2, 0), Enum.Material.Glass, rgb(8, 10, 10))
	inside.Reflectance = 0.5
	deco(ctx, "BoatSeat", Vector3.new(2.7, 0.2, 0.9), boat * CFrame.new(0, 1.3, 0.8), Enum.Material.Wood, rgb(64, 54, 46))
	deco(ctx, "Oar", Vector3.new(0.18, 0.12, 6.4), boat * CFrame.new(0.9, 1.35, -0.2) * CFrame.Angles(0, 0.1, 0), Enum.Material.Wood, rgb(70, 60, 50))
end

Themes.drain = {
	wall = { material = Enum.Material.Brick, color = rgb(84, 80, 74) },
	hubWall = { material = Enum.Material.Concrete, color = rgb(98, 98, 96) },
	floor = { material = Enum.Material.Slate, color = rgb(46, 46, 46), reflect = 0.12 },
	hubFloor = function(_room: string): Style
		return { material = Enum.Material.DiamondPlate, color = rgb(82, 82, 82) }
	end,
	ceiling = { material = Enum.Material.Concrete, color = rgb(30, 30, 30) },
	hubCeiling = { material = Enum.Material.Concrete, color = rgb(40, 40, 40) },
	trim = { material = Enum.Material.CorrodedMetal, color = rgb(70, 68, 64) },
	tunnel = { material = Enum.Material.Concrete, color = rgb(98, 98, 96) },
	locker = { material = Enum.Material.CorrodedMetal, color = rgb(90, 86, 80) },
	columns = false,
	writings = {
		"SHH", "PETE?", "DON'T", "IIII IIII IIII", "IT LISTENS", "HERE", "DEEPER", "NO",
	},
	writingColor = rgb(200, 200, 196),
	writingFont = Enum.Font.PermanentMarker,
	writingGlow = false,
	exitStyle = "lift",
	lamp = function(ctx: Ctx, cell: Cell?, position: Vector3)
		local sides = if cell then ctx.wallSides(cell.x, cell.z) else {}
		if cell and #sides > 0 then
			wallCage(ctx, cell, ctx.sideFrame(cell.x, cell.z, randomSide(ctx, sides)), false)
		else
			cagedLamp(ctx, cell, position, false)
		end
	end,
	hubLamps = function(ctx: Ctx)
		for i, w in hubWalls(ctx) do
			if i % 3 == 1 then
				wallCage(ctx, nil, ctx.sideFrame(w.cell.x, w.cell.z, w.side), true)
			end
		end
	end,
	cell = function(ctx: Ctx, x: number, z: number, info: CellInfo)
		local random = ctx.random
		local C, H, T = ctx.C, ctx.H, ctx.T
		local center = ctx.cellCenter(x, z)
		wallBands(ctx, x, z, { band(0, 0.5, 0.35, Enum.Material.Concrete, rgb(70, 70, 68)) })
		local axis = Dressing.straightAxis(ctx, x, z)
		if axis and not info.room then
			local base = CFrame.new(center) * (if axis == "NS" then CFrame.new() else CFrame.Angles(0, math.rad(90), 0))
			local span = C - T
			local spring = 5.6
			vault(ctx, base, span, spring, H - 0.3, C + 0.05, 0.9, rgb(74, 70, 64), "Vault")
			for _, ez in { -1, 1 } do
				vault(ctx, base * CFrame.new(0, 0, ez * (C / 2 - 0.5)), span - 0.9, spring, H - 0.75, 1, 1.1, rgb(92, 88, 80), "Rib")
			end
			-- the channel down the middle, a walkway either side
			local ch = 3.2
			local walk = (span - ch) / 2
			local water = deco(ctx, "Water", Vector3.new(ch, 0.1, C), base * CFrame.new(0, 0.1, 0), Enum.Material.Glass, rgb(10, 12, 12))
			water.Reflectance = 0.55
			water.CastShadow = false
			for _, sx in { -1, 1 } do
				deco(ctx, "Walkway", Vector3.new(walk, 0.35, C), base * CFrame.new(sx * (ch / 2 + walk / 2), 0.175, 0), Enum.Material.Slate, rgb(62, 62, 60))
				deco(ctx, "Kerb", Vector3.new(0.45, 0.42, C), base * CFrame.new(sx * (ch / 2 + 0.22), 0.21, 0), Enum.Material.Concrete, rgb(96, 96, 92))
			end
			if not info.spot then
				-- one pipe, always along the same wall, so the runs line up
				local pipeSide = if axis == "NS" then "E" else "N"
				if Maze.getEdge(ctx.layout, x, z, pipeSide) == "wall" then
					local f = ctx.sideFrame(x, z, pipeSide)
					deco(ctx, "Pipe", Vector3.new(C - T, 0.9, 0.9), f * CFrame.new(0, 3.2, -0.65), Enum.Material.CorrodedMetal, rgb(70, 66, 62), Enum.PartType.Cylinder)
					for _, px in { -3.5, 3.5 } do
						deco(ctx, "PipeBracket", Vector3.new(0.3, 1.3, 0.7), f * CFrame.new(px, 3.2, -0.35), Enum.Material.Metal, rgb(50, 50, 50))
					end
				end
				if random:NextNumber() < 0.1 then
					stormGrate(ctx, base, H - 0.3)
				end
			end
		end
		if info.room or info.spot then
			return
		end
		if Maze.passableCount(ctx.layout, x, z) == 1 then
			local back = deadEndBack(ctx, x, z)
			if back and random:NextNumber() < 0.75 then
				local roll = random:NextNumber()
				if roll < 0.3 then
					culvert(ctx, back)
				elseif roll < 0.55 then
					manhole(ctx, back)
				elseif roll < 0.8 then
					depthGauge(ctx, back)
				else
					-- a chair standing in the water, facing the wall
					Dressing.chair(ctx, back * CFrame.new(0, 0, -2.2) * CFrame.Angles(0, math.pi, 0), rgb(56, 46, 40), false)
				end
			end
		end
	end,
	room = function(ctx: Ctx, block: { Cell })
		if roomIndex(ctx, block) == 1 then
			Dressing.pumpRoom(ctx, block)
		else
			drainCistern(ctx, block)
		end
	end,
	hub = function(ctx: Ctx)
		eachHubCell(ctx, function(x: number, z: number)
			wallBands(ctx, x, z, { band(0, 0.5, 0.35, Enum.Material.Concrete, rgb(70, 70, 68)) })
		end)
		pumpHall(ctx)
	end,
	extra = noop,
	spawns = hallSpawns,
}

---------------------------------------------------------------------------
-- NIGHT 4: THE ATRIUM (a museum after dark)

local GILT = rgb(120, 100, 62)
local BRASS = rgb(150, 132, 84)

local function galleryBands(ctx: Ctx): { Band }
	local H = ctx.H
	return {
		band(0, 0.9, 0.22, Enum.Material.Wood, rgb(22, 20, 19)),
		band(H - 3.2, 0.25, 0.16, Enum.Material.Wood, rgb(34, 30, 28)),
		band(H - 1.4, 0.5, 0.45, Enum.Material.Plaster, rgb(112, 112, 110)),
		band(H - 0.9, 0.9, 0.8, Enum.Material.Plaster, rgb(126, 126, 122)),
	}
end

-- A painting in a gilt frame. Someone sitting for a portrait with no face, a field at
-- dusk with somebody standing far off in it, or a canvas painted over in black.
local function painting(ctx: Ctx, wall: CFrame, x: number, y: number, w: number, h: number, field: boolean?)
	local random = ctx.random
	local at = wall * CFrame.new(x, y, 0)
	solid(ctx, "PaintingFrame", Vector3.new(w + 1, h + 1, 0.3), at * CFrame.new(0, 0, -0.15), Enum.Material.Wood, GILT)
	deco(ctx, "FrameLip", Vector3.new(w + 0.35, h + 0.35, 0.12), at * CFrame.new(0, 0, -0.36), Enum.Material.Wood, rgb(64, 52, 34))
	local z = -0.45
	local kind = if field then 0.6 else random:NextNumber()
	if kind < 0.45 then
		deco(ctx, "Canvas", Vector3.new(w, h, 0.04), at * CFrame.new(0, 0, z), Enum.Material.Fabric, ctx.vary(rgb(84, 80, 74), 0.1))
		Dressing.egg(deco(ctx, "Sitter", Vector3.new(w * 0.8, h * 0.4, 0.03), at * CFrame.new(0, -h * 0.33, z - 0.03), Enum.Material.Fabric, rgb(22, 21, 20)))
		Dressing.egg(deco(ctx, "SitterHead", Vector3.new(w * 0.3, h * 0.3, 0.03), at * CFrame.new(random:NextNumber(-0.05, 0.05) * w, h * 0.06, z - 0.03), Enum.Material.Fabric, rgb(22, 21, 20)))
	elseif kind < 0.8 then
		deco(ctx, "Canvas", Vector3.new(w, h, 0.04), at * CFrame.new(0, 0, z), Enum.Material.Fabric, rgb(96, 96, 94))
		deco(ctx, "Field", Vector3.new(w, h * 0.42, 0.03), at * CFrame.new(0, -h * 0.29, z - 0.03), Enum.Material.Fabric, rgb(30, 30, 30))
		deco(ctx, "Figure", Vector3.new(0.18, 0.55, 0.03), at * CFrame.new(random:NextNumber(-0.3, 0.3) * w, -h * 0.08 + 0.2, z - 0.04), Enum.Material.Fabric, rgb(18, 18, 18))
	else
		deco(ctx, "Canvas", Vector3.new(w, h, 0.04), at * CFrame.new(0, 0, z), Enum.Material.Fabric, rgb(18, 18, 18))
	end
	-- a brass plate underneath, with nothing on it
	deco(ctx, "Plaque", Vector3.new(1, 0.5, 0.05), wall * CFrame.new(x + w / 2 - 0.5, y - h / 2 - 1.2, -0.04), Enum.Material.Metal, BRASS)
end

-- A brass picture light over a frame (top: the frame's top edge).
local function pictureLight(ctx: Ctx, wall: CFrame, x: number, top: number, w: number)
	local width = math.max(2, w * 0.5)
	ctx.decor(ctx.part(ctx.lights, "PictureLight", Vector3.new(width, 0.25, 0.3), wall * CFrame.new(x, top + 0.9, -1.05), Enum.Material.Metal, BRASS, nil))
	ctx.decor(ctx.part(ctx.lights, "PictureLightArm", Vector3.new(0.15, 0.15, 1), wall * CFrame.new(x, top + 0.9, -0.5), Enum.Material.Metal, BRASS, nil))
	local bulb = ctx.decor(ctx.part(ctx.lights, "Bulb", Vector3.new(width - 0.3, 0.08, 0.15), wall * CFrame.new(x, top + 0.75, -1.05), Enum.Material.Neon, rgb(255, 232, 196), nil))
	bulb.CastShadow = false
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Bottom
	spot.Angle = 100
	spot.Range = 9
	spot.Brightness = 1.4
	spot.Color = rgb(255, 228, 190)
	spot.Shadows = false
	spot.Parent = bulb
	ctx.addLamp(bulb, spot, nil)
end

-- A skylight in a deep well in the ceiling: the only real light in the building.
local function skylight(ctx: Ctx, cell: Cell?, position: Vector3)
	local H = ctx.ceiling
	local s = math.min(ctx.C * 0.45, 7.5)
	for _, o in { { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } } do
		local size = if o[1] == 0 then Vector3.new(s + 1.2, 1.2, 0.6) else Vector3.new(0.6, 1.2, s + 1.2)
		ctx.decor(ctx.part(ctx.lights, "SkylightWell", size, CFrame.new(position.X + o[1] * (s / 2 + 0.3), H - 0.6, position.Z + o[2] * (s / 2 + 0.3)), Enum.Material.Plaster, rgb(70, 70, 72), nil)).CastShadow = false
	end
	local sky = ctx.decor(ctx.part(ctx.lights, "Skylight", Vector3.new(s, 0.2, s), CFrame.new(position.X, H - 0.1, position.Z), Enum.Material.Neon, rgb(92, 98, 112), nil))
	sky.CastShadow = false
	for _, size in { Vector3.new(s, 0.25, 0.25), Vector3.new(0.25, 0.25, s) } do
		-- (the bars sit right under the light: as shadow-casters they'd blot most of it out)
		ctx.decor(ctx.part(ctx.lights, "SkylightBar", size, CFrame.new(position.X, H - 0.3, position.Z), Enum.Material.Metal, rgb(34, 34, 36), nil)).CastShadow = false
	end
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Bottom
	spot.Angle = 70
	spot.Range = H + 16
	spot.Brightness = 3
	spot.Color = ctx.night.lighting.LampColor
	spot.Shadows = true
	spot.Parent = sky
	ctx.addLamp(sky, spot, cell)
	local haze = ctx.decor(ctx.part(ctx.lights, "LightShaft", Vector3.new(H - 0.4, s * 0.85, s * 0.85), CFrame.new(position.X, H / 2, position.Z) * UP, Enum.Material.SmoothPlastic, rgb(196, 206, 228), Enum.PartType.Cylinder))
	haze.Transparency = 0.92
	haze.CastShadow = false
end

local function galleryBench(ctx: Ctx, at: CFrame)
	local wood = rgb(44, 36, 30)
	solid(ctx, "Bench", Vector3.new(6, 0.7, 1.9), at * CFrame.new(0, 1.85, 0), Enum.Material.Fabric, rgb(30, 29, 29))
	deco(ctx, "BenchFrame", Vector3.new(6.2, 0.25, 2.1), at * CFrame.new(0, 1.4, 0), Enum.Material.Wood, wood)
	for _, sx in { -2.7, 2.7 } do
		for _, sz in { -0.75, 0.75 } do
			deco(ctx, "BenchLeg", Vector3.new(0.3, 1.3, 0.3), at * CFrame.new(sx, 0.65, sz), Enum.Material.Wood, wood)
		end
	end
end

-- Something on a plinth under a dust sheet. Closed for the winter.
local function sheetedStatue(ctx: Ctx, at: CFrame)
	solid(ctx, "Plinth", Vector3.new(3.2, 1.6, 3.2), at * CFrame.new(0, 0.8, 0), Enum.Material.Marble, rgb(170, 170, 166))
	Dressing.sheeted(ctx, at * CFrame.new(0, 1.6, 0), if ctx.random:NextNumber() < 0.6 then "person" else "tall")
end

-- Brass posts and a velvet rope, `dist` out from a wall (the frame looks into the room).
local function ropeLine(ctx: Ctx, wall: CFrame, width: number, dist: number)
	local n = 3
	local step = width / (n - 1)
	for i = 0, n - 1 do
		local x = -width / 2 + i * step
		local post = wall * CFrame.new(x, 0, -dist)
		solid(ctx, "Stanchion", Vector3.new(3.1, 0.25, 0.25), post * CFrame.new(0, 1.55, 0) * UP, Enum.Material.Metal, BRASS, Enum.PartType.Cylinder)
		deco(ctx, "StanchionFoot", Vector3.new(0.15, 1, 1), post * CFrame.new(0, 0.08, 0) * UP, Enum.Material.Metal, BRASS, Enum.PartType.Cylinder)
		if i < n - 1 then
			deco(ctx, "Rope", Vector3.new(step, 0.18, 0.18), wall * CFrame.new(x + step / 2, 2.6, -dist), Enum.Material.Fabric, rgb(90, 20, 24), Enum.PartType.Cylinder)
		end
	end
end

local function hangPainting(ctx: Ctx, wall: CFrame, big: boolean)
	local random = ctx.random
	local landscape = big or random:NextNumber() < 0.45
	local w = if big then 8.5 elseif landscape then random:NextNumber(6, 8) else random:NextNumber(3.6, 5)
	local h = if landscape then w * random:NextNumber(0.6, 0.72) else w * random:NextNumber(1.25, 1.4)
	local y = 7 + (h - 4.5) * 0.25
	painting(ctx, wall, 0, y, w, h, big)
	if big or random:NextNumber() < 0.45 then
		pictureLight(ctx, wall, 0, y + h / 2 + 0.5, w)
	end
end

-- The rotunda: a ring of columns round a covered figure, under a round skylight.
local function rotunda(ctx: Ctx, block: { Cell })
	local c = Dressing.blockCenter(ctx, block)
	local H = ctx.ceiling
	local marble = Enum.Material.Marble
	deco(ctx, "Inlay", Vector3.new(0.06, 20, 20), CFrame.new(c + Vector3.new(0, 0.04, 0)) * UP, marble, rgb(150, 150, 146), Enum.PartType.Cylinder)
	deco(ctx, "InlayRing", Vector3.new(0.05, 21, 21), CFrame.new(c + Vector3.new(0, 0.03, 0)) * UP, marble, rgb(40, 40, 40), Enum.PartType.Cylinder)
	for i = 0, 7 do
		local a = i * math.pi / 4
		local p = c + Vector3.new(math.cos(a) * 9.5, 0, math.sin(a) * 9.5)
		solid(ctx, "Column", Vector3.new(H - 2.2, 1.6, 1.6), CFrame.new(p + Vector3.new(0, 1 + (H - 2.2) / 2, 0)) * UP, marble, rgb(190, 190, 186), Enum.PartType.Cylinder)
		deco(ctx, "ColumnBase", Vector3.new(2.3, 1, 2.3), CFrame.new(p + Vector3.new(0, 0.5, 0)), marble, rgb(176, 176, 172))
		deco(ctx, "ColumnCap", Vector3.new(2.4, 1.2, 2.4), CFrame.new(p + Vector3.new(0, H - 0.6, 0)), marble, rgb(176, 176, 172))
	end
	solid(ctx, "RoundPlinth", Vector3.new(2.4, 5, 5), CFrame.new(c + Vector3.new(0, 1.2, 0)) * UP, marble, rgb(170, 170, 166), Enum.PartType.Cylinder)
	Dressing.sheeted(ctx, CFrame.new(c + Vector3.new(0, 2.4, 0)) * CFrame.Angles(0, ctx.random:NextNumber(0, 6.28), 0), "person")
	skylight(ctx, block[1], c)
end

-- The photographs: two freestanding walls of small framed photographs and a bench
-- between them.
local function photoHall(ctx: Ctx, block: { Cell })
	local random = ctx.random
	local c = Dressing.blockCenter(ctx, block)
	local base = CFrame.new(c) * CFrame.Angles(0, random:NextInteger(0, 1) * math.pi / 2, 0)
	for _, sz in { -4.5, 4.5 } do
		local panel = base * CFrame.new(0, 0, sz)
		solid(ctx, "DisplayWall", Vector3.new(11, 7.5, 0.6), panel * CFrame.new(0, 3.75, 0), Enum.Material.Plaster, rgb(150, 150, 146))
		deco(ctx, "DisplayFoot", Vector3.new(11.2, 0.4, 0.8), panel * CFrame.new(0, 0.2, 0), Enum.Material.Wood, rgb(22, 20, 19))
		for _, face in { -1, 1 } do
			for i = 0, 3 do
				local at = panel * CFrame.new(-3.9 + i * 2.6, 4.6, face * 0.33)
				deco(ctx, "PhotoFrame", Vector3.new(1.7, 2.1, 0.08), at, Enum.Material.SmoothPlastic, rgb(20, 20, 20))
				deco(ctx, "PhotoMat", Vector3.new(1.4, 1.8, 0.04), at * CFrame.new(0, 0, face * 0.05), Enum.Material.SmoothPlastic, rgb(210, 208, 200))
				deco(ctx, "Photo", Vector3.new(1, 1.25, 0.03), at * CFrame.new(0, 0.1, face * 0.08), Enum.Material.SmoothPlastic, ctx.vary(rgb(84, 84, 82), 0.4))
			end
		end
	end
	galleryBench(ctx, base)
end

Themes.gallery = {
	wall = { material = Enum.Material.Plaster, color = rgb(150, 150, 146) },
	hubWall = { material = Enum.Material.Plaster, color = rgb(160, 160, 156) },
	floor = { material = Enum.Material.WoodPlanks, color = rgb(96, 84, 72), reflect = 0.04 },
	hubFloor = function(_room: string): Style
		return { material = Enum.Material.Marble, color = rgb(176, 176, 172), reflect = 0.08 }
	end,
	ceiling = { material = Enum.Material.Plaster, color = rgb(54, 54, 56) },
	hubCeiling = { material = Enum.Material.Plaster, color = rgb(60, 60, 62) },
	trim = { material = Enum.Material.Marble, color = rgb(196, 196, 190) },
	tunnel = { material = Enum.Material.Marble, color = rgb(190, 190, 186) },
	locker = { material = Enum.Material.Wood, color = rgb(60, 48, 40) },
	columns = false,
	writings = {
		"DON'T BLINK", "WHICH ONE", "IT MOVED", "IIII IIII", "STILL", "LOOK", "NEVER STONE",
	},
	writingColor = rgb(200, 200, 196),
	writingFont = Enum.Font.PermanentMarker,
	writingGlow = false,
	exitStyle = "grand",
	lamp = skylight,
	hubLamps = function(ctx: Ctx)
		hubCellLamps(ctx, Themes.gallery)
	end,
	cell = function(ctx: Ctx, x: number, z: number, info: CellInfo)
		local random = ctx.random
		wallBands(ctx, x, z, galleryBands(ctx))
		if info.room then
			return
		end
		local backSide = if Maze.passableCount(ctx.layout, x, z) == 1 then deadEndSide(ctx, x, z) else nil
		for _, side in ctx.wallSides(x, z) do
			local f = ctx.sideFrame(x, z, side)
			if side == backSide then
				hangPainting(ctx, f, true)
			elseif random:NextNumber() < 0.6 then
				hangPainting(ctx, f, false)
			end
		end
		if info.spot then
			return
		end
		if backSide then
			-- the end of a gallery: one painting to sit and look at
			local back = ctx.sideFrame(x, z, backSide)
			if random:NextNumber() < 0.7 then
				ropeLine(ctx, back, 7, 2.4)
				galleryBench(ctx, back * CFrame.new(0, 0, -ctx.C * 0.58))
			end
			return
		end
		local center = ctx.cellCenter(x, z)
		local axis = Dressing.straightAxis(ctx, x, z)
		local roll = random:NextNumber()
		if roll < 0.14 then
			galleryBench(ctx, CFrame.new(center) * CFrame.Angles(0, if axis == "NS" then math.rad(90) else 0, 0))
		elseif roll < 0.25 then
			sheetedStatue(ctx, CFrame.new(center + Vector3.new(random:NextNumber(-2, 2), 0, random:NextNumber(-2, 2))) * CFrame.Angles(0, random:NextNumber(0, 6.28), 0))
		elseif roll < 0.31 then
			bust(ctx, CFrame.new(center + Vector3.new(random:NextNumber(-2, 2), 0, random:NextNumber(-2, 2))))
		end
	end,
	room = function(ctx: Ctx, block: { Cell })
		if roomIndex(ctx, block) % 2 == 1 then
			rotunda(ctx, block)
		else
			photoHall(ctx, block)
		end
	end,
	hub = function(ctx: Ctx)
		local O = ctx.hubOrigin
		local C = ctx.C
		eachHubCell(ctx, function(x: number, z: number)
			wallBands(ctx, x, z, galleryBands(ctx))
		end)
		-- the ticket desk, and a rope for the queue nobody's in
		solid(ctx, "Desk", Vector3.new(2.4, 3.6, 8), CFrame.new(O + Vector3.new(6, 1.8, C * 1.1)), Enum.Material.Wood, rgb(52, 42, 34))
		deco(ctx, "DeskTop", Vector3.new(2.8, 0.25, 8.4), CFrame.new(O + Vector3.new(6, 3.72, C * 1.1)), Enum.Material.Marble, rgb(180, 180, 176))
		ropeLine(ctx, CFrame.new(O + Vector3.new(11, 0, C * 1.1)) * CFrame.Angles(0, math.rad(-90), 0), 6, 0)
		-- the main stair, up to a door that's locked: the upper floor is closed
		local walls = hubWalls(ctx)
		for _, w in walls do
			if w.side == "N" and w.cell.x == ctx.layout.hub.x0 + math.floor(ctx.layout.hub.w / 2) then
				local f = ctx.sideFrame(w.cell.x, w.cell.z, w.side)
				for i = 0, 7 do
					solid(ctx, "Step", Vector3.new(10, (i + 1) * 0.75, 1.4), f * CFrame.new(0, (i + 1) * 0.375, -(0.7 + (7 - i) * 1.4)), Enum.Material.Marble, rgb(170, 170, 166))
				end
				Dressing.fakeDoor(ctx, f * CFrame.new(0, 6, 0), rgb(60, 48, 40))
				ropeLine(ctx, f, 10, 12)
				break
			end
		end
		local w2 = walls[math.min(3, #walls)]
		ctx.sign(ctx.sideFrame(w2.cell.x, w2.cell.z, w2.side) * CFrame.new(0, 9, -0.1), Vector2.new(10, 2), "THE COLLECTION IS CLOSED", rgb(200, 198, 190), nil, false, Enum.Font.Fondamento)
	end,
	extra = function(ctx: Ctx)
		decoyStatues(ctx, 8)
	end,
	spawns = hallSpawns,
}

---------------------------------------------------------------------------
-- NIGHT 5: THE VOID (the house, unmade)

local UNMADE_BANDS: { Band } = {
	band(0, 3.6, 0.14, Enum.Material.Wood, rgb(50, 42, 36)),
	band(3.55, 0.3, 0.26, Enum.Material.Wood, rgb(68, 56, 48)),
}

-- A bare bulb on a flex that runs up into the dark, attached to nothing.
local function danglingBulb(ctx: Ctx, cell: Cell?, position: Vector3, brightness: number)
	-- low enough that the light stays under the broken wall tops
	local y = ctx.random:NextNumber(7.4, 8.6)
	local top = y + 20
	ctx.decor(ctx.part(ctx.lights, "Flex", Vector3.new(0.08, top - y, 0.08), CFrame.new(position.X, (top + y) / 2, position.Z), Enum.Material.SmoothPlastic, rgb(16, 16, 16), nil))
	local bulb = Dressing.egg(ctx.decor(ctx.part(ctx.lights, "Bulb", Vector3.new(0.7, 0.9, 0.7), CFrame.new(position.X, y, position.Z), Enum.Material.Neon, rgb(240, 226, 200), nil)))
	bulb.CastShadow = false
	local light = Instance.new("PointLight")
	light.Range = 22
	light.Brightness = brightness
	light.Color = ctx.night.lighting.LampColor
	light.Shadows = true
	light.Parent = bulb
	bulb:SetAttribute("Buzz", ctx.random:NextNumber() < 0.3)
	ctx.addLamp(bulb, light, cell)
end

-- A door standing on its own in its frame, like the ones in the lobby. Light leaks out
-- from under it, from wherever it goes.
local function loneDoor(ctx: Ctx, at: CFrame)
	local dw, dh = 4.4, 8.6
	local frame = rgb(56, 46, 40)
	for _, sx in { -1, 1 } do
		solid(ctx, "DoorPost", Vector3.new(0.5, dh + 0.5, 0.8), at * CFrame.new(sx * (dw / 2 + 0.25), (dh + 0.5) / 2, 0), Enum.Material.Wood, frame)
	end
	solid(ctx, "DoorHead", Vector3.new(dw + 1, 0.5, 0.8), at * CFrame.new(0, dh + 0.25, 0), Enum.Material.Wood, frame)
	solid(ctx, "LoneDoor", Vector3.new(dw, dh - 0.15, 0.3), at * CFrame.new(0, dh / 2 + 0.1, 0), Enum.Material.Wood, rgb(80, 68, 58))
	for _, py in { 2.4, 6 } do
		deco(ctx, "DoorPanel", Vector3.new(dw - 1.2, 2.6, 0.08), at * CFrame.new(0, py, -0.19), Enum.Material.Wood, rgb(70, 60, 50))
	end
	deco(ctx, "Knob", Vector3.new(0.35, 0.35, 0.35), at * CFrame.new(dw / 2 - 0.5, dh * 0.45, -0.28), Enum.Material.Metal, rgb(160, 150, 120), Enum.PartType.Ball)
	local leak = deco(ctx, "LightLeak", Vector3.new(dw - 0.3, 0.06, 1.6), at * CFrame.new(0, 0.03, -0.9), Enum.Material.Neon, rgb(170, 160, 140))
	leak.Transparency = 0.35
	leak.CastShadow = false
	local glow = Instance.new("PointLight")
	glow.Range = 7
	glow.Brightness = 0.7
	glow.Color = rgb(255, 236, 210)
	glow.Shadows = false
	glow.Parent = leak
end

-- A room the house remembers from the other nights, under one bare bulb.
local function rememberedRoom(ctx: Ctx, block: { Cell }, which: number)
	local c = Dressing.blockCenter(ctx, block)
	local base = CFrame.new(c) * CFrame.Angles(0, ctx.random:NextInteger(0, 3) * math.pi / 2, 0)
	local wood = Enum.Material.Wood
	local dark = rgb(56, 46, 40)
	if which == 1 then
		-- the bed you woke up in on the first night, made, waiting for you
		solid(ctx, "BedFrame", Vector3.new(6, 1.6, 8), base * CFrame.new(0, 0.8, 0), wood, dark)
		solid(ctx, "Headboard", Vector3.new(6, 4.2, 0.5), base * CFrame.new(0, 2.1, -4.15), wood, dark)
		solid(ctx, "Mattress", Vector3.new(5.6, 0.9, 7.4), base * CFrame.new(0, 2.05, 0.2), Enum.Material.Fabric, rgb(196, 194, 188))
		deco(ctx, "Pillow", Vector3.new(3.6, 0.6, 1.5), base * CFrame.new(0, 2.8, -3), Enum.Material.Fabric, rgb(220, 218, 214))
		solid(ctx, "Nightstand", Vector3.new(2.2, 2.4, 2), base * CFrame.new(4.4, 1.2, -3.4), wood, dark)
		deco(ctx, "Rug", Vector3.new(10, 0.08, 8), base * CFrame.new(0, 0.04, 2), Enum.Material.Fabric, rgb(56, 56, 60))
	elseif which == 2 then
		-- an iron bed from the ward, someone in it, the curtain half round it
		wardBed(ctx, base * CFrame.new(0, -1.2, 0))
		Dressing.egg(deco(ctx, "Body", Vector3.new(2, 0.9, 5.4), base * CFrame.new(0, 2.15, 0.5), Enum.Material.Fabric, rgb(206, 206, 202)))
		local curtain = deco(ctx, "Curtain", Vector3.new(0.08, 8, 6.5), base * CFrame.new(2.6, 4.4, 0), Enum.Material.Fabric, rgb(190, 192, 188))
		curtain.Transparency = 0.2
		ivStand(ctx, base * CFrame.new(-2.6, 0, -2))
	else
		-- a plinth from the gallery with nothing on it any more
		solid(ctx, "Plinth", Vector3.new(3, 4, 3), base * CFrame.new(0, 2, 0), Enum.Material.Marble, rgb(170, 170, 166))
		ropeLine(ctx, base * CFrame.new(0, 0, -3.6), 6, 0)
		ctx.sign(base * CFrame.new(0, 2.6, -1.55), Vector2.new(2.4, 0.8), "IT LEFT", rgb(30, 30, 34), rgb(150, 150, 154), false, Enum.Font.Fondamento)
	end
	danglingBulb(ctx, block[1], c, 1.1)
end

Themes.unmade = {
	wall = { material = Enum.Material.Plaster, color = rgb(128, 124, 118) },
	hubWall = { material = Enum.Material.Plaster, color = rgb(150, 146, 138) },
	floor = { material = Enum.Material.WoodPlanks, color = rgb(64, 56, 50) },
	hubFloor = function(_room: string): Style
		return { material = Enum.Material.WoodPlanks, color = rgb(80, 68, 58) }
	end,
	ceiling = { material = Enum.Material.SmoothPlastic, color = rgb(0, 0, 0) },
	hubCeiling = { material = Enum.Material.SmoothPlastic, color = rgb(0, 0, 0) },
	trim = { material = Enum.Material.Wood, color = rgb(70, 58, 50) },
	tunnel = { material = Enum.Material.Plaster, color = rgb(128, 124, 118) },
	locker = { material = Enum.Material.Wood, color = rgb(70, 58, 50) },
	columns = false,
	-- the hall is still whole; everywhere else the walls stop, broken, short of the dark
	edgeHeight = function(ctx: Ctx, x: number, z: number, dir: string): number
		local layout = ctx.layout
		local nx, nz = x + Maze.DX[dir], z + Maze.DZ[dir]
		if (Maze.inBounds(layout, x, z) and Maze.isHub(layout, x, z)) or (Maze.inBounds(layout, nx, nz) and Maze.isHub(layout, nx, nz)) then
			return ctx.H
		end
		if ctx.random:NextNumber() < 0.4 then
			return ctx.H
		end
		return ctx.H * ctx.random:NextNumber(0.72, 0.94)
	end,
	writings = {
		"WAKE UP", "YOU CAME BACK", "WE ARE STILL HERE", "IIII IIII IIII IIII", "NO MORNING", "GREY", "ALL OF THEM",
	},
	writingColor = rgb(28, 22, 22),
	writingFont = Enum.Font.PermanentMarker,
	writingGlow = false,
	exitStyle = "portal",
	lamp = function(ctx: Ctx, cell: Cell?, position: Vector3)
		local sides = if cell then ctx.wallSides(cell.x, cell.z) else {}
		if cell and #sides > 0 and ctx.random:NextNumber() < 0.35 then
			sconce(ctx, cell, ctx.sideFrame(cell.x, cell.z, randomSide(ctx, sides)), ctx.night.lighting.LampColor)
		else
			danglingBulb(ctx, cell, position, ctx.random:NextNumber(0.9, 1.3))
		end
	end,
	hubLamps = function(ctx: Ctx)
		local hub = ctx.layout.hub
		for rz = 0, hub.d - 1, 2 do
			for rx = 0, hub.w - 1, 2 do
				danglingBulb(ctx, nil, ctx.cellCenter(hub.x0 + rx, hub.z0 + rz), 1.2)
			end
		end
	end,
	cell = function(ctx: Ctx, x: number, z: number, info: CellInfo)
		local random = ctx.random
		local C = ctx.C
		local center = ctx.cellCenter(x, z)
		wallBands(ctx, x, z, UNMADE_BANDS)
		-- floorboards gone, nothing but black underneath
		if random:NextNumber() < 0.22 then
			local alongX = random:NextNumber() < 0.5
			local start = random:NextNumber(-C * 0.3, C * 0.3)
			for k = 0, random:NextInteger(0, 2) do
				local len = random:NextNumber(3, C * 0.7)
				local off = start + k * 0.62
				local slide = random:NextNumber(-2, 2)
				local size = if alongX then Vector3.new(len, 0.03, 0.56) else Vector3.new(0.56, 0.03, len)
				local pos = if alongX then center + Vector3.new(slide, 0.02, off) else center + Vector3.new(off, 0.02, slide)
				local gap = deco(ctx, "MissingBoard", size, CFrame.new(pos), Enum.Material.SmoothPlastic, rgb(3, 3, 3))
				gap.CastShadow = false
			end
		end
		-- pieces of the house drifting overhead
		if random:NextNumber() < 0.12 then
			local p = center + Vector3.new(random:NextNumber(-4, 4), ctx.H + random:NextNumber(3, 16), random:NextNumber(-4, 4))
			local piece = deco(ctx, "WallFragment", Vector3.new(random:NextNumber(3, 6.5), random:NextNumber(2.5, 5), 1), CFrame.new(p) * CFrame.Angles(random:NextNumber(-0.5, 0.5), random:NextNumber(0, 6.28), random:NextNumber(-0.6, 0.6)), Enum.Material.Plaster, ctx.vary(rgb(128, 124, 118), 0.08))
			CollectionService:AddTag(piece, "Float")
		end
		if info.room or info.spot then
			return
		end
		if Maze.passableCount(ctx.layout, x, z) == 1 then
			local back = deadEndBack(ctx, x, z)
			if back and random:NextNumber() < 0.7 then
				local roll = random:NextNumber()
				if roll < 0.4 then
					loneDoor(ctx, back * CFrame.new(0, 0, -C * 0.4))
				elseif roll < 0.65 then
					Dressing.sheeted(ctx, back * CFrame.new(random:NextNumber(-2, 2), 0, -2.6) * CFrame.Angles(0, math.pi, 0), "person")
				elseif roll < 0.85 then
					Dressing.chair(ctx, back * CFrame.new(0, 0, -2) * CFrame.Angles(0, math.pi, 0), rgb(56, 46, 40), false)
					portrait(ctx, back * CFrame.new(0, 6.4, 0))
				else
					-- a chair hanging upside down over the dead end
					Dressing.chair(ctx, back * CFrame.new(0, ctx.H + 3, -C * 0.4) * CFrame.Angles(math.pi, random:NextNumber(0, 6.28), 0), rgb(56, 46, 40), false)
				end
			end
			return
		end
		local sides = ctx.wallSides(x, z)
		if #sides == 0 then
			return
		end
		local f = ctx.sideFrame(x, z, randomSide(ctx, sides))
		local roll = random:NextNumber()
		if roll < 0.07 then
			portrait(ctx, f * CFrame.new(random:NextNumber(-2.5, 2.5), 6.4, 0))
		elseif roll < 0.11 then
			Dressing.chair(ctx, f * CFrame.new(random:NextNumber(-3, 3), 0, -1.7) * CFrame.Angles(0, math.pi, 0), rgb(56, 46, 40), false)
		elseif roll < 0.14 then
			grandfatherClock(ctx, f)
		elseif roll < 0.17 then
			Dressing.mirror(ctx, f)
		end
	end,
	room = function(ctx: Ctx, block: { Cell })
		rememberedRoom(ctx, block, (roomIndex(ctx, block) - 1) % 3 + 1)
	end,
	hub = function(ctx: Ctx)
		local hub = ctx.layout.hub
		local O = ctx.hubOrigin
		local C = ctx.C
		eachHubCell(ctx, function(x: number, z: number)
			wallBands(ctx, x, z, UNMADE_BANDS)
			wallBands(ctx, x, z, { band(ctx.H - 0.45, 0.45, 0.3, Enum.Material.Plaster, rgb(150, 146, 140)) })
		end)
		-- the hall of the house, the way it was
		deco(ctx, "Runner", Vector3.new(4, 0.1, hub.d * C - 4), CFrame.new(O + Vector3.new(hub.w * C / 2, 0.06, hub.d * C / 2)), Enum.Material.Fabric, rgb(60, 58, 58))
		for i, w in hubWalls(ctx) do
			local f = ctx.sideFrame(w.cell.x, w.cell.z, w.side)
			if i == 2 then
				grandfatherClock(ctx, f)
			elseif i % 3 == 0 then
				portrait(ctx, f * CFrame.new(0, 6.6, 0))
			end
		end
	end,
	extra = noop,
	spawns = hallSpawns,
}

return Themes
