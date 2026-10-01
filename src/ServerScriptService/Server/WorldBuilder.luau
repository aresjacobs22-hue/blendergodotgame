--!strict
-- Turns a Maze layout into Parts: the grey house, the concrete maze, lamps, props,
-- scrawled writing, and the exit tunnel. Interactive things (doors, keys, lockers,
-- the exit door) are added afterwards by Interactables.

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Maze = require(ReplicatedStorage.Shared.Maze)

type Layout = Maze.Layout

export type Note = { part: BasePart, text: string }

export type World = {
	model: Model,
	spawnPoints: { CFrame },
	houseOrigin: Vector3,
	escapeZone: BasePart,
	exitLight: PointLight,
	hiddenSpot: CFrame,
	notes: { Note },
	random: Random,
}

type Style = { material: Enum.Material, color: Color3 }

local C = Config.Maze.CellSize
local H = Config.Maze.WallHeight
local T = Config.Maze.WallThickness
local ROT90 = CFrame.Angles(0, math.rad(90), 0)

local WorldBuilder = {}

WorldBuilder.DOOR_WIDTH = 5.5
WorldBuilder.DOOR_HEIGHT = 10
WorldBuilder.EXIT_WIDTH = 7
WorldBuilder.EXIT_HEIGHT = 10.5
local HOLE_WIDTH = 6
local HOLE_HEIGHT = 9.5

local MAZE_WALL: Style = { material = Enum.Material.Concrete, color = Color3.fromRGB(118, 116, 112) }
local HOUSE_WALL: Style = { material = Enum.Material.Plaster, color = Color3.fromRGB(170, 164, 154) }
local TRIM: Style = { material = Enum.Material.Wood, color = Color3.fromRGB(70, 58, 50) }

local ROOM_FLOORS: { [string]: Style } = {
	hall = { material = Enum.Material.WoodPlanks, color = Color3.fromRGB(88, 74, 62) },
	living = { material = Enum.Material.WoodPlanks, color = Color3.fromRGB(98, 82, 68) },
	bedroom = { material = Enum.Material.Carpet, color = Color3.fromRGB(78, 76, 80) },
	kitchen = { material = Enum.Material.CeramicTiles, color = Color3.fromRGB(150, 150, 146) },
	study = { material = Enum.Material.WoodPlanks, color = Color3.fromRGB(80, 68, 58) },
}

local random = Random.new()

-- The monster walks through furniture (its paths cut through the middle of rooms);
-- players, line of sight and flashlight shadows still treat furniture as solid.
local groupsReady = false
function WorldBuilder.setupCollisionGroups()
	if groupsReady then
		return
	end
	groupsReady = true
	PhysicsService:RegisterCollisionGroup("Monster")
	PhysicsService:RegisterCollisionGroup("Furniture")
	PhysicsService:CollisionGroupSetCollidable("Monster", "Furniture", false)
end

function WorldBuilder.markFurniture(root: Instance)
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = "Furniture"
		end
	end
end

local function vary(color: Color3, amount: number?): Color3
	local f = 1 + random:NextNumber(-1, 1) * (amount or 0.06)
	return Color3.new(math.clamp(color.R * f, 0, 1), math.clamp(color.G * f, 0, 1), math.clamp(color.B * f, 0, 1))
end

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	material: Enum.Material,
	color: Color3,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Material = material
	p.Color = color
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end
WorldBuilder.part = part

-- Decorative parts that should never block movement or line of sight.
local function decor(p: BasePart): BasePart
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	return p
end
WorldBuilder.decor = decor

-- Frame on the edge an owner cell holds ("N" or "E"). Its Front face (-Z) looks into
-- the owner cell, its Back face into the neighbour. Y = floor level.
function WorldBuilder.edgeFrame(x: number, z: number, dir: string): CFrame
	if dir == "N" then
		return CFrame.new((x + 0.5) * C, 0, (z + 1) * C)
	end
	return CFrame.new((x + 1) * C, 0, (z + 0.5) * C) * ROT90
end

