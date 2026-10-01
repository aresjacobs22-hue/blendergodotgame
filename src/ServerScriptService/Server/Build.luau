--!strict
-- Building blocks shared by every map theme: parts, wall slabs, doorways, lamps,
-- signs, notes, writing. One context per map build (cell size and wall height vary
-- per night).

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Maze = require(ReplicatedStorage.Shared.Maze)
local Nights = require(ReplicatedStorage.Shared.Nights)

export type Style = { material: Enum.Material, color: Color3, reflect: number? }
export type Lamp = { bulb: BasePart, light: Light, cell: Maze.Cell? }

export type Ctx = {
	layout: Maze.Layout,
	night: Nights.Night,
	C: number, -- cell size
	H: number, -- wall height
	ceiling: number, -- ceiling height
	T: number, -- wall thickness
	doorWidth: number,
	doorHeight: number,
	exitWidth: number,
	exitHeight: number,
	random: Random,
	structure: Folder,
	props: Folder,
	lights: Folder,
	lamps: { Lamp },
	hubOrigin: Vector3, -- world position of the hub's south-west corner

	part: (parent: Instance, name: string, size: Vector3, cframe: CFrame, material: Enum.Material, color: Color3, shape: Enum.PartType?) -> Part,
	decor: (p: BasePart) -> BasePart,
	vary: (color: Color3, amount: number?) -> Color3,
	styled: (parent: Instance, name: string, size: Vector3, cframe: CFrame, style: Style) -> Part,
	edgeFrame: (x: number, z: number, dir: string) -> CFrame,
	sideFrame: (x: number, z: number, side: string) -> CFrame,
	cellCenter: (x: number, z: number) -> Vector3,
	wallSides: (x: number, z: number) -> { string },
	sign: (frame: CFrame, size: Vector2, text: string, textColor: Color3, background: Color3?, glow: boolean?, font: Enum.Font?) -> Part,
	note: (cframe: CFrame) -> Part,
	writing: (frame: CFrame, text: string, color: Color3, font: Enum.Font, glow: boolean) -> (),
	addLamp: (bulb: BasePart, light: Light, cell: Maze.Cell?) -> (),
}

local Build = {}

local groupsReady = false

-- The monster walks through furniture (its paths cut through the middle of rooms);
-- players, line of sight and flashlight shadows still treat furniture as solid.
function Build.setupCollisionGroups()
	if groupsReady then
		return
	end
	groupsReady = true
	PhysicsService:RegisterCollisionGroup("Monster")
	PhysicsService:RegisterCollisionGroup("Furniture")
	PhysicsService:CollisionGroupSetCollidable("Monster", "Furniture", false)
end

function Build.markFurniture(root: Instance)
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = "Furniture"
		end
	end
end

