--!strict
-- Set dressing shared by the map themes: furniture, landmark rooms and the small
-- touches that make each map feel lived-in (or died-in). Themes.luau decides where
-- these go; this file only knows how to build them.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Maze = require(ReplicatedStorage.Shared.Maze)
local Build = require(script.Parent.Build)

type Ctx = Build.Ctx
type Cell = Maze.Cell

local Dressing = {}

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

local function egg(p: BasePart): BasePart
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- A small light that flickers with the others (and dies when the monster is near).
local function smallLamp(ctx: Ctx, bulb: BasePart, cell: Cell?, range: number, brightness: number, color: Color3, shadows: boolean)
	local light = Instance.new("PointLight")
	light.Range = range
	light.Brightness = brightness
	light.Color = color
	light.Shadows = shadows
	light.Parent = bulb
	ctx.addLamp(bulb, light, cell)
end

Dressing.egg = egg
Dressing.UP = UP

-- Cells ------------------------------------------------------------------------

-- "NS" or "EW" for a plain straight corridor cell, nil for corners and junctions.
function Dressing.straightAxis(ctx: Ctx, x: number, z: number): string?
	local function open(side: string): boolean
		return Maze.isPassable(Maze.getEdge(ctx.layout, x, z, side))
	end
	local n, s, e, w = open("N"), open("S"), open("E"), open("W")
	if n and s and not e and not w then
		return "NS"
	elseif e and w and not n and not s then
		return "EW"
	end
	return nil
end

function Dressing.isBoundary(ctx: Ctx, x: number, z: number, side: string): boolean
	local nx, nz = x + Maze.DX[side], z + Maze.DZ[side]
	return not Maze.inBounds(ctx.layout, nx, nz)
end

-- Every open edge between two plain maze cells (not hub, not inside a room).
function Dressing.openEdges(ctx: Ctx, roomCells: { [string]: boolean }): { { x: number, z: number, dir: string } }
	local out = {}
	local layout = ctx.layout
	for z = 0, layout.depth - 1 do
		for x = 0, layout.width - 1 do
			for _, dir in { "N", "E" } do
				local nx, nz = x + Maze.DX[dir], z + Maze.DZ[dir]
				if Maze.inBounds(layout, nx, nz) and Maze.getEdge(layout, x, z, dir) == "open" then
					local plain = not Maze.isHub(layout, x, z) and not Maze.isHub(layout, nx, nz)
					if plain and not roomCells[Maze.key(x, z)] and not roomCells[Maze.key(nx, nz)] then
						table.insert(out, { x = x, z = z, dir = dir })
					end
				end
			end
		end
	end
	return out
end

function Dressing.blockCenter(ctx: Ctx, block: { Cell }): Vector3
	local sum = Vector3.zero
	for _, c in block do
		sum += ctx.cellCenter(c.x, c.z)
	end
	return sum / #block
end