-- Frame on the inside face of one of a cell's walls, looking into the cell.
function WorldBuilder.sideFrame(x: number, z: number, side: string): CFrame
	local ox, oz = Maze.DX[side], Maze.DZ[side]
	local pos = Vector3.new((x + 0.5 + ox * 0.5) * C - ox * T / 2, 0, (z + 0.5 + oz * 0.5) * C - oz * T / 2)
	return CFrame.lookAt(pos, pos - Vector3.new(ox, 0, oz))
end

function WorldBuilder.cellCenter(x: number, z: number): Vector3
	return Vector3.new((x + 0.5) * C, 0, (z + 0.5) * C)
end

local function styleOf(layout: Layout, x: number, z: number): Style
	if Maze.inBounds(layout, x, z) and Maze.isHouse(layout, x, z) then
		return HOUSE_WALL
	end
	return MAZE_WALL
end

-- A slab of wall along an edge frame. Walls between the house and the maze are two
-- half-thickness layers so each side gets its own material.
local function wallBox(parent: Instance, frame: CFrame, length: number, height: number, yBottom: number, xOffset: number, front: Style, back: Style)
	if length <= 0.05 or height <= 0.05 then
		return
	end
	local y = yBottom + height / 2
	if front == back then
		part(parent, "Wall", Vector3.new(length, height, T), frame * CFrame.new(xOffset, y, 0), front.material, vary(front.color))
	else
		part(parent, "Wall", Vector3.new(length, height, T / 2), frame * CFrame.new(xOffset, y, -T / 4), front.material, vary(front.color))
		part(parent, "Wall", Vector3.new(length, height, T / 2), frame * CFrame.new(xOffset, y, T / 4), back.material, vary(back.color))
	end
end

local function wallWithOpening(parent: Instance, frame: CFrame, width: number, height: number, front: Style, back: Style)
	local length = C - T
	local side = (length - width) / 2
	wallBox(parent, frame, side, H, 0, -(width + side) / 2, front, back)
	wallBox(parent, frame, side, H, 0, (width + side) / 2, front, back)
	wallBox(parent, frame, width, H - height, height, 0, front, back)
end

local function doorTrim(parent: Instance, frame: CFrame, width: number, height: number)
	local depth = T + 0.3
	for _, sx in { -1, 1 } do
		part(parent, "Trim", Vector3.new(0.45, height, depth), frame * CFrame.new(sx * (width / 2 + 0.2), height / 2, 0), TRIM.material, TRIM.color)
	end
	part(parent, "Trim", Vector3.new(width + 0.85, 0.45, depth), frame * CFrame.new(0, height + 0.2, 0), TRIM.material, TRIM.color)
end

local function brokenWall(parent: Instance, frame: CFrame, front: Style, back: Style)
	wallWithOpening(parent, frame, HOLE_WIDTH, HOLE_HEIGHT, front, back)
	-- jagged chunks hanging into the opening
	for _ = 1, 5 do
		local sx = if random:NextNumber() < 0.5 then -1 else 1
		local size = Vector3.new(random:NextNumber(0.6, 1.6), random:NextNumber(0.8, 2.4), T * 0.9)
		local y = random:NextNumber(0.5, HOLE_HEIGHT)
		local p = part(
			parent,
			"Chunk",
			size,
			frame * CFrame.new(sx * (HOLE_WIDTH / 2 - size.X / 2 + 0.3), y, 0) * CFrame.Angles(0, 0, random:NextNumber(-0.5, 0.5)),
			MAZE_WALL.material,
			vary(MAZE_WALL.color)
		)
		p.CanCollide = false
	end
	part(parent, "Chunk", Vector3.new(HOLE_WIDTH + 0.5, 1.2, T * 0.9), frame * CFrame.new(0, HOLE_HEIGHT - 0.2, 0) * CFrame.Angles(0, 0, random:NextNumber(-0.15, 0.15)), MAZE_WALL.material, vary(MAZE_WALL.color)).CanCollide = false
	-- rubble on both sides
	for _ = 1, 9 do
		local s = random:NextNumber(0.4, 1.3)
		local p = part(
			parent,
			"Rubble",
			Vector3.new(s, s * 0.6, s * random:NextNumber(0.7, 1.3)),
			frame * CFrame.new(random:NextNumber(-HOLE_WIDTH, HOLE_WIDTH) * 0.6, s * 0.25, random:NextNumber(-3, 3)) * CFrame.Angles(random:NextNumber(-0.4, 0.4), random:NextNumber(0, 6.28), random:NextNumber(-0.4, 0.4)),
			MAZE_WALL.material,
			vary(MAZE_WALL.color, 0.15)
		)
		decor(p)
	end
