--!strict
-- The look of each night's map: materials, lamps, props, hub decor, wall writing.
--   house   grey concrete maze around a house                      (night 1)
--   ward    tiled hospital halls in red emergency light            (night 2)
--   sewer   flooded brick tunnels, no power                        (night 3)
--   atrium  a vast marble hall of columns, lamp posts and statues  (night 4)
--   void    black glass, glowing purple veins, floating rocks      (night 5)

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
	local function note(x: number, y: number, z: number, text: string)
		ctx.note(CFrame.new(O + Vector3.new(x, y + 0.025, z)) * CFrame.Angles(0, random:NextNumber(-0.4, 0.4), 0), text)
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
	note(7.7, 2.4, 25.9, "If you're reading this, you woke up here too.\nThe clock in the hall says midnight. It always says midnight.\nJust make it to 6 AM. Don't let it see you.")
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
	note(46.5, 3.2, 13, "The lockers saved me twice.\nThe third time it WATCHED me get in.\nIf it's chasing you, break line of sight first.")

	-- study
	box("Desk", Vector3.new(6, 3, 2.6), 42, 0, 34.2, wood, darkWood)
	box("DeskChair", Vector3.new(2, 2, 2), 42, 0, 31.6, wood, darkWood)
	box("Bookshelf", Vector3.new(2, 9, 8), 58.5, 0, 30, wood, darkWood)
	note(41.2, 3, 34.0, "Day 14.\nIt doesn't see well in the dark, but it HEARS everything.\nWalk. Crouch. Only run when it's already running at you.\nIt likes the light. Turn yours off when it's close.")
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
		"IT SEES YOU", "DON'T RUN", "MAKE IT TO SIX", "HIDE", "IT HEARS YOUR FEET", "WHERE DID THE COLOR GO",
		"I WOKE UP HERE TOO", "TURN OFF YOUR LIGHT", "LISTEN FOR THE CLICKING", "NOT ALONE", "DON'T LOOK BEHIND YOU",
		"WAKE UP WAKE UP WAKE UP", "IT KNOWS THE LOCKERS", "STAY QUIET", "THE CLOCK IS WRONG", "THE HOUSE DOESN'T END",
		"THAT ISN'T A SHEET",
	},
	writingColor = rgb(28, 22, 22),
	writingFont = Enum.Font.Creepster,
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
-- NIGHT 2: THE RED WARD

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

local function wardLamp(ctx: Ctx, cell: Cell?, position: Vector3)
	local random = ctx.random
	local H = ctx.ceiling
	local broken = random:NextNumber() < 0.18
	ctx.decor(ctx.part(ctx.lights, "Fixture", Vector3.new(4.2, 0.25, 1.8), CFrame.new(position.X, H - 0.12, position.Z), Enum.Material.Metal, rgb(160, 160, 160), nil))
	local bulb = ctx.decor(ctx.part(ctx.lights, "Bulb", Vector3.new(3.8, 0.15, 1.3), CFrame.new(position.X, H - 0.3, position.Z), Enum.Material.Neon, if broken then rgb(240, 240, 230) else rgb(255, 80, 70), nil))
	bulb.CastShadow = false
	local light = Instance.new("PointLight")
	light.Range = 20
	light.Brightness = if broken then 0.9 else random:NextNumber(1.5, 2.1)
	light.Color = if broken then rgb(255, 250, 240) else ctx.night.lighting.LampColor
	light.Shadows = true
	light.Parent = bulb
	bulb:SetAttribute("Buzz", broken)
	ctx.addLamp(bulb, light, cell)
	-- spinning red alarm beacons
	if random:NextNumber() < 0.2 then
		local beacon = ctx.decor(ctx.part(ctx.lights, "Beacon", Vector3.new(0.9, 0.7, 0.9), CFrame.new(position.X + 2.8, H - 0.5, position.Z), Enum.Material.Neon, rgb(255, 30, 20), nil))
		beacon.CastShadow = false
		local spot = Instance.new("SpotLight")
		spot.Face = Enum.NormalId.Front
		spot.Angle = 40
		spot.Range = 34
		spot.Brightness = 3
		spot.Color = rgb(255, 20, 10)
		spot.Parent = beacon
		CollectionService:AddTag(beacon, "Beacon")
	end
end