-- A wall face inside a room block that is still a solid wall (for things to stand against).
function Dressing.roomWall(ctx: Ctx, block: { Cell }): (Cell?, string?)
	for _, c in block do
		local sides = ctx.wallSides(c.x, c.z)
		if #sides > 0 then
			return c, sides[ctx.random:NextInteger(1, #sides)]
		end
	end
	return nil, nil
end

-- Furniture ------------------------------------------------------------------------

-- Something under a white dust sheet. Sometimes it's the shape of a person.
function Dressing.sheeted(ctx: Ctx, at: CFrame, kind: string)
	local sheet = rgb(198, 196, 190)
	local fabric = Enum.Material.Fabric
	if kind == "person" then
		egg(solid(ctx, "Sheet", Vector3.new(2.6, 6.2, 2), at * CFrame.new(0, 3.1, 0), fabric, sheet))
		egg(solid(ctx, "SheetHead", Vector3.new(1.4, 1.7, 1.4), at * CFrame.new(0, 6.6, -0.1) * CFrame.Angles(0.15, 0, 0.12), fabric, sheet))
		deco(ctx, "SheetHem", Vector3.new(3, 0.2, 2.4), at * CFrame.new(0, 0.1, 0), fabric, sheet)
	elseif kind == "tall" then
		solid(ctx, "Sheet", Vector3.new(3.2, 6.5, 2), at * CFrame.new(0, 3.25, 0), fabric, sheet)
		egg(deco(ctx, "SheetTop", Vector3.new(3.4, 1.2, 2.2), at * CFrame.new(0, 6.5, 0), fabric, sheet))
	else
		egg(solid(ctx, "Sheet", Vector3.new(3.4, 3.4, 3.2), at * CFrame.new(0, 1.7, 0), fabric, sheet))
		deco(ctx, "SheetHem", Vector3.new(3.6, 0.8, 3.4), at * CFrame.new(0, 0.4, 0), fabric, sheet)
	end
end

-- A door set into a wall that doesn't open (there's nothing behind it).
function Dressing.fakeDoor(ctx: Ctx, wall: CFrame, color: Color3)
	local dw, dh = 4, 8
	solid(ctx, "DoorFrame", Vector3.new(dw + 0.8, dh + 0.4, 0.3), wall * CFrame.new(0, (dh + 0.4) / 2, -0.15), Enum.Material.Wood, color:Lerp(Color3.new(0, 0, 0), 0.3))
	solid(ctx, "Door", Vector3.new(dw, dh, 0.25), wall * CFrame.new(0, dh / 2, -0.32), Enum.Material.Wood, color)
	for _, py in { 2.2, 5.6 } do
		deco(ctx, "DoorPanel", Vector3.new(dw - 1.2, 2.6, 0.08), wall * CFrame.new(0, py, -0.47), Enum.Material.Wood, color:Lerp(Color3.new(0, 0, 0), 0.15))
	end
	deco(ctx, "Knob", Vector3.new(0.35, 0.35, 0.35), wall * CFrame.new(dw / 2 - 0.5, dh * 0.45, -0.55), Enum.Material.Metal, rgb(160, 150, 120), Enum.PartType.Ball)
end

-- A side table against a wall with a little lamp on it.
function Dressing.tableLamp(ctx: Ctx, wall: CFrame, cell: Cell?, withLight: boolean)
	local wood = Enum.Material.Wood
	local dark = rgb(60, 48, 40)
	local base = wall * CFrame.new(ctx.random:NextNumber(-2.5, 2.5), 0, -1.3)
	solid(ctx, "SideTable", Vector3.new(2.6, 0.25, 1.8), base * CFrame.new(0, 2.6, 0), wood, dark)
	for _, l in { { -1.1, -0.7 }, { 1.1, -0.7 }, { -1.1, 0.7 }, { 1.1, 0.7 } } do
		deco(ctx, "TableLeg", Vector3.new(0.2, 2.5, 0.2), base * CFrame.new(l[1], 1.25, l[2]), wood, dark)
	end
	deco(ctx, "LampStem", Vector3.new(1.3, 0.25, 0.25), base * CFrame.new(0, 3.35, 0) * UP, Enum.Material.Metal, rgb(90, 86, 80), Enum.PartType.Cylinder)
	deco(ctx, "LampShade", Vector3.new(1.2, 1.4, 1.4), base * CFrame.new(0, 4.3, 0) * UP, Enum.Material.Fabric, rgb(170, 164, 150), Enum.PartType.Cylinder)
	local bulb = deco(ctx, "Bulb", Vector3.new(0.5, 0.5, 0.5), base * CFrame.new(0, 3.95, 0), Enum.Material.Neon, rgb(230, 222, 200), Enum.PartType.Ball)
	bulb.CastShadow = false
	if withLight then
		smallLamp(ctx, bulb, cell, 13, 0.9, rgb(255, 236, 205), true)
	else
		bulb.Color = rgb(40, 38, 36)
	end
end

function Dressing.mirror(ctx: Ctx, wall: CFrame)
	local at = wall * CFrame.new(ctx.random:NextNumber(-2, 2), 6, -0.1)
	solid(ctx, "MirrorFrame", Vector3.new(3.4, 4.6, 0.25), at, Enum.Material.Wood, rgb(40, 34, 30))
	local glass = deco(ctx, "Mirror", Vector3.new(2.8, 4, 0.06), at * CFrame.new(0, 0, -0.15), Enum.Material.Glass, rgb(150, 155, 160))
	glass.Reflectance = 0.65
	for _ = 1, 3 do
		deco(ctx, "Crack", Vector3.new(0.04, ctx.random:NextNumber(1, 2.4), 0.02), at * CFrame.new(ctx.random:NextNumber(-0.8, 0.8), ctx.random:NextNumber(-1, 1), -0.2) * CFrame.Angles(0, 0, ctx.random:NextNumber(-1, 1)), Enum.Material.SmoothPlastic, rgb(230, 230, 230)).Transparency = 0.3
	end
end

-- A window in an outside wall: nothing but black outside, curtains half drawn.
function Dressing.window(ctx: Ctx, wall: CFrame, height: number, curtains: Color3?)
	local w, h = 4.4, height
	local at = wall * CFrame.new(0, 3 + h / 2, -0.05)
	local frame = rgb(48, 40, 34)
	for _, sx in { -1, 1 } do
		solid(ctx, "WindowFrame", Vector3.new(0.35, h + 0.7, 0.4), at * CFrame.new(sx * (w / 2 + 0.17), 0, 0), Enum.Material.Wood, frame)
	end
	solid(ctx, "WindowFrame", Vector3.new(w + 0.7, 0.35, 0.4), at * CFrame.new(0, h / 2 + 0.17, 0), Enum.Material.Wood, frame)
	solid(ctx, "Sill", Vector3.new(w + 1, 0.3, 0.8), at * CFrame.new(0, -h / 2 - 0.15, -0.2), Enum.Material.Wood, frame)
	deco(ctx, "Mullion", Vector3.new(0.18, h, 0.3), at, Enum.Material.Wood, frame)
	deco(ctx, "Mullion", Vector3.new(w, 0.18, 0.3), at, Enum.Material.Wood, frame)
	local glass = deco(ctx, "WindowGlass", Vector3.new(w, h, 0.05), at * CFrame.new(0, 0, 0.05), Enum.Material.Glass, rgb(8, 9, 12))
	glass.Reflectance = 0.25
	if curtains then
		for _, sx in { -1, 1 } do
			deco(ctx, "Curtain", Vector3.new(1.4, h + 1.2, 0.15), at * CFrame.new(sx * (w / 2 - 0.4), 0, -0.35) * CFrame.Angles(0, 0, sx * 0.03), Enum.Material.Fabric, curtains)
		end
	end
end

function Dressing.chair(ctx: Ctx, at: CFrame, color: Color3, toppled: boolean?)
	local wood = Enum.Material.Wood
	local base = if toppled then at * CFrame.new(0, 1.1, 0) * CFrame.Angles(math.rad(90), 0, 0) * CFrame.new(0, -1.1, 0) else at
	solid(ctx, "ChairSeat", Vector3.new(2, 0.3, 2), base * CFrame.new(0, 2, 0), wood, color)
	solid(ctx, "ChairBack", Vector3.new(2, 3, 0.3), base * CFrame.new(0, 3.5, 0.85), wood, color)
	for _, l in { { -0.8, -0.8 }, { 0.8, -0.8 }, { -0.8, 0.8 }, { 0.8, 0.8 } } do
		deco(ctx, "ChairLeg", Vector3.new(0.22, 2, 0.22), base * CFrame.new(l[1], 1, l[2]), wood, color)
	end
end

function Dressing.ladder(ctx: Ctx, wall: CFrame, height: number, color: Color3)
	local at = wall * CFrame.new(ctx.random:NextNumber(-3, 3), 0, -0.4)
	for _, sx in { -0.75, 0.75 } do
		deco(ctx, "LadderRail", Vector3.new(0.2, height, 0.2), at * CFrame.new(sx, height / 2, 0), Enum.Material.CorrodedMetal, color)
	end
	for y = 1, height - 0.5, 1.1 do
		deco(ctx, "LadderRung", Vector3.new(1.5, 0.14, 0.14), at * CFrame.new(0, y, 0), Enum.Material.CorrodedMetal, color)
	end
end

function Dressing.rat(ctx: Ctx, at: CFrame)
	local fur = rgb(34, 30, 28)
	local body = egg(deco(ctx, "Rat", Vector3.new(0.55, 0.42, 1.0), at * CFrame.new(0, 0.2, 0), Enum.Material.Fabric, fur))
	egg(deco(ctx, "RatHead", Vector3.new(0.34, 0.3, 0.5), body.CFrame * CFrame.new(0, 0.03, -0.55), Enum.Material.Fabric, fur))
	egg(deco(ctx, "RatTail", Vector3.new(0.07, 0.07, 1.1), body.CFrame * CFrame.new(0.1, -0.12, 0.95) * CFrame.Angles(0, 0.4, 0), Enum.Material.SmoothPlastic, rgb(80, 64, 60)))
end

-- Rooms --------------------------------------------------------------------------

-- Night 1: a dining room laid for a dinner nobody came to.
function Dressing.diningRoom(ctx: Ctx, block: { Cell }, cell: Cell?)
	local c = Dressing.blockCenter(ctx, block)
	local wood = Enum.Material.Wood
	local dark = rgb(56, 44, 36)
	local base = CFrame.new(c)
	deco(ctx, "Rug", Vector3.new(18, 0.08, 12), base * CFrame.new(0, 0.04, 0), Enum.Material.Fabric, rgb(70, 66, 66))
	solid(ctx, "TableTop", Vector3.new(14, 0.4, 4.6), base * CFrame.new(0, 3.1, 0), wood, dark)
	for _, l in { { -6.4, -1.8 }, { 6.4, -1.8 }, { -6.4, 1.8 }, { 6.4, 1.8 } } do
		deco(ctx, "TableLeg", Vector3.new(0.4, 3, 0.4), base * CFrame.new(l[1], 1.5, l[2]), wood, dark)
	end
	deco(ctx, "Runner", Vector3.new(12, 0.05, 1.4), base * CFrame.new(0, 3.33, 0), Enum.Material.Fabric, rgb(170, 168, 160))
	for i = -1, 1 do
		for _, side in { -1, 1 } do
			local seat = base * CFrame.new(i * 4, 0, side * 3.4) * CFrame.Angles(0, if side > 0 then math.pi else 0, 0)
			Dressing.chair(ctx, seat, dark, i == 1 and side == 1)
			deco(ctx, "Plate", Vector3.new(0.08, 1.3, 1.3), base * CFrame.new(i * 4, 3.34, side * 1.4) * UP, Enum.Material.SmoothPlastic, rgb(225, 225, 220), Enum.PartType.Cylinder)
		end
	end
	Dressing.chair(ctx, base * CFrame.new(-8.6, 0, 0) * CFrame.Angles(0, math.rad(-90), 0), dark, false)
	-- candelabra: the only light in the room
	deco(ctx, "Candelabra", Vector3.new(1.6, 0.3, 0.3), base * CFrame.new(0, 4.1, 0) * UP, Enum.Material.Metal, rgb(150, 140, 110), Enum.PartType.Cylinder)
	local flame: BasePart? = nil
	for i = -1, 1 do
		deco(ctx, "Candle", Vector3.new(0.9, 0.22, 0.22), base * CFrame.new(i * 0.7, 5.3, 0) * UP, Enum.Material.SmoothPlastic, rgb(230, 228, 215), Enum.PartType.Cylinder)
		local f = deco(ctx, "Flame", Vector3.new(0.18, 0.35, 0.18), base * CFrame.new(i * 0.7, 5.95, 0), Enum.Material.Neon, rgb(255, 214, 150))
		f.CastShadow = false
		if i == 0 then
			flame = f
		end
	end
	if flame then
		smallLamp(ctx, flame, cell, 18, 0.9, rgb(255, 214, 160), true)
	end
end

-- Night 1: a nursery. The mobile still turns.
function Dressing.nursery(ctx: Ctx, block: { Cell })
	local c = Dressing.blockCenter(ctx, block)
	local base = CFrame.new(c) * CFrame.Angles(0, ctx.random:NextInteger(0, 3) * math.pi / 2, 0)
	local white = rgb(205, 202, 196)
	local wood = Enum.Material.Wood
	-- crib
	local crib = base * CFrame.new(-3, 0, -2)
	solid(ctx, "CribBase", Vector3.new(6, 0.4, 3.4), crib * CFrame.new(0, 1.6, 0), wood, white)
	deco(ctx, "CribMattress", Vector3.new(5.6, 0.4, 3), crib * CFrame.new(0, 2, 0), Enum.Material.Fabric, rgb(180, 178, 174))
	for i = 0, 11 do
		local x = -2.8 + i * (5.6 / 11)
		for _, sz in { -1.6, 1.6 } do
			deco(ctx, "CribBar", Vector3.new(3, 0.14, 0.14), crib * CFrame.new(x, 2.9, sz) * UP, wood, white, Enum.PartType.Cylinder)
		end
	end
	for _, sz in { -1.6, 1.6 } do
		deco(ctx, "CribRail", Vector3.new(6, 0.25, 0.25), crib * CFrame.new(0, 4.4, sz), wood, white)
	end
	for _, sx in { -3, 3 } do
		solid(ctx, "CribEnd", Vector3.new(0.3, 4.6, 3.4), crib * CFrame.new(sx, 2.3, 0), wood, white)
	end
	-- the mobile, hanging over the crib
	local top = ctx.ceiling
	deco(ctx, "MobileString", Vector3.new(0.05, top - 7, 0.05), crib * CFrame.new(0, (top + 7) / 2, 0), Enum.Material.SmoothPlastic, rgb(30, 30, 30))
	local mobile = deco(ctx, "Mobile", Vector3.new(2.4, 0.1, 0.1), crib * CFrame.new(0, 7, 0), wood, white)
	CollectionService:AddTag(mobile, "Spin")
	for i = 0, 3 do
		local a = i * math.pi / 2
		deco(ctx, "MobileToy", Vector3.new(0.4, 0.4, 0.4), crib * CFrame.new(math.cos(a) * 1.1, 6.3, math.sin(a) * 1.1), Enum.Material.SmoothPlastic, rgb(220, 218, 210), if i % 2 == 0 then Enum.PartType.Ball else nil)
	end
	-- rocking chair facing the crib, and blocks on the floor
	local rocker = base * CFrame.new(4, 0, 3) * CFrame.Angles(0, math.rad(200), 0)
	solid(ctx, "RockerSeat", Vector3.new(2.4, 0.3, 2.4), rocker * CFrame.new(0, 1.9, 0), wood, rgb(70, 58, 48))
	solid(ctx, "RockerBack", Vector3.new(2.4, 3.6, 0.3), rocker * CFrame.new(0, 3.8, 1.1) * CFrame.Angles(-0.15, 0, 0), wood, rgb(70, 58, 48))
	for _, sx in { -1, 1 } do
		deco(ctx, "Rocker", Vector3.new(0.2, 0.3, 3.4), rocker * CFrame.new(sx * 1.05, 0.4, 0) * CFrame.Angles(0.12, 0, 0), wood, rgb(70, 58, 48))
		deco(ctx, "RockerLeg", Vector3.new(0.2, 1.6, 0.2), rocker * CFrame.new(sx * 1.05, 1.15, -0.9), wood, rgb(70, 58, 48))
		deco(ctx, "RockerLeg", Vector3.new(0.2, 1.6, 0.2), rocker * CFrame.new(sx * 1.05, 1.15, 0.9), wood, rgb(70, 58, 48))
	end
	for i = 1, 6 do
		local s = 0.9
		deco(ctx, "Block", Vector3.new(s, s, s), base * CFrame.new(ctx.random:NextNumber(-2, 3), s / 2 + (if i == 6 then s else 0), ctx.random:NextNumber(1, 4)) * CFrame.Angles(0, ctx.random:NextNumber(0, 6), 0), wood, rgb(150, 148, 144))
	end
	-- a doll sitting in the corner, facing you
	local doll = base * CFrame.new(-5, 0, 4.5) * CFrame.Angles(0, math.rad(150), 0)
	egg(solid(ctx, "DollBody", Vector3.new(1.1, 1.5, 0.9), doll * CFrame.new(0, 0.75, 0), Enum.Material.Fabric, rgb(150, 146, 140)))
	egg(deco(ctx, "DollHead", Vector3.new(0.9, 1, 0.9), doll * CFrame.new(0, 1.9, 0) * CFrame.Angles(0, 0, 0.35), Enum.Material.SmoothPlastic, rgb(225, 220, 212)))
	for _, sx in { -0.18, 0.18 } do
		deco(ctx, "DollEye", Vector3.new(0.14, 0.14, 0.14), doll * CFrame.new(sx - 0.15, 1.95, -0.42), Enum.Material.SmoothPlastic, rgb(10, 10, 10), Enum.PartType.Ball)
	end
end

-- Night 1: a bathroom. The tub is full. Don't look in the mirror too long.
function Dressing.bathroom(ctx: Ctx, block: { Cell })
	local c = Dressing.blockCenter(ctx, block)
	local base = CFrame.new(c) * CFrame.Angles(0, ctx.random:NextInteger(0, 3) * math.pi / 2, 0)
	local porcelain = rgb(215, 214, 208)
	deco(ctx, "Tiles", Vector3.new(22, 0.06, 22), base * CFrame.new(0, 0.03, 0), Enum.Material.CeramicTiles, rgb(160, 160, 156))
	local tub = base * CFrame.new(-4, 0, -4)
	for _, p in { { 0, -1.6, 7, 0.4 }, { 0, 1.6, 7, 0.4 } } do
		solid(ctx, "TubSide", Vector3.new(p[3], 2.6, p[4]), tub * CFrame.new(p[1], 1.3, p[2]), Enum.Material.SmoothPlastic, porcelain)
	end
	for _, sx in { -3.3, 3.3 } do
		solid(ctx, "TubEnd", Vector3.new(0.4, 2.6, 3.6), tub * CFrame.new(sx, 1.3, 0), Enum.Material.SmoothPlastic, porcelain)
	end
	local water = deco(ctx, "TubWater", Vector3.new(6.2, 0.1, 2.8), tub * CFrame.new(0, 2.1, 0), Enum.Material.Glass, rgb(20, 20, 22))
	water.Reflectance = 0.4
	deco(ctx, "ShowerRail", Vector3.new(7, 0.15, 0.15), tub * CFrame.new(0, 8, 1.6), Enum.Material.Metal, rgb(160, 160, 160), Enum.PartType.Cylinder)
	local curtain = deco(ctx, "ShowerCurtain", Vector3.new(3.2, 6, 0.08), tub * CFrame.new(-1.6, 5, 1.6), Enum.Material.Fabric, rgb(190, 190, 186))
	curtain.Transparency = 0.25
	-- sink + mirror on a wall
	local cell, side = Dressing.roomWall(ctx, block)
	if cell and side then
		local wall = ctx.sideFrame(cell.x, cell.z, side)
		local sink = wall * CFrame.new(0, 0, -1.2)
		solid(ctx, "SinkStand", Vector3.new(1, 3, 1), sink * CFrame.new(0, 1.5, 0), Enum.Material.SmoothPlastic, porcelain)
		egg(solid(ctx, "Sink", Vector3.new(2.4, 0.8, 1.8), sink * CFrame.new(0, 3.2, 0), Enum.Material.SmoothPlastic, porcelain))
		Dressing.mirror(ctx, wall)
	end
	local toilet = base * CFrame.new(4.5, 0, 3.5)
	egg(solid(ctx, "Toilet", Vector3.new(1.6, 1.8, 2.2), toilet * CFrame.new(0, 1, 0), Enum.Material.SmoothPlastic, porcelain))
	solid(ctx, "ToiletTank", Vector3.new(1.8, 2.2, 0.8), toilet * CFrame.new(0, 2.2, 1.2), Enum.Material.SmoothPlastic, porcelain)
end

-- Night 2: an operating theatre. The big lamp still works.
function Dressing.operatingRoom(ctx: Ctx, block: { Cell }, cell: Cell?)
	local c = Dressing.blockCenter(ctx, block)
	local base = CFrame.new(c) * CFrame.Angles(0, ctx.random:NextInteger(0, 1) * math.pi / 2, 0)
	local steel = rgb(170, 175, 178)
	deco(ctx, "FloorTiles", Vector3.new(22, 0.05, 22), base * CFrame.new(0, 0.03, 0), Enum.Material.CeramicTiles, rgb(150, 160, 158))
	solid(ctx, "TableBase", Vector3.new(1.4, 3, 1.4), base * CFrame.new(0, 1.5, 0), Enum.Material.Metal, steel)
	solid(ctx, "OperatingTable", Vector3.new(3, 0.5, 7.5), base * CFrame.new(0, 3.2, 0), Enum.Material.Metal, steel)
	deco(ctx, "TablePad", Vector3.new(2.8, 0.25, 7.2), base * CFrame.new(0, 3.55, 0), Enum.Material.Fabric, rgb(90, 110, 110))
	-- a sheet over a shape on the table
	egg(deco(ctx, "Body", Vector3.new(2.2, 1, 6.4), base * CFrame.new(0, 4, 0.2), Enum.Material.Fabric, rgb(210, 214, 210)))
	egg(deco(ctx, "BodyHead", Vector3.new(1.3, 0.9, 1.4), base * CFrame.new(0, 4.2, -2.9), Enum.Material.Fabric, rgb(210, 214, 210)))
	-- the surgical lamp: a big dish over the table with a spot pointing down
	local H = ctx.ceiling
	deco(ctx, "LampArm", Vector3.new(H - 9, 0.3, 0.3), base * CFrame.new(0, (H + 9) / 2, 0) * UP, Enum.Material.Metal, steel, Enum.PartType.Cylinder)
	local dish = deco(ctx, "SurgicalLamp", Vector3.new(0.8, 3.4, 3.4), base * CFrame.new(0, 8.6, 0) * UP, Enum.Material.Metal, steel, Enum.PartType.Cylinder)
	local face = deco(ctx, "SurgicalLight", Vector3.new(0.1, 2.8, 2.8), dish.CFrame * CFrame.new(-0.42, 0, 0), Enum.Material.Neon, rgb(240, 245, 255), Enum.PartType.Cylinder)
	face.CastShadow = false
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Left
	spot.Angle = 70
	spot.Range = 18
	spot.Brightness = 2.2
	spot.Color = rgb(235, 245, 255)
	spot.Shadows = true
	spot.Parent = face
	ctx.addLamp(face, spot, cell)
	-- tools, gas, monitors
	solid(ctx, "Tray", Vector3.new(2.4, 0.15, 1.4), base * CFrame.new(2.8, 3.6, -1.5), Enum.Material.Metal, steel)
	deco(ctx, "TrayStand", Vector3.new(0.2, 3.5, 0.2), base * CFrame.new(2.8, 1.75, -1.5), Enum.Material.Metal, steel)
	for i = 0, 3 do
		deco(ctx, "Scalpel", Vector3.new(0.08, 0.06, 0.9), base * CFrame.new(2.2 + i * 0.4, 3.72, -1.5) * CFrame.Angles(0, (i - 1.5) * 0.08, 0), Enum.Material.Metal, rgb(210, 210, 215))
	end
	for i = 0, 2 do
		solid(ctx, "GasTank", Vector3.new(4.2, 0.9, 0.9), base * CFrame.new(-4.5, 2.1, 3 + i * 1.1) * UP, Enum.Material.Metal, if i == 1 then rgb(60, 110, 70) else rgb(70, 90, 140), Enum.PartType.Cylinder)
	end
	local monitor = solid(ctx, "Monitor", Vector3.new(2, 1.4, 0.4), base * CFrame.new(-3, 6, -3.5) * CFrame.Angles(0, math.rad(30), 0), Enum.Material.SmoothPlastic, rgb(28, 28, 30))
	ctx.sign(monitor.CFrame * CFrame.new(0, 0, -0.21), Vector2.new(1.8, 1.2), "-- -- --", rgb(90, 255, 140), rgb(4, 16, 8), true, Enum.Font.Code)
	deco(ctx, "MonitorPole", Vector3.new(6, 0.25, 0.25), base * CFrame.new(-3, 3, -3.5) * UP, Enum.Material.Metal, steel, Enum.PartType.Cylinder)
end

-- Night 2: the morgue. One drawer is open.
function Dressing.morgue(ctx: Ctx, block: { Cell })
	local steel = rgb(160, 165, 168)
	local cell, side = Dressing.roomWall(ctx, block)
	if cell and side then
		local wall = ctx.sideFrame(cell.x, cell.z, side)
		local W = ctx.C - ctx.T - 1
		solid(ctx, "DrawerWall", Vector3.new(W, 7.4, 1.2), wall * CFrame.new(0, 3.7, -0.6), Enum.Material.Metal, rgb(120, 124, 126))
		local cols = 4
		local open = ctx.random:NextInteger(1, cols * 3)
		for row = 0, 2 do
			for col = 1, cols do
				local x = -W / 2 + (col - 0.5) * (W / cols)
				local y = 1.4 + row * 2.3
				local i = row * cols + col
				if i == open then
					-- pulled out, with something under a sheet
					local tray = wall * CFrame.new(x, y, -3.4)
					solid(ctx, "DrawerTray", Vector3.new(W / cols - 0.4, 0.3, 5.2), tray, Enum.Material.Metal, steel)
					egg(deco(ctx, "Body", Vector3.new(1.6, 0.9, 4.4), tray * CFrame.new(0, 0.5, 0), Enum.Material.Fabric, rgb(210, 212, 208)))
					deco(ctx, "DrawerHole", Vector3.new(W / cols - 0.5, 1.8, 0.05), wall * CFrame.new(x, y, -1.23), Enum.Material.SmoothPlastic, rgb(4, 4, 4))
				else
					deco(ctx, "DrawerDoor", Vector3.new(W / cols - 0.4, 1.9, 0.12), wall * CFrame.new(x, y, -1.25), Enum.Material.Metal, steel)
					deco(ctx, "DrawerHandle", Vector3.new(1, 0.15, 0.15), wall * CFrame.new(x, y + 0.5, -1.38), Enum.Material.Metal, rgb(200, 200, 200))
					deco(ctx, "DrawerTag", Vector3.new(0.6, 0.35, 0.03), wall * CFrame.new(x, y - 0.3, -1.33), Enum.Material.SmoothPlastic, rgb(220, 218, 205))
				end
			end
		end
	end
	local c = Dressing.blockCenter(ctx, block)
	local tableAt = CFrame.new(c) * CFrame.Angles(0, ctx.random:NextNumber(-0.3, 0.3), 0)
	solid(ctx, "AutopsyTable", Vector3.new(3.2, 0.4, 7.4), tableAt * CFrame.new(0, 3, 0), Enum.Material.Metal, steel)
	solid(ctx, "TablePedestal", Vector3.new(1.2, 2.8, 1.2), tableAt * CFrame.new(0, 1.4, 0), Enum.Material.Metal, steel)
	egg(deco(ctx, "Body", Vector3.new(2, 1, 6.2), tableAt * CFrame.new(0, 3.65, 0), Enum.Material.Fabric, rgb(214, 216, 212)))
	-- a foot sticking out, with a toe tag
	deco(ctx, "Foot", Vector3.new(0.45, 1, 0.5), tableAt * CFrame.new(0.4, 3.7, 3.3), Enum.Material.SmoothPlastic, rgb(190, 176, 166))
	deco(ctx, "ToeTag", Vector3.new(0.5, 0.3, 0.03), tableAt * CFrame.new(0.4, 3.6, 3.62), Enum.Material.SmoothPlastic, rgb(225, 222, 205))
end

-- Night 3: a pump station, long dead.
function Dressing.pumpRoom(ctx: Ctx, block: { Cell })
	local c = Dressing.blockCenter(ctx, block)
	local base = CFrame.new(c) * CFrame.Angles(0, ctx.random:NextInteger(0, 1) * math.pi / 2, 0)
	local rust = rgb(96, 70, 52)
	local H = ctx.ceiling
	solid(ctx, "PumpBase", Vector3.new(9, 1.2, 5), base * CFrame.new(0, 0.6, 0), Enum.Material.Concrete, rgb(80, 82, 78))
	solid(ctx, "Pump", Vector3.new(7.5, 3.6, 3.6), base * CFrame.new(0, 3, 0), Enum.Material.CorrodedMetal, rgb(70, 92, 84), Enum.PartType.Cylinder)
	solid(ctx, "Motor", Vector3.new(3, 2.6, 2.6), base * CFrame.new(-4.6, 2.6, 0), Enum.Material.Metal, rgb(60, 60, 58))
	for _, sx in { -2.4, 2.4 } do
		deco(ctx, "Riser", Vector3.new(H - 4, 1.2, 1.2), base * CFrame.new(sx, (H + 4) / 2, 0) * UP, Enum.Material.CorrodedMetal, rust, Enum.PartType.Cylinder)
		-- valve wheel
		local wheel = base * CFrame.new(sx, 6, -0.9)
		deco(ctx, "ValveWheel", Vector3.new(0.15, 1.8, 1.8), wheel * CFrame.Angles(0, math.rad(90), 0), Enum.Material.Metal, rgb(140, 30, 26), Enum.PartType.Cylinder)
	end
	-- a railing round the pit
	for _, p in { { 0, -4.5, 11, 0.2 }, { 0, 4.5, 11, 0.2 } } do
		deco(ctx, "Rail", Vector3.new(p[3], 0.2, p[4]), base * CFrame.new(p[1], 3.3, p[2]), Enum.Material.Metal, rgb(150, 120, 30))
		for i = -2, 2 do
			deco(ctx, "RailPost", Vector3.new(0.2, 3.3, 0.2), base * CFrame.new(i * 2.6, 1.65, p[2]), Enum.Material.Metal, rgb(150, 120, 30))
		end
	end
	local panel = solid(ctx, "ControlPanel", Vector3.new(4, 5, 1), base * CFrame.new(0, 2.5, 7.5) * CFrame.Angles(0, math.pi, 0), Enum.Material.Metal, rgb(66, 70, 66))
	for i = 0, 2 do
		deco(ctx, "Gauge", Vector3.new(0.12, 0.9, 0.9), panel.CFrame * CFrame.new(-1.2 + i * 1.2, 1, -0.55) * CFrame.Angles(0, math.rad(90), 0), Enum.Material.SmoothPlastic, rgb(210, 205, 190), Enum.PartType.Cylinder)
	end
end

-- Night 3: a cistern, its roof held up by brick pillars standing in black water.
function Dressing.cistern(ctx: Ctx, block: { Cell })
	local c = Dressing.blockCenter(ctx, block)
	local H = ctx.ceiling
	local water = deco(ctx, "DeepWater", Vector3.new(ctx.C * 2 - 2, 0.1, ctx.C * 2 - 2), CFrame.new(c + Vector3.new(0, 0.3, 0)), Enum.Material.Glass, rgb(6, 14, 12))
	water.Reflectance = 0.5
	water.CastShadow = false
	for _, o in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		local p = c + Vector3.new(o[1] * ctx.C * 0.45, 0, o[2] * ctx.C * 0.45)
		solid(ctx, "Pillar", Vector3.new(2.4, H, 2.4), CFrame.new(p + Vector3.new(0, H / 2, 0)), Enum.Material.Brick, rgb(70, 72, 66))
		deco(ctx, "PillarCap", Vector3.new(3.2, 0.8, 3.2), CFrame.new(p + Vector3.new(0, H - 0.4, 0)), Enum.Material.Concrete, rgb(80, 82, 78))
	end
	for _ = 1, 4 do
		local s = ctx.random:NextNumber(0.8, 1.8)
		deco(ctx, "Debris", Vector3.new(s, s * 0.4, s * 1.6), CFrame.new(c + Vector3.new(ctx.random:NextNumber(-8, 8), 0.4, ctx.random:NextNumber(-8, 8))) * CFrame.Angles(0, ctx.random:NextNumber(0, 6), 0), Enum.Material.Wood, rgb(60, 50, 40))
	end
end

-- Night 4: a reflecting pool with a marble rim.
function Dressing.pool(ctx: Ctx, at: CFrame, w: number, d: number)
	local marble = Enum.Material.Marble
	local rim = rgb(214, 214, 210)
	solid(ctx, "PoolRim", Vector3.new(w + 1.2, 0.9, 0.6), at * CFrame.new(0, 0.45, -d / 2 - 0.3), marble, rim)
	solid(ctx, "PoolRim", Vector3.new(w + 1.2, 0.9, 0.6), at * CFrame.new(0, 0.45, d / 2 + 0.3), marble, rim)
	solid(ctx, "PoolRim", Vector3.new(0.6, 0.9, d), at * CFrame.new(-w / 2 - 0.3, 0.45, 0), marble, rim)
	solid(ctx, "PoolRim", Vector3.new(0.6, 0.9, d), at * CFrame.new(w / 2 + 0.3, 0.45, 0), marble, rim)
	local water = deco(ctx, "PoolWater", Vector3.new(w, 0.1, d), at * CFrame.new(0, 0.55, 0), Enum.Material.Glass, rgb(12, 16, 24))
	water.Reflectance = 0.55
	water.CastShadow = false
end

-- Night 4: a glass display case with something old inside.
function Dressing.displayCase(ctx: Ctx, at: CFrame)
	local marble = Enum.Material.Marble
	solid(ctx, "Plinth", Vector3.new(2.4, 3.4, 2.4), at * CFrame.new(0, 1.7, 0), marble, rgb(205, 205, 200))
	local glass = solid(ctx, "Case", Vector3.new(2.2, 2.4, 2.2), at * CFrame.new(0, 4.6, 0), Enum.Material.Glass, rgb(200, 210, 220))
	glass.Transparency = 0.8
	if ctx.random:NextNumber() < 0.5 then
		egg(deco(ctx, "Skull", Vector3.new(0.9, 1, 1.1), at * CFrame.new(0, 4, 0), Enum.Material.SmoothPlastic, rgb(214, 208, 192)))
		deco(ctx, "SkullJaw", Vector3.new(0.6, 0.25, 0.5), at * CFrame.new(0, 3.55, -0.3), Enum.Material.SmoothPlastic, rgb(200, 194, 178))
	else
		deco(ctx, "Vase", Vector3.new(1.8, 0.9, 0.9), at * CFrame.new(0, 4.3, 0) * UP, Enum.Material.Marble, rgb(60, 70, 90), Enum.PartType.Cylinder)
		deco(ctx, "VaseNeck", Vector3.new(0.6, 0.5, 0.5), at * CFrame.new(0, 5.4, 0) * UP, Enum.Material.Marble, rgb(60, 70, 90), Enum.PartType.Cylinder)
	end
end

-- Night 4: a long banner hanging from the far-away ceiling.
function Dressing.banner(ctx: Ctx, at: Vector3, yaw: number, color: Color3)
	local top = ctx.ceiling - 1
	local frame = CFrame.new(at.X, 0, at.Z) * CFrame.Angles(0, yaw, 0)
	deco(ctx, "BannerRod", Vector3.new(3, 0.25, 0.25), frame * CFrame.new(0, top, 0), Enum.Material.Metal, rgb(170, 140, 70), Enum.PartType.Cylinder)
	deco(ctx, "Banner", Vector3.new(2.4, 15, 0.08), frame * CFrame.new(0, top - 7.6, 0), Enum.Material.Fabric, color)
	deco(ctx, "BannerTip", Vector3.new(1.7, 1.7, 0.08), frame * CFrame.new(0, top - 15.1, 0) * CFrame.Angles(0, 0, math.rad(45)), Enum.Material.Fabric, color)
end

-- Night 4: moonlight falling through a skylight in a pale shaft.
function Dressing.moonShaft(ctx: Ctx, at: Vector3)
	local top = ctx.ceiling
	local sky = deco(ctx, "Skylight", Vector3.new(7, 0.3, 7), CFrame.new(at.X, top - 0.2, at.Z), Enum.Material.Neon, rgb(170, 190, 230))
	sky.CastShadow = false
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Bottom
	spot.Angle = 24
	spot.Range = top + 6
	spot.Brightness = 2.2
	spot.Color = rgb(190, 210, 255)
	spot.Shadows = true
	spot.Parent = sky
	local haze = deco(ctx, "LightShaft", Vector3.new(top, 7, 7), CFrame.new(at.X, top / 2, at.Z) * UP, Enum.Material.SmoothPlastic, rgb(200, 215, 255), Enum.PartType.Cylinder)
	haze.Transparency = 0.93
	haze.CastShadow = false
end

-- Night 5: something from an earlier night, floating in the dark.
function Dressing.floatingMemory(ctx: Ctx, at: Vector3)
	local r = ctx.random
	local cf = CFrame.new(at) * CFrame.Angles(r:NextNumber(-0.5, 0.5), r:NextNumber(0, 6.28), r:NextNumber(-0.5, 0.5))
	local kind = r:NextInteger(1, 5)
	local parts: { BasePart } = {}
	local function add(p: BasePart)
		table.insert(parts, p)
	end
	if kind == 1 then -- a bed
		add(deco(ctx, "MemoryBed", Vector3.new(4, 1.2, 7), cf, Enum.Material.Wood, rgb(40, 34, 30)))
		add(deco(ctx, "MemoryMattress", Vector3.new(3.6, 0.7, 6.6), cf * CFrame.new(0, 0.9, 0), Enum.Material.Fabric, rgb(120, 118, 114)))
	elseif kind == 2 then -- a gurney
		add(deco(ctx, "MemoryGurney", Vector3.new(2.6, 0.4, 6.4), cf, Enum.Material.Metal, rgb(110, 110, 112)))
		add(egg(deco(ctx, "MemorySheet", Vector3.new(2, 0.9, 5.6), cf * CFrame.new(0, 0.6, 0), Enum.Material.Fabric, rgb(140, 140, 136))))
	elseif kind == 3 then -- a locker
		add(deco(ctx, "MemoryLocker", Vector3.new(2.6, 7, 2.2), cf, Enum.Material.Metal, rgb(70, 72, 76)))
	elseif kind == 4 then -- a statue's head
		add(egg(deco(ctx, "MemoryHead", Vector3.new(2.6, 3.2, 2.8), cf, Enum.Material.Marble, rgb(170, 170, 166))))
		for _, sx in { -0.55, 0.55 } do
			add(deco(ctx, "MemoryEye", Vector3.new(0.6, 0.4, 0.3), cf * CFrame.new(sx, 0.3, -1.3), Enum.Material.SmoothPlastic, rgb(5, 5, 5)))
		end
	else -- a chair
		add(deco(ctx, "MemoryChair", Vector3.new(2, 0.3, 2), cf, Enum.Material.Wood, rgb(50, 42, 36)))
		add(deco(ctx, "MemoryChairBack", Vector3.new(2, 3, 0.3), cf * CFrame.new(0, 1.5, 0.85), Enum.Material.Wood, rgb(50, 42, 36)))
	end
	for _, p in parts do
		CollectionService:AddTag(p, "Float")
	end
end

-- Night 5: a room that remembers one of the earlier nights.
function Dressing.memoryRoom(ctx: Ctx, block: { Cell }, which: number, cell: Cell?)
	local c = Dressing.blockCenter(ctx, block)
	local base = CFrame.new(c) * CFrame.Angles(0, ctx.random:NextNumber(0, 6.28), 0)
	local dim = rgb(110, 106, 120)
	if which == 1 then
		-- the bed you woke up in
		solid(ctx, "BedFrame", Vector3.new(6, 1.6, 8), base * CFrame.new(0, 0.8, 0), Enum.Material.Wood, rgb(36, 30, 28))
		solid(ctx, "Mattress", Vector3.new(5.6, 0.9, 7.4), base * CFrame.new(0, 2.05, 0.2), Enum.Material.Fabric, dim)
		solid(ctx, "Headboard", Vector3.new(6, 4.2, 0.5), base * CFrame.new(0, 2.1, -4.1), Enum.Material.Wood, rgb(36, 30, 28))
		deco(ctx, "Rug", Vector3.new(9, 0.08, 7), base * CFrame.new(0, 0.04, 6), Enum.Material.Fabric, rgb(40, 36, 46))
	elseif which == 2 then
		-- a hospital bed and its curtain
		solid(ctx, "BedFrame", Vector3.new(3.4, 2.2, 7), base * CFrame.new(0, 1.1, 0), Enum.Material.Metal, rgb(90, 90, 96))
		egg(deco(ctx, "Body", Vector3.new(2, 1, 6), base * CFrame.new(0, 2.6, 0), Enum.Material.Fabric, dim))
		local curtain = deco(ctx, "Curtain", Vector3.new(0.1, 7.5, 6), base * CFrame.new(2.6, 3.75, 0), Enum.Material.Fabric, rgb(80, 90, 96))
		curtain.Transparency = 0.3
	else
		-- a plinth with nothing on it
		solid(ctx, "Plinth", Vector3.new(3, 4, 3), base * CFrame.new(0, 2, 0), Enum.Material.Marble, rgb(120, 120, 124))
		ctx.sign(base * CFrame.new(0, 2.6, -1.55), Vector2.new(2.4, 0.8), "IT LEFT", rgb(30, 30, 34), rgb(150, 150, 154), false, Enum.Font.Fondamento)
	end
	-- one cold light over it, like a memory
	local hang = math.min(ctx.ceiling, ctx.H) - 1
	deco(ctx, "MemoryCord", Vector3.new(0.08, ctx.ceiling - hang, 0.08), base * CFrame.new(0, (ctx.ceiling + hang) / 2, 0), Enum.Material.SmoothPlastic, rgb(10, 10, 12))
	local bulb = deco(ctx, "MemoryLight", Vector3.new(0.6, 0.6, 0.6), base * CFrame.new(0, hang, 0), Enum.Material.Neon, rgb(150, 140, 190), Enum.PartType.Ball)
	bulb.CastShadow = false
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Bottom
	spot.Angle = 70
	spot.Range = hang + 8
	spot.Brightness = 1.4
	spot.Color = rgb(170, 160, 220)
	spot.Shadows = true
	spot.Parent = bulb
	ctx.addLamp(bulb, spot, cell)
end

return Dressing