end

local function buildEdges(layout: Layout, parent: Instance)
	local W, D = layout.width, layout.depth
	for z = -1, D - 1 do
		for x = -1, W - 1 do
			for _, dir in { "N", "E" } do
				local valid = if dir == "N" then (x >= 0 and x < W) else (z >= 0 and z < D)
				if valid then
					local kind = Maze.getEdge(layout, x, z, dir)
					local nx, nz = x + Maze.DX[dir], z + Maze.DZ[dir]
					local front, back = styleOf(layout, x, z), styleOf(layout, nx, nz)
					local frame = WorldBuilder.edgeFrame(x, z, dir)
					if kind == "wall" then
						wallBox(parent, frame, C - T, H, 0, 0, front, back)
					elseif kind == "door" or kind == "doorway" then
						wallWithOpening(parent, frame, WorldBuilder.DOOR_WIDTH, WorldBuilder.DOOR_HEIGHT, front, back)
						doorTrim(parent, frame, WorldBuilder.DOOR_WIDTH, WorldBuilder.DOOR_HEIGHT)
					elseif kind == "exit" then
						wallWithOpening(parent, frame, WorldBuilder.EXIT_WIDTH, WorldBuilder.EXIT_HEIGHT, front, back)
						doorTrim(parent, frame, WorldBuilder.EXIT_WIDTH, WorldBuilder.EXIT_HEIGHT)
					elseif kind == "hole" then
						brokenWall(parent, frame, front, back)
					end
				end
			end
		end
	end
end

local function buildPillars(layout: Layout, parent: Instance)
	local W, D = layout.width, layout.depth
	for j = 0, D do
		for i = 0, W do
			local needed = false
			-- horizontal edges meeting at this vertex
			for _, ex in { i - 1, i } do
				if ex >= 0 and ex < W and Maze.getEdge(layout, ex, j - 1, "N") ~= "open" then
					needed = true
				end
			end
			-- vertical edges meeting at this vertex
			for _, ez in { j - 1, j } do
				if ez >= 0 and ez < D and Maze.getEdge(layout, i - 1, ez, "E") ~= "open" then
					needed = true
				end
			end
			if needed then
				local houseCount = 0
				for _, c in { { i - 1, j - 1 }, { i, j - 1 }, { i - 1, j }, { i, j } } do
					if Maze.inBounds(layout, c[1], c[2]) and Maze.isHouse(layout, c[1], c[2]) then
						houseCount += 1
					end
				end
				local style = if houseCount >= 2 then HOUSE_WALL else MAZE_WALL
				part(parent, "Pillar", Vector3.new(T + 0.5, H, T + 0.5), CFrame.new(i * C, H / 2, j * C), style.material, vary(style.color, 0.1))
			end
		end
	end
end

local function lamp(parent: Instance, position: Vector3, brightness: number, range: number, hanging: boolean, buzz: boolean): BasePart
	local bulbY = if hanging then H - 3.2 else H - 0.45
	if hanging then
		decor(part(parent, "Cord", Vector3.new(0.12, H - bulbY, 0.12), CFrame.new(position.X, (H + bulbY) / 2, position.Z), Enum.Material.Plastic, Color3.fromRGB(20, 20, 20)))
		decor(part(parent, "Shade", Vector3.new(2.2, 0.9, 2.2), CFrame.new(position.X, bulbY + 0.55, position.Z), Enum.Material.Fabric, Color3.fromRGB(120, 116, 110)))
	else
		decor(part(parent, "LampBase", Vector3.new(2.8, 0.3, 2.8), CFrame.new(position.X, H - 0.15, position.Z), Enum.Material.Metal, Color3.fromRGB(45, 45, 45)))
	end
	local bulb = decor(part(parent, "Bulb", if hanging then Vector3.new(0.9, 0.9, 0.9) else Vector3.new(1.5, 0.35, 1.5), CFrame.new(position.X, bulbY, position.Z), Enum.Material.Neon, Color3.fromRGB(215, 212, 200), if hanging then Enum.PartType.Ball else nil))
	bulb.CastShadow = false
	local light = Instance.new("PointLight")
	light.Range = range
	light.Brightness = brightness
	light.Color = Color3.fromRGB(255, 240, 220)
	light.Shadows = true
	light.Parent = bulb
	bulb:SetAttribute("BaseBrightness", brightness)
	bulb:SetAttribute("Buzz", buzz)
	CollectionService:AddTag(bulb, "FlickerLight")
	return bulb