function Build.new(layout: Maze.Layout, night: Nights.Night, model: Model): Ctx
	local m = night.maze
	local C = m.CellSize
	local H = m.WallHeight
	local T = Config.Maze.WallThickness
	local random = Random.new(layout.seed)
	local ROT90 = CFrame.Angles(0, math.rad(90), 0)

	local structure = Instance.new("Folder")
	structure.Name = "Structure"
	structure.Parent = model
	local props = Instance.new("Folder")
	props.Name = "Props"
	props.Parent = model
	local lights = Instance.new("Folder")
	lights.Name = "Lights"
	lights.Parent = model

	local ctx: Ctx = {} :: any
	ctx.layout = layout
	ctx.night = night
	ctx.C = C
	ctx.H = H
	ctx.ceiling = m.CeilingHeight
	ctx.T = T
	ctx.doorWidth = 5.5
	ctx.doorHeight = math.min(m.DoorHeight, H - 1)
	ctx.exitWidth = 7
	ctx.exitHeight = math.min(m.DoorHeight + 0.5, H - 1)
	ctx.random = random
	ctx.structure = structure
	ctx.props = props
	ctx.lights = lights
	ctx.lamps = {}
	ctx.hubOrigin = Vector3.new(layout.hub.x0 * C, 0, layout.hub.z0 * C)

	function ctx.part(parent: Instance, name: string, size: Vector3, cframe: CFrame, material: Enum.Material, color: Color3, shape: Enum.PartType?): Part
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

	-- decorative parts never block movement or line of sight
	function ctx.decor(p: BasePart): BasePart
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		return p
	end

	function ctx.vary(color: Color3, amount: number?): Color3
		local f = 1 + random:NextNumber(-1, 1) * (amount or 0.06)
		return Color3.new(math.clamp(color.R * f, 0, 1), math.clamp(color.G * f, 0, 1), math.clamp(color.B * f, 0, 1))
	end

	function ctx.styled(parent: Instance, name: string, size: Vector3, cframe: CFrame, style: Style): Part
		local p = ctx.part(parent, name, size, cframe, style.material, ctx.vary(style.color), nil)
		if style.reflect then
			p.Reflectance = style.reflect
		end
		return p
	end

	-- Frame on the edge an owner cell holds ("N" or "E"). Its Front face (-Z) looks
	-- into the owner cell, its Back face into the neighbour. Y = floor level.
	function ctx.edgeFrame(x: number, z: number, dir: string): CFrame
		if dir == "N" then
			return CFrame.new((x + 0.5) * C, 0, (z + 1) * C)
		end
		return CFrame.new((x + 1) * C, 0, (z + 0.5) * C) * ROT90
	end

	-- Frame on the inside face of one of a cell's walls, looking into the cell.
	function ctx.sideFrame(x: number, z: number, side: string): CFrame
		local ox, oz = Maze.DX[side], Maze.DZ[side]
		local pos = Vector3.new((x + 0.5 + ox * 0.5) * C - ox * T / 2, 0, (z + 0.5 + oz * 0.5) * C - oz * T / 2)
		return CFrame.lookAt(pos, pos - Vector3.new(ox, 0, oz))
	end

	function ctx.cellCenter(x: number, z: number): Vector3
		return Vector3.new((x + 0.5) * C, 0, (z + 0.5) * C)
	end

	function ctx.wallSides(x: number, z: number): { string }
		local sides = {}
		for _, d in Maze.DIRS do
			if Maze.getEdge(layout, x, z, d) == "wall" then
				table.insert(sides, d)
			end
		end
		return sides
	end

	-- A flat sign (text on a panel). frame looks out from the surface it's mounted on.
	function ctx.sign(frame: CFrame, size: Vector2, text: string, textColor: Color3, background: Color3?, glow: boolean?, font: Enum.Font?): Part
		local panel = ctx.part(props, "Sign", Vector3.new(size.X, size.Y, 0.08), frame, if glow then Enum.Material.Neon else Enum.Material.SmoothPlastic, background or Color3.new(0, 0, 0), nil)
		ctx.decor(panel)
		panel.CastShadow = false
		if not background then
			panel.Transparency = 1
		end
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = if glow then 0 else 1
		gui.Parent = panel
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = font or Enum.Font.GothamBold
		label.Text = text
		label.TextScaled = true
		label.TextColor3 = textColor
		label.Parent = gui
		return panel
	end

	-- A sheet of paper left behind. Whatever was written on it has faded.
	function ctx.note(cframe: CFrame): Part
		local p = ctx.part(props, "Note", Vector3.new(1.3, 0.05, 1.7), cframe, Enum.Material.SmoothPlastic, Color3.fromRGB(215, 210, 196), nil)
		p.CanCollide = false
		return p
	end

	function ctx.writing(frame: CFrame, text: string, color: Color3, font: Enum.Font, glow: boolean)
		local canvas = ctx.decor(ctx.part(props, "Writing", Vector3.new(9, 4.4, 0.05), frame, Enum.Material.SmoothPlastic, Color3.new(0, 0, 0), nil))
		canvas.Transparency = 1
		canvas.CastShadow = false
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = if glow then 0 else 1 -- normally only readable by flashlight
		gui.Brightness = if glow then 2 else 1
		gui.Parent = canvas
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = font
		label.Text = text
		label.TextScaled = true
		label.TextColor3 = color
		label.TextTransparency = random:NextNumber(0.05, 0.25)
		label.Rotation = random:NextNumber(-7, 7)
		label.Parent = gui
	end

	-- Register a light so clients flicker it and objectives can power it.
	function ctx.addLamp(bulb: BasePart, light: Light, cell: Maze.Cell?)
		bulb:SetAttribute("BaseBrightness", light.Brightness)
		CollectionService:AddTag(bulb, "FlickerLight")
		table.insert(ctx.lamps, { bulb = bulb, light = light, cell = cell })
	end

	return ctx