Themes.ward = {
	wall = { material = Enum.Material.CeramicTiles, color = rgb(206, 204, 198) },
	hubWall = { material = Enum.Material.Plaster, color = rgb(196, 190, 184) },
	floor = { material = Enum.Material.Marble, color = rgb(165, 162, 158), reflect = 0.08 },
	hubFloor = function(_room: string): Style
		return { material = Enum.Material.CeramicTiles, color = rgb(150, 148, 144) }
	end,
	ceiling = { material = Enum.Material.Plaster, color = rgb(175, 172, 168) },
	hubCeiling = { material = Enum.Material.Plaster, color = rgb(175, 172, 168) },
	trim = { material = Enum.Material.Metal, color = rgb(150, 150, 150) },
	tunnel = { material = Enum.Material.CeramicTiles, color = rgb(206, 204, 198) },
	locker = { material = Enum.Material.Metal, color = rgb(176, 186, 192) },
	columns = false,
	writings = {
		"STAY IN YOUR BED", "VISITING HOURS ARE OVER", "IT CRAWLS", "LOOK DOWN", "NURSE?", "ROOM 13 IS EMPTY NOW",
		"THE PATIENTS LEFT", "DON'T RUN IN THE HALLS", "IT WAS ON ALL FOURS", "WE'RE NOT SICK", "IT'S UNDER THE BEDS",
		"NO ONE IS COMING", "ITS FACE IS UPSIDE DOWN",
	},
	writingColor = rgb(110, 8, 8),
	writingFont = Enum.Font.Creepster,
	writingGlow = false,
	exitStyle = "double",
	lamp = wardLamp,
	hubLamps = function(ctx: Ctx)
		hubCellLamps(ctx, Themes.ward)
	end,
	cell = function(ctx: Ctx, x: number, z: number, info: CellInfo)
		if info.room then
			return
		end
		local random = ctx.random
		local C, T, H = ctx.C, ctx.T, ctx.H
		local center = ctx.cellCenter(x, z)
		local sides = ctx.wallSides(x, z)
		-- a guide line on the floor down the middle of straight corridors
		local axis = Dressing.straightAxis(ctx, x, z)
		if axis then
			local size = if axis == "NS" then Vector3.new(0.4, 0.04, C) else Vector3.new(C, 0.04, 0.4)
			deco(ctx, "GuideLine", size, CFrame.new(center + Vector3.new(0, 0.03, 0)), Enum.Material.SmoothPlastic, rgb(200, 170, 50))
		end
		for _, side in sides do
			local f = ctx.sideFrame(x, z, side)
			if random:NextNumber() < 0.45 then
				deco(ctx, "Handrail", Vector3.new(C - T - 1.5, 0.25, 0.25), f * CFrame.new(0, 3.2, -0.35), Enum.Material.Wood, rgb(150, 120, 90), Enum.PartType.Cylinder)
			end
			deco(ctx, "Kickplate", Vector3.new(C - T - 0.1, 0.8, 0.12), f * CFrame.new(0, 0.4, -0.06), Enum.Material.Metal, rgb(140, 140, 140))
			if random:NextNumber() < 0.07 then
				-- red emergency strip at floor level
				local strip = deco(ctx, "EmergencyStrip", Vector3.new(C - T - 2, 0.12, 0.08), f * CFrame.new(0, 0.95, -0.14), Enum.Material.Neon, rgb(170, 18, 12))
				strip.CastShadow = false
			end
		end
		-- papers everywhere
		if random:NextNumber() < 0.35 then
			for _ = 1, random:NextInteger(2, 5) do
				deco(ctx, "Paper", Vector3.new(0.9, 0.02, 1.2), CFrame.new(center + Vector3.new(random:NextNumber(-4, 4), 0.05, random:NextNumber(-4, 4))) * CFrame.Angles(0, random:NextNumber(0, 6.28), 0), Enum.Material.SmoothPlastic, rgb(216, 214, 204))
			end
		end
		-- a ceiling panel hanging down, wires dangling
		if not info.spot and random:NextNumber() < 0.07 then
			local hang = CFrame.new(center + Vector3.new(random:NextNumber(-2, 2), H - 0.1, random:NextNumber(-2, 2))) * CFrame.Angles(0, random:NextNumber(0, 6.28), 0)
			deco(ctx, "CeilingHole", Vector3.new(4, 0.05, 4), hang * CFrame.new(0, -0.02, 0), Enum.Material.SmoothPlastic, rgb(5, 5, 5))
			deco(ctx, "FallenPanel", Vector3.new(4, 0.15, 4), hang * CFrame.new(0, 0, -2) * CFrame.Angles(math.rad(-55), 0, 0) * CFrame.new(0, 0, -2), Enum.Material.Plaster, rgb(170, 168, 162))
			for _ = 1, 3 do
				local len = random:NextNumber(2.5, 5.5)
				deco(ctx, "Wire", Vector3.new(0.08, len, 0.08), hang * CFrame.new(random:NextNumber(-1.5, 1.5), -len / 2, random:NextNumber(-1.5, 1.5)) * CFrame.Angles(random:NextNumber(-0.2, 0.2), 0, random:NextNumber(-0.2, 0.2)), Enum.Material.SmoothPlastic, rgb(20, 20, 20))
			end
		end
		if #sides == 0 or info.spot then
			return
		end
		local f = ctx.sideFrame(x, z, randomSide(ctx, sides))
		local roll = random:NextNumber()
		if roll < 0.13 then
			-- a gurney left against the wall
			wardBed(ctx, f * CFrame.new(random:NextNumber(-1, 1), -1.2, -2.2) * CFrame.Angles(0, math.rad(90), 0))
		elseif roll < 0.23 then
			-- wheelchair
			local base = f * CFrame.new(random:NextNumber(-3, 3), 0, -2.4) * CFrame.Angles(0, random:NextNumber(-1, 1), 0)
			solid(ctx, "Seat", Vector3.new(2, 0.3, 2), base * CFrame.new(0, 1.8, 0), Enum.Material.Fabric, rgb(40, 40, 44))
			solid(ctx, "Back", Vector3.new(2, 2, 0.3), base * CFrame.new(0, 2.9, 1), Enum.Material.Fabric, rgb(40, 40, 44))
			for _, sx in { -1.15, 1.15 } do
				deco(ctx, "Wheel", Vector3.new(0.15, 2.4, 2.4), base * CFrame.new(sx, 1.2, 0.3), Enum.Material.Metal, rgb(90, 90, 90), Enum.PartType.Cylinder)
			end
		elseif roll < 0.32 then
			-- IV stand
			local base = f * CFrame.new(random:NextNumber(-3, 3), 0, -1.5)
			deco(ctx, "Pole", Vector3.new(7, 0.15, 0.15), base * CFrame.new(0, 3.5, 0) * UP, Enum.Material.Metal, rgb(180, 180, 180), Enum.PartType.Cylinder)
			deco(ctx, "Bag", Vector3.new(0.7, 1.1, 0.25), base * CFrame.new(0.35, 6.2, 0), Enum.Material.Glass, rgb(220, 225, 220)).Transparency = 0.4
			for a = 0, 2 do
				deco(ctx, "Foot", Vector3.new(1.4, 0.12, 0.15), base * CFrame.Angles(0, a * 2.09, 0) * CFrame.new(0.6, 0.1, 0), Enum.Material.Metal, rgb(150, 150, 150))
			end
		elseif roll < 0.4 then
			solid(ctx, "MedCart", Vector3.new(3, 3.2, 1.8), f * CFrame.new(random:NextNumber(-3, 3), 1.6, -1.1), Enum.Material.Metal, rgb(170, 175, 180))
		elseif roll < 0.5 then
			ctx.sign(f * CFrame.new(random:NextNumber(-2, 2), 7.6, -0.08), Vector2.new(4, 1), WARD_SIGNS[random:NextInteger(1, #WARD_SIGNS)], rgb(20, 20, 20), rgb(225, 225, 220), false, Enum.Font.GothamBold)
		elseif roll < 0.56 then
			Dressing.chair(ctx, f * CFrame.new(random:NextNumber(-3, 3), 0, -2.5) * CFrame.Angles(0, random:NextNumber(0, 6.28), 0), rgb(70, 90, 110), true)
		end
	end,
	room = function(ctx: Ctx, block: { Cell })
		local i = roomIndex(ctx, block)
		if i == 1 then
			Dressing.operatingRoom(ctx, block, block[1])
			return
		elseif i == 2 then
			Dressing.morgue(ctx, block)
			return
		end
		local random = ctx.random
		for _, c in block do
			local sides = ctx.wallSides(c.x, c.z)
			if #sides > 0 then
				local f = ctx.sideFrame(c.x, c.z, sides[random:NextInteger(1, #sides)])
				local bed = f * CFrame.new(random:NextNumber(-1.5, 1.5), 0, -3.8) * CFrame.Angles(0, math.rad(180), 0)
				wardBed(ctx, bed * CFrame.new(0, -1.2, 0))
				-- privacy curtain beside the bed
				local curtain = deco(ctx, "Curtain", Vector3.new(0.1, 7.5, 5.5), bed * CFrame.new(2.6, 4.5, 0), Enum.Material.Fabric, rgb(170, 195, 190))
				curtain.Transparency = 0.25
				-- heart monitor flatlining (the only green in the ward)
				local monitor = solid(ctx, "Monitor", Vector3.new(1.4, 1.1, 0.8), bed * CFrame.new(-2.4, 4.2, -3), Enum.Material.SmoothPlastic, rgb(30, 30, 32))
				ctx.sign(monitor.CFrame * CFrame.new(0, 0, 0.41) * CFrame.Angles(0, math.rad(180), 0), Vector2.new(1.2, 0.8), "_____", rgb(60, 255, 120), rgb(5, 20, 10), true, Enum.Font.Code)
				solid(ctx, "MonitorStand", Vector3.new(0.6, 3.6, 0.6), bed * CFrame.new(-2.4, 1.8, -3), Enum.Material.Metal, rgb(120, 120, 120))
			end
		end
	end,
	hub = function(ctx: Ctx)
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
		local notes = {
			"PATIENT FILE #13\nFound on all fours under bed 4. Moves very fast, very low.\nWhen it gets close it LUNGES.\nIt loses interest fast. Break line of sight.",
			"Night shift: the 4 ward keys are gone again. Each one has a tag with a digit.\nThe exit keypad wants all four.\nThe main doors are chained shut until then.",
		}
		local walls = hubWalls(ctx)
		for i, text in notes do
			local w = walls[(i * 3) % #walls + 1]
			ctx.note(ctx.sideFrame(w.cell.x, w.cell.z, w.side) * CFrame.new(0, 3.4, -1.2), text)
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
	end,
	extra = function(ctx: Ctx)
		-- plastic strip curtains hanging across some of the corridors: you see shapes through them
		local rooms: { [string]: boolean } = {}
		for _, block in ctx.layout.roomBlocks do
			for _, c in block do
				rooms[Maze.key(c.x, c.z)] = true
			end
		end
		local C, H = ctx.C, ctx.H
		for _, e in Dressing.openEdges(ctx, rooms) do
			if ctx.random:NextNumber() < 0.1 then
				local frame = ctx.edgeFrame(e.x, e.z, e.dir)
				deco(ctx, "CurtainRail", Vector3.new(C - 1, 0.3, 0.3), frame * CFrame.new(0, H - 1.2, 0), Enum.Material.Metal, rgb(150, 150, 150))
				local n = 12
				for i = 0, n - 1 do
					local strip = deco(ctx, "PlasticStrip", Vector3.new((C - 1) / n + 0.15, H - 1.6, 0.05), frame * CFrame.new(-(C - 1) / 2 + (i + 0.5) * (C - 1) / n, (H - 1.6) / 2 + 0.2, (i % 2) * 0.06) * CFrame.Angles(0, 0, ctx.random:NextNumber(-0.03, 0.03)), Enum.Material.Glass, rgb(210, 225, 220))
					strip.Transparency = 0.55
					strip.CastShadow = false
				end
			end
		end
	end,
	spawns = hallSpawns,
}

---------------------------------------------------------------------------
-- NIGHT 3: THE DROWNED TUNNELS

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

Themes.sewer = {
	wall = { material = Enum.Material.Brick, color = rgb(72, 74, 68) },
	hubWall = { material = Enum.Material.Concrete, color = rgb(96, 98, 94) },
	floor = { material = Enum.Material.Concrete, color = rgb(52, 56, 54) },
	hubFloor = function(_room: string): Style
		return { material = Enum.Material.DiamondPlate, color = rgb(80, 82, 80) }
	end,
	ceiling = { material = Enum.Material.Concrete, color = rgb(38, 40, 38) },
	hubCeiling = { material = Enum.Material.Concrete, color = rgb(46, 48, 46) },
	trim = { material = Enum.Material.CorrodedMetal, color = rgb(90, 80, 70) },
	tunnel = { material = Enum.Material.Concrete, color = rgb(96, 98, 94) },
	locker = { material = Enum.Material.CorrodedMetal, color = rgb(92, 80, 70) },
	columns = false,
	writings = {
		"IT'S BLIND", "DON'T SPLASH", "THE NOISE BRINGS IT", "HOLD YOUR BREATH", "IT HEARD ME BREATHE", "CROUCH",
		"PETE?", "THREE GENERATORS", "IT CLICKS WHEN IT LISTENS", "NO LIGHT DOWN HERE", "THE LIFT STILL WORKS",
	},
	writingColor = rgb(190, 196, 186),
	writingFont = Enum.Font.Creepster,
	writingGlow = false,
	exitStyle = "lift",
	lamp = function(ctx: Ctx, cell: Cell?, position: Vector3)
		cagedLamp(ctx, cell, position, false)
	end,
	hubLamps = function(ctx: Ctx)
		local hub = ctx.layout.hub
		for rx = 0, hub.w - 1, 2 do
			cagedLamp(ctx, nil, ctx.cellCenter(hub.x0 + rx, hub.z0), true)
		end
	end,
	cell = function(ctx: Ctx, x: number, z: number, info: CellInfo)
		local random = ctx.random
		local C, H, T = ctx.C, ctx.H, ctx.T
		local center = ctx.cellCenter(x, z)
		-- ankle-deep water everywhere
		local water = deco(ctx, "Water", Vector3.new(C, 0.25, C), CFrame.new(center + Vector3.new(0, 0.12, 0)), Enum.Material.Glass, if info.room then rgb(16, 32, 28) else rgb(30, 52, 46))
		water.Transparency = 0.35
		water.Reflectance = 0.3
		water.CastShadow = false
		local sides = ctx.wallSides(x, z)
		local axis = Dressing.straightAxis(ctx, x, z)
		if axis and not info.room then
			-- a deeper channel down the middle, with kerbs, and brick ribs across the roof
			local along = if axis == "NS" then CFrame.new() else CFrame.Angles(0, math.rad(90), 0)
			local base = CFrame.new(center) * along
			local channel = deco(ctx, "Channel", Vector3.new(3.4, 0.06, C), base * CFrame.new(0, 0.28, 0), Enum.Material.Glass, rgb(8, 18, 16))
			channel.Reflectance = 0.5
			channel.CastShadow = false
			for _, sx in { -1, 1 } do
				deco(ctx, "Kerb", Vector3.new(0.5, 0.45, C), base * CFrame.new(sx * 1.95, 0.22, 0), Enum.Material.Concrete, rgb(70, 74, 70))
			end
			deco(ctx, "Rib", Vector3.new(C - T, 1.1, 1.3), base * CFrame.new(0, H - 0.55, 0), Enum.Material.Brick, rgb(78, 70, 62))
			for _, sx in { -1, 1 } do
				deco(ctx, "RibFoot", Vector3.new(0.9, H - 1.1, 1.3), base * CFrame.new(sx * (C - T) / 2, (H - 1.1) / 2, 0), Enum.Material.Brick, rgb(78, 70, 62))
			end
		end
		-- glowing algae: the only light you'll get before the power's back
		if not info.room and #sides > 0 and random:NextNumber() < 0.14 then
			local f = ctx.sideFrame(x, z, sides[random:NextInteger(1, #sides)])
			local anchor: BasePart? = nil
			for i = 1, random:NextInteger(3, 6) do
				local s = random:NextNumber(0.5, 1.4)
				local patch = Dressing.egg(deco(ctx, "Algae", Vector3.new(s, s * random:NextNumber(0.5, 1), 0.12), f * CFrame.new(random:NextNumber(-3.5, 3.5), random:NextNumber(0.6, 3.5), -0.05), Enum.Material.Neon, rgb(30, 105, 85)))
				patch.CastShadow = false
				if i == 1 then
					anchor = patch
				end
			end
			if anchor then
				local glow = Instance.new("PointLight")
				glow.Range = 13
				glow.Brightness = 0.6
				glow.Color = rgb(90, 255, 200)
				glow.Shadows = false
				glow.Parent = anchor
				CollectionService:AddTag(anchor, "Algae")
			end
		end
		if #sides > 0 and not info.spot and random:NextNumber() < 0.05 then
			Dressing.ladder(ctx, ctx.sideFrame(x, z, sides[random:NextInteger(1, #sides)]), H, rgb(100, 70, 50))
		end
		if random:NextNumber() < 0.09 then
			for _ = 1, random:NextInteger(1, 3) do
				Dressing.rat(ctx, CFrame.new(center + Vector3.new(random:NextNumber(-4.5, 4.5), 0.25, random:NextNumber(-4.5, 4.5))) * CFrame.Angles(0, random:NextNumber(0, 6.28), 0))
			end
		end
		if #sides > 0 and random:NextNumber() < 0.55 then
			local f = ctx.sideFrame(x, z, sides[random:NextInteger(1, #sides)])
			deco(ctx, "Pipe", Vector3.new(C - T, 1.4, 1.4), f * CFrame.new(0, H - 1.6, -0.9), Enum.Material.CorrodedMetal, ctx.vary(rgb(90, 70, 55), 0.2), Enum.PartType.Cylinder)
			if random:NextNumber() < 0.4 then
				local low = f * CFrame.new(0, 2.6, -0.5)
				deco(ctx, "Pipe", Vector3.new(C - T, 0.6, 0.6), low, Enum.Material.Metal, ctx.vary(rgb(80, 84, 80), 0.2), Enum.PartType.Cylinder)
				deco(ctx, "Valve", Vector3.new(0.15, 1.4, 1.4), low * CFrame.new(random:NextNumber(-2, 2), 0, -0.5) * CFrame.Angles(0, math.rad(90), 0), Enum.Material.Metal, rgb(130, 30, 25), Enum.PartType.Cylinder)
			end
		end
		if random:NextNumber() < 0.25 then
			local along = if random:NextNumber() < 0.5 then CFrame.new() else CFrame.Angles(0, math.rad(90), 0)
			deco(ctx, "CeilingPipe", Vector3.new(C, 1, 1), CFrame.new(center + Vector3.new(random:NextNumber(-3, 3), H - 0.8, 0)) * along, Enum.Material.CorrodedMetal, ctx.vary(rgb(80, 66, 52), 0.2), Enum.PartType.Cylinder)
		end
		if #sides > 0 and random:NextNumber() < 0.12 then
			local f = ctx.sideFrame(x, z, sides[1])
			deco(ctx, "GrateHole", Vector3.new(3, 2, 0.1), f * CFrame.new(1, 1.4, -0.06), Enum.Material.SmoothPlastic, rgb(5, 5, 5))
			for i = 0, 5 do
				deco(ctx, "GrateBar", Vector3.new(0.12, 2.1, 0.15), f * CFrame.new(-0.25 + i * 0.5, 1.4, -0.12), Enum.Material.Metal, rgb(70, 70, 70))
			end
		end
		if not info.spot and random:NextNumber() < 0.08 then
			solid(ctx, "Drum", Vector3.new(3.4, 2.2, 2.2), CFrame.new(center + Vector3.new(random:NextNumber(-3.5, 3.5), 1.7, random:NextNumber(-3.5, 3.5))) * UP, Enum.Material.CorrodedMetal, ctx.vary(rgb(110, 60, 40), 0.25), Enum.PartType.Cylinder)
		end
		if random:NextNumber() < 0.08 then
			local top = center + Vector3.new(random:NextNumber(-3, 3), H, random:NextNumber(-3, 3))
			for i = 1, 10 do
				deco(ctx, "Chain", Vector3.new(0.25, 0.45, 0.12), CFrame.new(top - Vector3.new(0, i * 0.42, 0)) * CFrame.Angles(0, (i % 2) * math.rad(90), 0), Enum.Material.Metal, rgb(90, 90, 90))
			end
		end
		if random:NextNumber() < 0.15 then
			local drip = deco(ctx, "Drip", Vector3.new(0.2, 0.2, 0.2), CFrame.new(center + Vector3.new(random:NextNumber(-4, 4), H - 0.2, random:NextNumber(-4, 4))), Enum.Material.SmoothPlastic, rgb(0, 0, 0))
			drip.Transparency = 1
			CollectionService:AddTag(drip, "Drip")
		end
	end,
	room = function(ctx: Ctx, block: { Cell })
		if roomIndex(ctx, block) == 1 then
			Dressing.pumpRoom(ctx, block)
		else
			Dressing.cistern(ctx, block)
		end
		-- an outflow pipe pouring into the flooded chamber
		local c = block[1]
		local sides = ctx.wallSides(c.x, c.z)
		if #sides > 0 then
			local f = ctx.sideFrame(c.x, c.z, sides[1])
			deco(ctx, "Outflow", Vector3.new(3, 4, 4), f * CFrame.new(0, 6, -1) * CFrame.Angles(0, math.rad(90), 0), Enum.Material.CorrodedMetal, rgb(80, 66, 52), Enum.PartType.Cylinder)
			local fall = deco(ctx, "Waterfall", Vector3.new(2.6, 5, 0.6), f * CFrame.new(0, 2.5, -2.2), Enum.Material.Glass, rgb(60, 90, 80))
			fall.Transparency = 0.5
			fall.CastShadow = false
		end
	end,
	hub = function(ctx: Ctx)
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
		ctx.note(ctx.sideFrame(w.cell.x, w.cell.z, w.side) * CFrame.new(0, 3.4, -1.2), "Maintenance log, day ?\nPower's out in the whole system. Three backup generators, one at the end of each far tunnel.\nThe service lift won't move without all three.\nWhatever lives down here is BLIND. I watched it walk right past Pete while he held his breath.\nThen Pete sneezed.")
		local e = ctx.layout.exitCell
		ctx.sign(ctx.sideFrame(e.x, e.z, "S") * CFrame.new(0, ctx.exitHeight + 1, -0.15), Vector2.new(5, 1.1), "SERVICE LIFT", rgb(255, 210, 60), rgb(25, 25, 20), true, Enum.Font.GothamBlack)
	end,
	extra = noop,
	spawns = hallSpawns,
}

---------------------------------------------------------------------------
-- NIGHT 4: THE ATRIUM

local function lampPost(ctx: Ctx, cell: Cell?, position: Vector3)
	local C = ctx.C
	local p = position + Vector3.new(C * 0.28, 0, C * 0.28)
	solid(ctx, "PostBase", Vector3.new(1.6, 1, 1.6), CFrame.new(p + Vector3.new(0, 0.5, 0)), Enum.Material.Marble, rgb(200, 200, 196))
	solid(ctx, "Post", Vector3.new(13, 0.5, 0.5), CFrame.new(p + Vector3.new(0, 7, 0)) * UP, Enum.Material.Metal, rgb(40, 42, 46), Enum.PartType.Cylinder)
	local bulb = ctx.decor(ctx.part(ctx.lights, "Bulb", Vector3.new(1.8, 1.8, 1.8), CFrame.new(p + Vector3.new(0, 14, 0)), Enum.Material.Neon, rgb(225, 235, 255), Enum.PartType.Ball))
	bulb.CastShadow = false
	local light = Instance.new("PointLight")
	light.Range = 48
	light.Brightness = ctx.random:NextNumber(1, 1.4)
	light.Color = ctx.night.lighting.LampColor
	light.Shadows = true
	light.Parent = bulb
	ctx.addLamp(bulb, light, cell)
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

Themes.atrium = {
	wall = { material = Enum.Material.Marble, color = rgb(218, 218, 214) },
	hubWall = { material = Enum.Material.Marble, color = rgb(205, 205, 200) },
	floor = { material = Enum.Material.Marble, color = rgb(228, 228, 224), reflect = 0.12 },
	hubFloor = function(_room: string): Style
		return { material = Enum.Material.Marble, color = rgb(200, 196, 188), reflect = 0.1 }
	end,
	ceiling = { material = Enum.Material.Slate, color = rgb(36, 38, 44) },
	hubCeiling = { material = Enum.Material.Slate, color = rgb(36, 38, 44) },
	trim = { material = Enum.Material.Marble, color = rgb(240, 240, 236) },
	tunnel = { material = Enum.Material.Marble, color = rgb(205, 205, 200) },
	locker = { material = Enum.Material.Wood, color = rgb(90, 66, 44) },
	columns = true,
	writings = {
		"KEEP YOUR EYES OPEN", "IT MOVES WHEN YOU DON'T LOOK", "WHICH ONE IS REAL", "IT WAS NEVER A STATUE", "LOOK AT IT",
		"THE LIGHTS WILL GO OUT", "WALK BACKWARDS", "SIX PHOTOGRAPHS", "DON'T TURN AROUND",
	},
	writingColor = rgb(60, 62, 70),
	writingFont = Enum.Font.Creepster,
	writingGlow = false,
	exitStyle = "grand",
	lamp = lampPost,
	hubLamps = function(ctx: Ctx)
		hubCellLamps(ctx, Themes.atrium)
	end,
	cell = function(ctx: Ctx, x: number, z: number, info: CellInfo)
		local random = ctx.random
		local C = ctx.C
		local center = ctx.cellCenter(x, z)
		if not info.spot then
			local roll = random:NextNumber()
			local spot = CFrame.new(center + Vector3.new(random:NextNumber(-C * 0.3, C * 0.3), 0, random:NextNumber(-C * 0.3, C * 0.3))) * CFrame.Angles(0, random:NextInteger(0, 3) * math.pi / 2, 0)
			if roll < 0.12 then
				solid(ctx, "Bench", Vector3.new(6, 0.6, 2), spot * CFrame.new(0, 1.6, 0), Enum.Material.Marble, rgb(215, 215, 210))
				for _, sx in { -2.4, 2.4 } do
					solid(ctx, "BenchLeg", Vector3.new(0.8, 1.3, 1.8), spot * CFrame.new(sx, 0.65, 0), Enum.Material.Marble, rgb(200, 200, 196))
				end
			elseif roll < 0.22 then
				bust(ctx, spot)
			elseif roll < 0.28 then
				for i = 0, 2 do
					solid(ctx, "Stanchion", Vector3.new(3.2, 0.3, 0.3), spot * CFrame.new(i * 3 - 3, 1.6, 0) * UP, Enum.Material.Metal, rgb(180, 150, 70), Enum.PartType.Cylinder)
					if i < 2 then
						deco(ctx, "Rope", Vector3.new(3, 0.2, 0.2), spot * CFrame.new(i * 3 - 1.5, 2.8, 0), Enum.Material.Fabric, rgb(120, 20, 25), Enum.PartType.Cylinder)
					end
				end
			elseif roll < 0.34 then
				solid(ctx, "Planter", Vector3.new(2.6, 2.4, 2.6), spot * CFrame.new(0, 1.2, 0), Enum.Material.Marble, rgb(190, 190, 186))
				deco(ctx, "Trunk", Vector3.new(6, 0.5, 0.5), spot * CFrame.new(0, 5, 0) * UP, Enum.Material.Wood, rgb(50, 44, 40), Enum.PartType.Cylinder)
				for _ = 1, 4 do
					deco(ctx, "Branch", Vector3.new(0.2, 3, 0.2), spot * CFrame.new(0, 7.5, 0) * CFrame.Angles(random:NextNumber(-0.8, 0.8), random:NextNumber(0, 6), random:NextNumber(-0.8, 0.8)) * CFrame.new(0, 1.4, 0), Enum.Material.Wood, rgb(50, 44, 40))
				end
			end
		end
		-- huge empty frames on the partition walls
		for _, side in ctx.wallSides(x, z) do
			if random:NextNumber() < 0.25 then
				local f = ctx.sideFrame(x, z, side)
				solid(ctx, "GiltFrame", Vector3.new(9, 7, 0.4), f * CFrame.new(0, 7.5, -0.2), Enum.Material.Wood, rgb(150, 115, 55))
				deco(ctx, "EmptyCanvas", Vector3.new(8, 6, 0.1), f * CFrame.new(0, 7.5, -0.42), Enum.Material.SmoothPlastic, rgb(12, 12, 14))
			end
		end
	end,
	room = noop,
	hub = function(ctx: Ctx)
		local O = ctx.hubOrigin
		local C = ctx.C
		solid(ctx, "TicketBooth", Vector3.new(7, 5, 4), CFrame.new(O + Vector3.new(6, 2.5, C * 1.3)), Enum.Material.Wood, rgb(80, 60, 45))
		local walls = hubWalls(ctx)
		local w = walls[1]
		ctx.note(ctx.sideFrame(w.cell.x, w.cell.z, w.side) * CFrame.new(0, 3.4, -1.2), "To whoever finds this,\nThe statues were never supposed to move.\nKEEP LOOKING AT IT. It cannot move while it is seen.\nWhen the lights blink, it comes closer.\nSix photographs are scattered through the halls. Collect them and the doors will remember you.\n- the curator")
		local w2 = walls[math.min(3, #walls)]
		ctx.sign(ctx.sideFrame(w2.cell.x, w2.cell.z, w2.side) * CFrame.new(0, 8, -0.1), Vector2.new(10, 3), "THE ATRIUM\nPLEASE DO NOT TOUCH THE EXHIBITS", rgb(40, 40, 46), rgb(220, 218, 210), false, Enum.Font.Fondamento)
	end,
	extra = function(ctx: Ctx)
		local layout = ctx.layout
		-- moonlight falling through skylights, spread across the hall
		local shafts: { Vector3 } = {}
		for _ = 1, 40 do
			if #shafts >= 6 then
				break
			end
			local c = ctx.cellCenter(ctx.random:NextInteger(0, layout.width - 1), ctx.random:NextInteger(0, layout.depth - 1))
			local ok = true
			for _, other in shafts do
				if (other - c).Magnitude < ctx.C * 2.5 then
					ok = false
				end
			end
			if ok then
				table.insert(shafts, c)
				Dressing.moonShaft(ctx, c + Vector3.new(ctx.C * 0.25, 0, -ctx.C * 0.25))
			end
		end
		-- the far end: a sealed pair of giant doors up a short flight of steps
		local gx = math.floor(layout.width / 2)
		local gz = layout.depth - 1
		local gate = ctx.sideFrame(gx, gz, "N")
		for i = 0, 2 do
			solid(ctx, "Step", Vector3.new(14 - i * 2, 0.6, 3 - i * 0.6), gate * CFrame.new(0, 0.3 + i * 0.6, -1.5 - (2 - i) * 0.6), Enum.Material.Marble, rgb(215, 215, 210))
		end
		solid(ctx, "GreatDoor", Vector3.new(10, 15, 0.6), gate * CFrame.new(0, 9, -0.3), Enum.Material.Wood, rgb(60, 42, 30))
		deco(ctx, "DoorSeam", Vector3.new(0.15, 15, 0.1), gate * CFrame.new(0, 9, -0.65), Enum.Material.SmoothPlastic, rgb(10, 8, 6))
		for _, sx in { -1, 1 } do
			deco(ctx, "DoorRing", Vector3.new(0.2, 1.2, 1.2), gate * CFrame.new(sx * 1.2, 8, -0.7) * CFrame.Angles(0, math.rad(90), 0), Enum.Material.Metal, rgb(170, 140, 70), Enum.PartType.Cylinder)
			solid(ctx, "DoorColumn", Vector3.new(1.6, 17, 1.6), gate * CFrame.new(sx * 6, 8.5, -0.8), Enum.Material.Marble, rgb(225, 225, 220))
		end
		ctx.sign(gate * CFrame.new(0, 17.6, -0.4), Vector2.new(10, 1.6), "THE COLLECTION IS CLOSED", rgb(40, 40, 46), rgb(214, 210, 200), false, Enum.Font.Fondamento)
		-- decoy statues: some of these are just statues
		local spots: { [string]: boolean } = {}
		for _, s in layout.spots do
			spots[Maze.key(s.x, s.z)] = true
		end
		local placed = 0
		local tries = 0
		while placed < 8 and tries < 80 do
			tries += 1
			local x = ctx.random:NextInteger(0, layout.width - 1)
			local z = ctx.random:NextInteger(0, layout.depth - 1)
			local k = Maze.key(x, z)
			if not Maze.isHub(layout, x, z) and not spots[k] and (math.abs(x - layout.entrance.x) + math.abs(z - layout.entrance.z)) > 1 then
				spots[k] = true
				placed += 1
				-- a mix of both kinds, so you can't tell the real one by its shape
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
	end,
	spawns = hallSpawns,
}

---------------------------------------------------------------------------
-- NIGHT 5: THE VOID

-- dim veins: the Void is dark now; only the monster glows properly
local VEIN_COLORS = { rgb(70, 26, 110), rgb(90, 30, 90), rgb(56, 30, 110) }

local function crystalLamp(ctx: Ctx, cell: Cell?, position: Vector3)
	local random = ctx.random
	local C = ctx.C
	local base = position + Vector3.new(random:NextNumber(-C * 0.32, C * 0.32), 0, random:NextNumber(-C * 0.32, C * 0.32))
	for _ = 1, 3 do
		local h = random:NextNumber(2.5, 5)
		local shard = deco(ctx, "Crystal", Vector3.new(0.7, h, 0.7), CFrame.new(base + Vector3.new(random:NextNumber(-0.8, 0.8), h / 2 - 0.3, random:NextNumber(-0.8, 0.8))) * CFrame.Angles(random:NextNumber(-0.35, 0.35), random:NextNumber(0, 6), random:NextNumber(-0.35, 0.35)), Enum.Material.Glass, rgb(34, 20, 52))
		shard.Transparency = 0.15
		shard.Reflectance = 0.2
	end
	-- a faint ember inside the cluster
	local bulb = ctx.decor(ctx.part(ctx.lights, "CrystalCore", Vector3.new(0.5, 0.5, 0.5), CFrame.new(base + Vector3.new(0, 1, 0)), Enum.Material.Neon, rgb(110, 50, 170), Enum.PartType.Ball))
	bulb.CastShadow = false
	local light = Instance.new("PointLight")
	light.Range = 16
	light.Brightness = random:NextNumber(0.5, 0.8)
	light.Color = ctx.night.lighting.LampColor
	light.Shadows = true
	light.Parent = bulb
	bulb:SetAttribute("Pulse", true)
	ctx.addLamp(bulb, light, cell)
end

Themes.void = {
	wall = { material = Enum.Material.Basalt, color = rgb(38, 32, 48) },
	hubWall = { material = Enum.Material.Basalt, color = rgb(44, 36, 56) },
	floor = { material = Enum.Material.Glass, color = rgb(12, 10, 16), reflect = 0.3 },
	hubFloor = function(_room: string): Style
		return { material = Enum.Material.Glass, color = rgb(14, 10, 20), reflect = 0.4 }
	end,
	ceiling = { material = Enum.Material.SmoothPlastic, color = rgb(0, 0, 0) },
	hubCeiling = { material = Enum.Material.SmoothPlastic, color = rgb(0, 0, 0) },
	trim = { material = Enum.Material.Basalt, color = rgb(24, 18, 32) },
	tunnel = { material = Enum.Material.Basalt, color = rgb(26, 20, 34) },
	locker = { material = Enum.Material.Basalt, color = rgb(24, 18, 32) },
	columns = false,
	writings = {
		"THIS IS WHERE THE COLOR WENT", "BREAK THE HEARTS", "IT IS ALL OF THEM", "YOU WERE NEVER AWAKE", "WAKE UP",
		"IT CAN SMELL YOU", "THREE HEARTS ONE BODY", "RUN WHEN THE LAST ONE BREAKS", "THERE IS NO MORNING HERE",
		"WE ARE STILL HERE", "YOU CAME BACK", "IT REMEMBERS EVERY NIGHT",
	},
	writingColor = rgb(170, 110, 220),
	writingFont = Enum.Font.Creepster,
	writingGlow = false,
	exitStyle = "portal",
	lamp = crystalLamp,
	hubLamps = function(ctx: Ctx)
		local hub = ctx.layout.hub
		crystalLamp(ctx, nil, ctx.cellCenter(hub.x0, hub.z0 + 1))
		crystalLamp(ctx, nil, ctx.cellCenter(hub.x0 + hub.w - 1, hub.z0 + 1))
	end,
	cell = function(ctx: Ctx, x: number, z: number, info: CellInfo)
		local random = ctx.random
		local C, H = ctx.C, ctx.H
		local center = ctx.cellCenter(x, z)
		for _, side in ctx.wallSides(x, z) do
			if random:NextNumber() < 0.1 then
				local f = ctx.sideFrame(x, z, side)
				local vein = deco(ctx, "Vein", Vector3.new(0.14, random:NextNumber(3, 8), 0.05), f * CFrame.new(random:NextNumber(-C * 0.4, C * 0.4), random:NextNumber(2, H - 3), -0.04) * CFrame.Angles(0, 0, random:NextNumber(-0.7, 0.7)), Enum.Material.Neon, VEIN_COLORS[random:NextInteger(1, #VEIN_COLORS)])
				vein.CastShadow = false
			end
		end
		-- black spikes hanging from far above
		if random:NextNumber() < 0.12 then
			for _ = 1, random:NextInteger(1, 3) do
				local len = random:NextNumber(6, 16)
				Dressing.egg(deco(ctx, "Spike", Vector3.new(1.2, len * 2, 1.2), CFrame.new(center + Vector3.new(random:NextNumber(-C / 2.5, C / 2.5), ctx.ceiling, random:NextNumber(-C / 2.5, C / 2.5))), Enum.Material.Basalt, rgb(14, 10, 18)))
			end
		end
		-- pieces of the other nights, drifting
		if not info.spot and random:NextNumber() < 0.1 then
			Dressing.floatingMemory(ctx, center + Vector3.new(random:NextNumber(-3, 3), random:NextNumber(5, 12), random:NextNumber(-3, 3)))
		end
		if random:NextNumber() < 0.25 then
			for _ = 1, random:NextInteger(1, 3) do
				local s = random:NextNumber(1.5, 4.5)
				local rock = deco(ctx, "FloatingRock", Vector3.new(s, s * random:NextNumber(0.6, 1.4), s * random:NextNumber(0.7, 1.3)), CFrame.new(center + Vector3.new(random:NextNumber(-C / 2, C / 2), H + random:NextNumber(3, 18), random:NextNumber(-C / 2, C / 2))) * CFrame.Angles(random:NextNumber(0, 6), random:NextNumber(0, 6), random:NextNumber(0, 6)), Enum.Material.Basalt, rgb(22, 18, 30))
				CollectionService:AddTag(rock, "Float")
			end
		end
		local sides = ctx.wallSides(x, z)
		if #sides > 0 and random:NextNumber() < 0.09 then
			-- something is looking out of the wall
			local f = ctx.sideFrame(x, z, sides[random:NextInteger(1, #sides)])
			local eyes = f * CFrame.new(random:NextNumber(-2, 2), random:NextNumber(4, 8), 0)
			for _, sx in { -0.5, 0.5 } do
				local eye = deco(ctx, "WallEye", Vector3.new(0.45, 0.45, 0.45), eyes * CFrame.new(sx, 0, -0.05), Enum.Material.Neon, rgb(240, 230, 255), Enum.PartType.Ball)
				CollectionService:AddTag(eye, "WallEye")
				deco(ctx, "Pupil", Vector3.new(0.18, 0.18, 0.1), eyes * CFrame.new(sx, 0, -0.27), Enum.Material.SmoothPlastic, rgb(0, 0, 0))
			end
		end
		if not info.spot and random:NextNumber() < 0.06 then
			local m = solid(ctx, "Monolith", Vector3.new(2.4, 9, 1), CFrame.new(center + Vector3.new(random:NextNumber(-3, 3), 4.5, random:NextNumber(-3, 3))) * CFrame.Angles(0, random:NextNumber(0, 6), random:NextNumber(-0.1, 0.1)), Enum.Material.Basalt, rgb(10, 8, 14))
			ctx.sign(m.CFrame * CFrame.new(0, 1, -0.55), Vector2.new(2, 5), "◇\n△\n○", rgb(150, 90, 200), nil, false, Enum.Font.Code)
		end
	end,
	room = function(ctx: Ctx, block: { Cell })
		-- each room remembers one of the earlier nights
		Dressing.memoryRoom(ctx, block, (roomIndex(ctx, block) - 1) % 3 + 1, block[1])
		local center = Dressing.blockCenter(ctx, block)
		for i = 0, 3 do
			local a = i * math.pi / 2 + math.pi / 4
			local m = solid(ctx, "Monolith", Vector3.new(2, 10, 1), CFrame.new(center + Vector3.new(math.cos(a) * 9, 5, math.sin(a) * 9)) * CFrame.Angles(0, -a + math.pi / 2, 0), Enum.Material.Basalt, rgb(10, 8, 14))
			ctx.sign(m.CFrame * CFrame.new(0, 1.5, -0.55), Vector2.new(1.6, 6), "W\nA\nK\nE", rgb(150, 90, 200), nil, false, Enum.Font.Creepster)
		end
	end,
	hub = function(ctx: Ctx)
		local O = ctx.hubOrigin
		local hub = ctx.layout.hub
		local C = ctx.C
		local center = O + Vector3.new(hub.w * C / 2, 0, hub.d * C / 2 + 2)
		for i = 0, 7 do
			local a = i * math.pi / 4
			solid(ctx, "ThresholdPillar", Vector3.new(1.6, 12, 1.6), CFrame.new(center + Vector3.new(math.cos(a) * 13, 6, math.sin(a) * 13)), Enum.Material.Basalt, rgb(14, 10, 20))
		end
		local walls = hubWalls(ctx)
		local w = walls[1]
		ctx.note(ctx.sideFrame(w.cell.x, w.cell.z, w.side) * CFrame.new(0, 3.4, -1.2), "There were others before you.\nThey broke the hearts and they ran.\nThe way out only opens when all three stop beating.\nIt KNOWS the moment one stops.\nIt can smell you through a locker door if it's close.")
	end,
	extra = noop,
	spawns = hallSpawns,
}

return Themes