end

local function writing(parent: Instance, frame: CFrame, text: string)
	local canvas = decor(part(parent, "Writing", Vector3.new(9, 4.4, 0.05), frame, Enum.Material.SmoothPlastic, Color3.new(0, 0, 0)))
	canvas.Transparency = 1
	canvas.CastShadow = false
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 1 -- only readable when lit, i.e. by your flashlight
	gui.Parent = canvas
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.Creepster
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(28, 22, 22)
	label.TextTransparency = random:NextNumber(0.05, 0.25)
	label.Rotation = random:NextNumber(-7, 7)
	label.Parent = gui
end

-- A portrait whose face is drawn with UI frames: pale oval, hollow black eyes.
local function portrait(parent: Instance, frame: CFrame)
	part(parent, "PortraitFrame", Vector3.new(3.6, 4.6, 0.3), frame * CFrame.new(0, 0, -0.15), Enum.Material.Wood, Color3.fromRGB(45, 36, 30))
	local canvas = decor(part(parent, "Portrait", Vector3.new(3, 4, 0.05), frame * CFrame.new(0, 0, -0.33), Enum.Material.SmoothPlastic, Color3.fromRGB(38, 38, 38)))
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 1
	gui.Parent = canvas
	local function blob(name: string, pos: UDim2, size: UDim2, color: Color3)
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
	blob("Body", UDim2.fromScale(0.5, 1.05), UDim2.fromScale(0.95, 0.5), Color3.fromRGB(20, 20, 20))
	local face = blob("Face", UDim2.fromScale(0.5, 0.42), UDim2.fromScale(0.5, 0.5), Color3.fromRGB(205, 200, 190))
	face.Rotation = random:NextNumber(-8, 8)
	blob("EyeL", UDim2.fromScale(0.41, 0.38), UDim2.fromScale(0.11, 0.09), Color3.new(0, 0, 0))
	blob("EyeR", UDim2.fromScale(0.59, 0.38), UDim2.fromScale(0.11, 0.09), Color3.new(0, 0, 0))
	blob("Mouth", UDim2.fromScale(0.5, 0.55), UDim2.fromScale(0.16, 0.12), Color3.new(0, 0, 0))
end