end

-- Wall slab along an edge. Walls between two styles are two half-thickness layers so
-- each side gets its own material.
function Build.wallBox(ctx: Ctx, parent: Instance, frame: CFrame, length: number, height: number, yBottom: number, xOffset: number, front: Style, back: Style)
	if length <= 0.05 or height <= 0.05 then
		return
	end
	local T = ctx.T
	local y = yBottom + height / 2
	if front == back then
		ctx.styled(parent, "Wall", Vector3.new(length, height, T), frame * CFrame.new(xOffset, y, 0), front)
	else
		ctx.styled(parent, "Wall", Vector3.new(length, height, T / 2), frame * CFrame.new(xOffset, y, -T / 4), front)
		ctx.styled(parent, "Wall", Vector3.new(length, height, T / 2), frame * CFrame.new(xOffset, y, T / 4), back)
	end
end

function Build.wallWithOpening(ctx: Ctx, parent: Instance, frame: CFrame, width: number, height: number, front: Style, back: Style)
	local length = ctx.C - ctx.T
	local side = (length - width) / 2
	Build.wallBox(ctx, parent, frame, side, ctx.H, 0, -(width + side) / 2, front, back)
	Build.wallBox(ctx, parent, frame, side, ctx.H, 0, (width + side) / 2, front, back)
	Build.wallBox(ctx, parent, frame, width, ctx.H - height, height, 0, front, back)
end

function Build.doorTrim(ctx: Ctx, parent: Instance, frame: CFrame, width: number, height: number, style: Style)
	local depth = ctx.T + 0.3
	for _, sx in { -1, 1 } do
		ctx.part(parent, "Trim", Vector3.new(0.45, height, depth), frame * CFrame.new(sx * (width / 2 + 0.2), height / 2, 0), style.material, style.color, nil)
	end
	ctx.part(parent, "Trim", Vector3.new(width + 0.85, 0.45, depth), frame * CFrame.new(0, height + 0.2, 0), style.material, style.color, nil)
end

function Build.brokenWall(ctx: Ctx, parent: Instance, frame: CFrame, front: Style, back: Style)
	local random = ctx.random
	local width, height = 6, math.min(9.5, ctx.H - 1.5)
	Build.wallWithOpening(ctx, parent, frame, width, height, front, back)
	for _ = 1, 5 do
		local sx = if random:NextNumber() < 0.5 then -1 else 1
		local size = Vector3.new(random:NextNumber(0.6, 1.6), random:NextNumber(0.8, 2.4), ctx.T * 0.9)
		local p = ctx.part(parent, "Chunk", size, frame * CFrame.new(sx * (width / 2 - size.X / 2 + 0.3), random:NextNumber(0.5, height), 0) * CFrame.Angles(0, 0, random:NextNumber(-0.5, 0.5)), front.material, ctx.vary(front.color), nil)
		p.CanCollide = false
	end
	for _ = 1, 9 do
		local s = random:NextNumber(0.4, 1.3)
		ctx.decor(ctx.part(parent, "Rubble", Vector3.new(s, s * 0.6, s * random:NextNumber(0.7, 1.3)), frame * CFrame.new(random:NextNumber(-width, width) * 0.6, s * 0.25, random:NextNumber(-3, 3)) * CFrame.Angles(random:NextNumber(-0.4, 0.4), random:NextNumber(0, 6.28), random:NextNumber(-0.4, 0.4)), front.material, ctx.vary(front.color, 0.15), nil))
	end
end

return Build