local function buildHouseProps(layout: Layout, parent: Instance, notes: { Note })
	local O = Vector3.new(layout.house.x0 * C, 0, layout.house.z0 * C)

	local function box(name: string, size: Vector3, x: number, yBottom: number, z: number, material: Enum.Material, color: Color3, rotY: number?): Part
		return part(parent, name, size, CFrame.new(O + Vector3.new(x, yBottom + size.Y / 2, z)) * CFrame.Angles(0, rotY or 0, 0), material, color)
	end
	local function wallFrame(x: number, y: number, z: number, facing: Vector3): CFrame
		local pos = O + Vector3.new(x, y, z)
		return CFrame.lookAt(pos, pos + facing)
	end
	local function note(x: number, y: number, z: number, text: string)
		local p = box("Note", Vector3.new(1.3, 0.05, 1.7), x, y, z, Enum.Material.SmoothPlastic, Color3.fromRGB(215, 210, 196), random:NextNumber(-0.4, 0.4))
		p.CanCollide = false
		table.insert(notes, { part = p :: BasePart, text = text })
	end

	local wood = Enum.Material.Wood
	local darkWood = Color3.fromRGB(62, 50, 42)
	local fabric = Enum.Material.Fabric

	-- Bedroom (x 0..24, z 24..36): you wake up here.
	box("BedFrame", Vector3.new(6, 1.6, 8), 3.6, 0, 29.1, wood, darkWood)
	box("Headboard", Vector3.new(6, 4.2, 0.5), 3.6, 0, 24.85, wood, darkWood)
	box("Mattress", Vector3.new(5.6, 0.9, 7.4), 3.6, 1.6, 29.3, fabric, Color3.fromRGB(196, 194, 188))
	box("Pillow", Vector3.new(3.6, 0.6, 1.5), 3.6, 2.5, 26.2, fabric, Color3.fromRGB(220, 218, 214))
	box("Blanket", Vector3.new(5.8, 0.3, 4.6), 3.7, 2.5, 31.0, fabric, Color3.fromRGB(70, 70, 78), 0.06)
	box("Nightstand", Vector3.new(2.2, 2.4, 2), 8, 0, 25.6, wood, darkWood)
	box("BrokenLamp", Vector3.new(0.6, 1.3, 0.6), 8.4, 2.4, 25.4, Enum.Material.Metal, Color3.fromRGB(80, 80, 80), 0.3)
	note(7.7, 2.4, 25.9, "If you're reading this, you woke up here too.\nThere's no color anymore. Find the 4 KEYS out in the halls.\nEach key has a tag with a number. The door in the hall wants all of it.")
	-- a chair facing the corner
	box("ChairSeat", Vector3.new(2.2, 0.35, 2.2), 21.4, 2.1, 33.6, wood, darkWood, math.rad(45))
	box("ChairBack", Vector3.new(2.2, 3.2, 0.3), 22.2, 2.45, 34.4, wood, darkWood, math.rad(45))
	for _, l in { { 20.7, 33.6 }, { 21.4, 32.9 }, { 22.1, 33.6 }, { 21.4, 34.3 } } do
		box("ChairLeg", Vector3.new(0.3, 2.1, 0.3), l[1], 0, l[2], wood, darkWood)
	end
	portrait(parent, wallFrame(18, 6.2, 35.5, Vector3.new(0, 0, -1)))

	-- Living room (x 0..24, z 0..24)
	local couch = Color3.fromRGB(104, 100, 96)
	box("CouchBase", Vector3.new(3.6, 2, 9), 2.9, 0, 12, fabric, couch)
	box("CouchBack", Vector3.new(1.2, 4.2, 9), 1.1, 0, 12, fabric, couch)
	box("CouchArm", Vector3.new(3.6, 3, 1), 2.9, 0, 7, fabric, couch)
	box("CouchArm", Vector3.new(3.6, 3, 1), 2.9, 0, 17, fabric, couch)
	decor(box("Rug", Vector3.new(10, 0.1, 8), 8, 0.05, 12, fabric, Color3.fromRGB(56, 56, 60)))
	box("CoffeeTable", Vector3.new(3, 1.6, 5), 8.5, 0, 12, wood, darkWood)
	box("TVStand", Vector3.new(2.4, 2.4, 6.4), 22.2, 0, 6, wood, darkWood)
	box("TV", Vector3.new(1, 3.4, 5.4), 22.5, 2.4, 6, Enum.Material.SmoothPlastic, Color3.fromRGB(16, 16, 16))
	local screen = decor(part(parent, "Screen", Vector3.new(4.8, 2.9, 0.05), wallFrame(21.95, 4.1, 6, Vector3.new(-1, 0, 0)), Enum.Material.Neon, Color3.fromRGB(46, 46, 46)))
	local tvGui = Instance.new("SurfaceGui")
	tvGui.Face = Enum.NormalId.Front
	tvGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	tvGui.PixelsPerStud = 40
	tvGui.Parent = screen
	local tvText = Instance.new("TextLabel")
	tvText.BackgroundTransparency = 1
	tvText.Size = UDim2.fromScale(1, 1)
	tvText.Font = Enum.Font.SpecialElite
	tvText.Text = "NO SIGNAL\n\nSTAY ASLEEP"
	tvText.TextScaled = true
	tvText.TextColor3 = Color3.fromRGB(150, 150, 150)
	tvText.Parent = tvGui
	local tvLight = Instance.new("PointLight")
	tvLight.Range = 10
	tvLight.Brightness = 0.6
	tvLight.Shadows = true
	tvLight.Parent = screen
	screen:SetAttribute("BaseBrightness", 0.6)
	CollectionService:AddTag(screen, "FlickerLight")
	box("Bookshelf", Vector3.new(8, 9, 2), 12, 0, 1.55, wood, darkWood)
	for shelf = 0, 2 do
		local x = 8.6
		while x < 15.2 do
			local w = random:NextNumber(0.35, 0.8)
			local h = random:NextNumber(1.4, 2.2)
			box("Book", Vector3.new(w, h, 1.4), x + w / 2, 1 + shelf * 2.8, 2.0, Enum.Material.Fabric, vary(Color3.fromRGB(110, 104, 98), 0.4))
			x += w + random:NextNumber(0.02, 0.4)
		end
	end
	portrait(parent, wallFrame(0.5, 7, 12, Vector3.new(1, 0, 0)))

	-- Hall (x 24..36, z 0..36)
	box("ClockBody", Vector3.new(1.8, 8.6, 1.6), 25.4, 0, 8, wood, darkWood)
	decor(part(parent, "ClockFace", Vector3.new(1.3, 1.3, 0.05), wallFrame(26.33, 6.8, 8, Vector3.new(1, 0, 0)), Enum.Material.SmoothPlastic, Color3.fromRGB(200, 196, 186), Enum.PartType.Block))
	box("CoatRack", Vector3.new(0.4, 7, 0.4), 25.6, 0, 2.2, wood, darkWood)
	decor(box("Runner", Vector3.new(4, 0.1, 30), 30, 0.05, 18, fabric, Color3.fromRGB(60, 58, 58)))
	portrait(parent, wallFrame(24.5, 6.5, 24, Vector3.new(1, 0, 0)))
	portrait(parent, wallFrame(35.5, 6.5, 6, Vector3.new(-1, 0, 0)))

	-- Kitchen (x 36..60, z 0..24)
	box("Counter", Vector3.new(18, 3.4, 2.6), 47, 0, 1.8, wood, Color3.fromRGB(150, 146, 140))
	box("Countertop", Vector3.new(18.4, 0.3, 2.9), 47, 3.4, 1.8, Enum.Material.Marble, Color3.fromRGB(200, 200, 195))
	box("Cabinets", Vector3.new(18, 3, 1.6), 47, 7.2, 1.3, wood, Color3.fromRGB(140, 136, 130))
	box("Fridge", Vector3.new(3.2, 7.5, 3), 57.9, 0, 14, Enum.Material.Metal, Color3.fromRGB(186, 186, 186))
	box("TableTop", Vector3.new(6, 0.3, 4), 46, 2.9, 13, wood, darkWood)
	for _, l in { { 43.4, 11.4 }, { 48.6, 11.4 }, { 43.4, 14.6 }, { 48.6, 14.6 } } do
		box("TableLeg", Vector3.new(0.3, 2.9, 0.3), l[1], 0, l[2], wood, darkWood)
	end
	box("KitchenChair", Vector3.new(2, 2, 2), 46, 0, 16.2, wood, darkWood)
	box("KitchenChair", Vector3.new(2, 2, 2), 41.6, 0, 13, wood, darkWood, math.rad(70)) -- knocked askew
	note(46.5, 3.2, 13, "The lockers saved me twice.\nThe third time it WATCHED me get in.\nIf it's chasing you, break line of sight first.")

	-- Study (x 36..60, z 24..36)
	box("Desk", Vector3.new(6, 3, 2.6), 42, 0, 34.2, wood, darkWood)
	box("DeskChair", Vector3.new(2, 2, 2), 42, 0, 31.6, wood, darkWood)
	box("Bookshelf", Vector3.new(2, 9, 8), 58.5, 0, 30, wood, darkWood)
	note(41.2, 3, 34.0, "Day 14.\nIt doesn't see well in the dark, but it HEARS everything.\nWalk. Crouch. Only run when it's already running at you.\nAnd it likes the light. Turn yours off when it's close.")
	portrait(parent, wallFrame(42, 6.5, 24.5, Vector3.new(0, 0, 1)))
end

local function buildMazeProps(layout: Layout, parent: Instance)
	local keyCells: { [string]: boolean } = {}
	for _, k in layout.keys do
		keyCells[Maze.key(k.x, k.z)] = true
	end
	for z = 0, layout.depth - 1 do
		for x = 0, layout.width - 1 do
			if not Maze.isHouse(layout, x, z) then
				local center = WorldBuilder.cellCenter(x, z)
				-- pipes along a wall, up near the ceiling
				if random:NextNumber() < 0.3 then
					for _, side in Maze.DIRS do
						if Maze.getEdge(layout, x, z, side) == "wall" then
							local f = WorldBuilder.sideFrame(x, z, side)
							decor(part(parent, "Pipe", Vector3.new(C - T, 0.8, 0.8), f * CFrame.new(0, H - 1.6, -0.6), Enum.Material.CorrodedMetal, vary(Color3.fromRGB(96, 96, 96), 0.2), Enum.PartType.Cylinder))
							if random:NextNumber() < 0.5 then
								decor(part(parent, "Pipe", Vector3.new(C - T, 0.45, 0.45), f * CFrame.new(0, H - 2.6, -0.45), Enum.Material.Metal, vary(Color3.fromRGB(70, 70, 70), 0.2), Enum.PartType.Cylinder))
							end
							break
						end
					end
				end
				-- black puddles that catch the flashlight
				if random:NextNumber() < 0.16 then
					local p = decor(part(parent, "Puddle", Vector3.new(random:NextNumber(3, 6), 0.04, random:NextNumber(3, 6)), CFrame.new(center + Vector3.new(random:NextNumber(-2, 2), 0.03, random:NextNumber(-2, 2))) * CFrame.Angles(0, random:NextNumber(0, 6.28), 0), Enum.Material.Glass, Color3.fromRGB(18, 18, 18)))
					p.Transparency = 0.3
					p.Reflectance = 0.3
					p.CastShadow = false
				end
				-- clutter in dead ends that don't hold a key
				if Maze.passableCount(layout, x, z) == 1 and not keyCells[Maze.key(x, z)] and random:NextNumber() < 0.6 then
					for _, side in Maze.DIRS do
						if Maze.getEdge(layout, x, z, side) == "wall" then
							local f = WorldBuilder.sideFrame(x, z, side)
							for i = 1, random:NextInteger(1, 3) do
								local s = random:NextNumber(1.8, 3)
								part(parent, "Crate", Vector3.new(s, s, s), f * CFrame.new(random:NextNumber(-3.5, 3.5), s / 2 + (if i == 3 then 2.4 else 0), -s / 2 - 0.2) * CFrame.Angles(0, random:NextNumber(-0.3, 0.3), 0), Enum.Material.WoodPlanks, vary(Color3.fromRGB(90, 80, 70), 0.2))
							end
							break
						end
					end
				end
			end
		end
	end
end

local function buildExitTunnel(layout: Layout, parent: Instance): (BasePart, PointLight)
	local x = (layout.exitCell.x + 0.5) * C
	local width = WorldBuilder.EXIT_WIDTH + 2
	local length = 28
	local zMid = -length / 2
	part(parent, "TunnelFloor", Vector3.new(width + 2, 1, length), CFrame.new(x, -0.5, zMid), Enum.Material.Concrete, Color3.fromRGB(60, 60, 60))
	part(parent, "TunnelCeiling", Vector3.new(width + 2, 1, length), CFrame.new(x, H + 0.5, zMid), Enum.Material.Concrete, Color3.fromRGB(40, 40, 40))
	for _, sx in { -1, 1 } do
		part(parent, "TunnelWall", Vector3.new(1, H, length), CFrame.new(x + sx * (width / 2 + 0.5), H / 2, zMid), MAZE_WALL.material, MAZE_WALL.color)
	end
	local glow = part(parent, "TheOutside", Vector3.new(width + 2, H, 0.5), CFrame.new(x, H / 2, -length), Enum.Material.Neon, Color3.fromRGB(255, 255, 255))
	glow.CastShadow = false
	local light = Instance.new("PointLight")
	light.Range = 45
	light.Brightness = 4
	light.Shadows = true
	light.Enabled = false -- switched on when the exit opens
	light.Parent = glow
	local zone = decor(part(parent, "EscapeZone", Vector3.new(width, 12, 2), CFrame.new(x, 6, -12), Enum.Material.SmoothPlastic, Color3.new(1, 1, 1)))
	zone.CanTouch = true
	zone.Transparency = 1
	return zone, light
end

function WorldBuilder.build(layout: Layout): World
	random = Random.new(layout.seed)

	local model = Instance.new("Model")
	model.Name = "World"

	local structure = Instance.new("Folder")
	structure.Name = "Structure"
	structure.Parent = model
	local props = Instance.new("Folder")
	props.Name = "Props"
	props.Parent = model
	local lights = Instance.new("Folder")
	lights.Name = "Lights"
	lights.Parent = model

	local W, D = layout.width, layout.depth

	-- floor + ceiling
	part(structure, "Floor", Vector3.new(W * C + 2, 1, D * C + 2), CFrame.new(W * C / 2, -0.5, D * C / 2), Enum.Material.Slate, Color3.fromRGB(54, 54, 54))
	part(structure, "Ceiling", Vector3.new(W * C + 2, 1, D * C + 2), CFrame.new(W * C / 2, H + 0.5, D * C / 2), Enum.Material.Concrete, Color3.fromRGB(42, 42, 42))
	for key, room in layout.rooms do
		local xs, zs = string.match(key, "^(%-?%d+),(%-?%d+)$")
		local cx, cz = tonumber(xs) :: number, tonumber(zs) :: number
		local floorStyle = ROOM_FLOORS[room]
		part(structure, "HouseFloor", Vector3.new(C, 1, C), CFrame.new((cx + 0.5) * C, -0.45, (cz + 0.5) * C), floorStyle.material, floorStyle.color)
		part(structure, "HouseCeiling", Vector3.new(C, 1, C), CFrame.new((cx + 0.5) * C, H + 0.45, (cz + 0.5) * C), Enum.Material.Plaster, Color3.fromRGB(128, 126, 122))
	end

	buildEdges(layout, structure)
	buildPillars(layout, structure)

	-- maze lamps (some buzz) + one lamp per house room
	for _, c in layout.lights do
		lamp(lights, WorldBuilder.cellCenter(c.x, c.z), random:NextNumber(1.1, 1.7), 20, false, random:NextNumber() < 0.4)
	end
	local O = Vector3.new(layout.house.x0 * C, 0, layout.house.z0 * C)
	for _, spot in { { 12, 12, 1.3 }, { 48, 12, 1.4 }, { 12, 30, 0.8 }, { 48, 30, 1.0 }, { 30, 18, 1.2 }, { 30, 5, 0.9 } } do
		lamp(lights, O + Vector3.new(spot[1], 0, spot[2]), spot[3], 24, true, false)
	end

	for _, w in layout.writings do
		writing(props, WorldBuilder.sideFrame(w.x, w.z, w.side) * CFrame.new(random:NextNumber(-1.2, 1.2), random:NextNumber(5, 7), -0.1), w.text)
	end

	local notes: { Note } = {}
	buildHouseProps(layout, props, notes)
	buildMazeProps(layout, props)
	WorldBuilder.setupCollisionGroups()
	WorldBuilder.markFurniture(props)
	local escapeZone, exitLight = buildExitTunnel(layout, structure)

	-- spawn spots in the bedroom, facing the bedroom door
	local spawnPoints = {}
	for _, s in { { 10, 33.5 }, { 13, 33.5 }, { 10, 29.5 }, { 13, 29.5 }, { 16, 33.5 }, { 16, 30.5 } } do
		local pos = O + Vector3.new(s[1], 3.5, s[2])
		table.insert(spawnPoints, CFrame.lookAt(pos, pos + Vector3.new(1, 0, 0)))
	end

	model.Parent = workspace

	return {
		model = model,
		spawnPoints = spawnPoints,
		houseOrigin = O,
		escapeZone = escapeZone,
		exitLight = exitLight,
		hiddenSpot = CFrame.new(W * C / 2, -300, D * C / 2),
		notes = notes,
		random = random,
	}
end

return WorldBuilder
