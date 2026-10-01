--!strict
-- Things every map has: hinged doors, batteries, hiding lockers and readable notes.
-- (The exit lives in Exit.luau; keys, generators, photos and hearts in Objectives.)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Audio = require(ReplicatedStorage.Shared.Audio)
local Config = require(ReplicatedStorage.Shared.Config)
local Maze = require(ReplicatedStorage.Shared.Maze)
local WorldBuilder = require(script.Parent.WorldBuilder)

local Remotes = ReplicatedStorage.Remotes

type Layout = Maze.Layout
type World = WorldBuilder.World

export type Door = {
	part: BasePart,
	closed: CFrame,
	opened: CFrame,
	isOpen: boolean,
	busy: boolean,
	prompt: ProximityPrompt,
}

export type Locker = {
	model: Model,
	anchor: BasePart,
	inside: CFrame,
	outside: CFrame,
	occupant: Player?,
	prompt: ProximityPrompt,
	lastUse: number,
}

export type Hooks = {
	onHide: (player: Player, locker: Locker) -> (),
	onNoise: (position: Vector3, radius: number) -> (),
	isAlive: (player: Player) -> boolean,
}

local Interactables = {}
Interactables.__index = Interactables

export type Interactables = typeof(setmetatable(
	{} :: {
		layout: Layout,
		world: World,
		hooks: Hooks,
		folder: Folder,
		doors: { Door },
		lockers: { Locker },
		connections: { RBXScriptConnection },
	},
	Interactables
))

function Interactables.prompt(parent: Instance, action: string, object: string, hold: number?, distance: number?): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = hold or 0
	p.MaxActivationDistance = distance or 8
	p.RequiresLineOfSight = false
	p.Parent = parent
	return p
end
local prompt = Interactables.prompt

function Interactables.rootOf(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end
local rootOf = Interactables.rootOf

function Interactables.new(layout: Layout, world: World, hooks: Hooks): Interactables
	local folder = Instance.new("Folder")
	folder.Name = "Interactive"
	folder.Parent = world.model

	local self = setmetatable({
		layout = layout,
		world = world,
		hooks = hooks,
		folder = folder,
		doors = {},
		lockers = {},
		connections = {},
	}, Interactables)

	self:_buildDoors()
	self:_buildBatteries()
	self:_buildLockers()
	self:_buildNotes()

	table.insert(self.connections, Remotes.LeaveHiding.OnServerEvent:Connect(function(player: Player)
		self:leave(player, false)
	end))
	return self
end

-- Doors ------------------------------------------------------------------------

function Interactables._buildDoors(self: Interactables)
	local ctx = self.world.ctx
	for key, kind in self.layout.edges do
		if kind == "door" then
			local x, z, dir = Maze.parseEdgeKey(key)
			local frame = ctx.edgeFrame(x, z, dir)
			local w, h = ctx.doorWidth - 0.2, ctx.doorHeight - 0.15
			local closed = frame * CFrame.new(0, h / 2 + 0.05, 0)
			local hinge = frame * CFrame.new(-w / 2, h / 2 + 0.05, 0)
			local opened = hinge * CFrame.Angles(0, math.rad(-100), 0) * hinge:Inverse() * closed

			local style = self.world.theme.trim
			local door = ctx.part(self.folder, "Door", Vector3.new(w, h, 0.35), closed, if style.material == Enum.Material.Neon then Enum.Material.Basalt else style.material, if style.material == Enum.Material.Neon then Color3.fromRGB(20, 16, 26) else style.color, nil)
			door.CollisionGroup = "Furniture"
			for _, side in { -1, 1 } do
				local knob = ctx.part(self.folder, "Knob", Vector3.new(0.35, 0.35, 0.35), closed * CFrame.new(w / 2 - 0.6, -0.7, side * 0.3), Enum.Material.Metal, Color3.fromRGB(170, 170, 160), Enum.PartType.Ball)
				knob.Anchored = false
				knob.CanCollide = false
				knob.Massless = true
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = door
				weld.Part1 = knob
				weld.Parent = knob
			end

			local entry: Door = {
				part = door,
				closed = closed,
				opened = opened,
				isOpen = false,
				busy = false,
				prompt = prompt(door, "Open", "Door", 0, 9),
			}
			table.insert(self.doors, entry)
			if self.world.random:NextNumber() < 0.35 then
				entry.isOpen = true
				door.CFrame = opened
				entry.prompt.ActionText = "Close"
			end
			entry.prompt.Triggered:Connect(function(player: Player)
				if self.hooks.isAlive(player) then
					self:setDoor(entry, not entry.isOpen, false)
					if not entry.isOpen then
						self.hooks.onNoise(door.Position, 30) -- shutting a door carries
					end
				end
			end)
		end
	end
end

function Interactables.setDoor(self: Interactables, door: Door, open: boolean, slam: boolean)
	if door.busy or door.isOpen == open then
		return
	end
	door.busy = true
	door.isOpen = open
	local info = if slam
		then TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		else TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	local tween = TweenService:Create(door.part, info, { CFrame = if open then door.opened else door.closed })
	tween:Play()
	if slam then
		Audio.play("DoorSlam", door.part, 1.3, 1, 110)
	elseif open then
		Audio.play("DoorOpen", door.part, 0.8, 1, 60)
	else
		Audio.play("DoorSlam", door.part, 0.5, 1.25, 60)
	end
	door.prompt.ActionText = if open then "Close" else "Open"
	tween.Completed:Once(function()
		door.busy = false
	end)
end

-- The monster bursts through closed doors in its way.
function Interactables.slamOpenNear(self: Interactables, position: Vector3, radius: number)
	for _, door in self.doors do
		if not door.isOpen and not door.busy and (door.part.Position - position).Magnitude < radius then
			self:setDoor(door, true, true)
		end
	end
end

-- Spot helpers -----------------------------------------------------------------

-- The wall at the back of a cell (opposite its way in), for placing things.
function Interactables.backWallSide(layout: Layout, x: number, z: number): string
	for _, d in Maze.DIRS do
		if Maze.isPassable(Maze.getEdge(layout, x, z, d)) then
			local back = Maze.OPPOSITE[d]
			if Maze.getEdge(layout, x, z, back) == "wall" then
				return back
			end
		end
	end
	for _, d in Maze.DIRS do
		if Maze.getEdge(layout, x, z, d) == "wall" then
			return d
		end
	end
	return "N"
end

-- A frame to put an objective item in a cell: against its back wall if it has one,
-- otherwise on the floor near the middle (open halls).
function Interactables.spotFrame(world: World, cell: Maze.Cell): CFrame
	local ctx = world.ctx
	for _, d in Maze.DIRS do
		if Maze.getEdge(world.ctx.layout, cell.x, cell.z, d) == "wall" then
			return ctx.sideFrame(cell.x, cell.z, Interactables.backWallSide(world.ctx.layout, cell.x, cell.z)) * CFrame.new(0, 0, -1.8)
		end
	end
	local center = ctx.cellCenter(cell.x, cell.z)
	return CFrame.new(center + Vector3.new(ctx.C * 0.2, 0, ctx.C * 0.2)) * CFrame.Angles(0, world.random:NextNumber(0, 6.28), 0)
end

-- Batteries --------------------------------------------------------------------

function Interactables._buildBatteries(self: Interactables)
	local ctx = self.world.ctx
	for _, cell in self.layout.batteries do
		local frame = Interactables.spotFrame(self.world, cell) * CFrame.new(self.world.random:NextNumber(-2.5, 2.5), 0, 1.1)
		local battery = ctx.decor(ctx.part(self.folder, "Battery", Vector3.new(1.1, 0.5, 0.5), frame * CFrame.new(0, 0.26, 0) * CFrame.Angles(0, self.world.random:NextNumber(-0.6, 0.6), 0), Enum.Material.Metal, Color3.fromRGB(70, 70, 70), Enum.PartType.Cylinder))
		battery.CanQuery = true
		ctx.decor(ctx.part(battery, "BatteryCap", Vector3.new(0.12, 0.3, 0.3), battery.CFrame * CFrame.new(0.6, 0, 0), Enum.Material.Metal, Color3.fromRGB(200, 200, 200), Enum.PartType.Cylinder))
		local glint = Instance.new("PointLight")
		glint.Range = 4
		glint.Brightness = 0.5
		glint.Parent = battery
		local p = prompt(battery, "Take", "Battery", 0, 8)
		p.Triggered:Connect(function(player: Player)
			if not self.hooks.isAlive(player) or battery.Parent == nil then
				return
			end
			battery:Destroy()
			Remotes.Battery:FireClient(player, Config.Player.BatteryPickup)
		end)
	end
end

-- Hiding lockers -----------------------------------------------------------------

function Interactables._buildLockers(self: Interactables)
	local ctx = self.world.ctx
	local themeLocker = self.world.theme.locker
	for _, spot in self.layout.lockers do
		local w, h, depth = 4.2, 8.4, 3.4
		local center = ctx.sideFrame(spot.x, spot.z, spot.side) * CFrame.new(0, 0, -depth / 2)
		local material = if spot.house then Enum.Material.Wood else themeLocker.material
		local color = if spot.house then Color3.fromRGB(70, 58, 50) else themeLocker.color

		local model = Instance.new("Model")
		model.Name = if spot.house then "Wardrobe" else "Locker"
		local function panel(name: string, size: Vector3, offset: CFrame)
			local p = ctx.part(model, name, size, center * offset, material, color, nil)
			p.CollisionGroup = "Furniture"
		end
		panel("Back", Vector3.new(w, h, 0.2), CFrame.new(0, h / 2, depth / 2 - 0.1))
		panel("Side", Vector3.new(0.2, h, depth), CFrame.new(-(w / 2 - 0.1), h / 2, 0))
		panel("Side", Vector3.new(0.2, h, depth), CFrame.new(w / 2 - 0.1, h / 2, 0))
		panel("Top", Vector3.new(w, 0.2, depth), CFrame.new(0, h - 0.1, 0))
		panel("Bottom", Vector3.new(w, 0.2, depth), CFrame.new(0, 0.1, 0))
		-- slatted front: you can peek out between the slats
		local y = 0.45
		while y < h - 0.3 do
			panel("Slat", Vector3.new(w - 0.4, 0.44, 0.15), CFrame.new(0, y, -depth / 2 + 0.08))
			y += 0.62
		end
		panel("Handle", Vector3.new(0.18, 1.2, 0.2), CFrame.new(w / 2 - 0.6, 4.2, -depth / 2 - 0.08))

		local anchor = ctx.decor(ctx.part(model, "PromptAnchor", Vector3.new(1, 1, 1), center * CFrame.new(0, 3.5, -depth / 2 - 0.3), Enum.Material.SmoothPlastic, Color3.new(), nil))
		anchor.Transparency = 1
		model.Parent = self.folder

		local locker: Locker = {
			model = model,
			anchor = anchor,
			inside = center * CFrame.new(0, 3.1, 0.15),
			outside = center * CFrame.new(0, 3.1, -(depth / 2 + 2.6)),
			occupant = nil,
			prompt = prompt(anchor, "Hide", if spot.house then "Wardrobe" else "Locker", 0.25, 7),
			lastUse = -math.huge,
		}
		table.insert(self.lockers, locker)
		locker.prompt.Triggered:Connect(function(player: Player)
			self:hide(player, locker)
		end)
	end
end

function Interactables.lockerOf(self: Interactables, player: Player): Locker?
	for _, locker in self.lockers do
		if locker.occupant == player then
			return locker
		end
	end
	return nil
end

function Interactables.hide(self: Interactables, player: Player, locker: Locker)
	if locker.occupant or os.clock() - locker.lastUse < 0.8 then
		return
	end
	if not self.hooks.isAlive(player) or self:lockerOf(player) then
		return
	end
	local character = player.Character
	local root = rootOf(player)
	if not character or not root then
		return
	end
	locker.occupant = player
	locker.lastUse = os.clock()
	root.Anchored = true
	character:PivotTo(locker.inside)
	player:SetAttribute("Hiding", true)
	locker.prompt.Enabled = false
	Audio.play("Locker", locker.anchor, 0.9, 1, 60)
	self.hooks.onHide(player, locker)
end

-- pulled = the monster dragged them out, so they stay frozen for the jumpscare.
function Interactables.leave(self: Interactables, player: Player, pulled: boolean)
	local locker = self:lockerOf(player)
	if not locker then
		return
	end
	if not pulled and os.clock() - locker.lastUse < 0.5 then
		return
	end
	locker.occupant = nil
	locker.lastUse = os.clock()
	locker.prompt.Enabled = true
	player:SetAttribute("Hiding", false)
	local character = player.Character
	local root = rootOf(player)
	if character and root then
		character:PivotTo(locker.outside)
		if not pulled then
			root.Anchored = false
		end
	end
	Audio.play("Locker", locker.anchor, if pulled then 1.4 else 0.8, if pulled then 0.8 else 1.05, 70)
end

function Interactables.release(self: Interactables, player: Player)
	local locker = self:lockerOf(player)
	if locker then
		locker.occupant = nil
		locker.prompt.Enabled = true
	end
	player:SetAttribute("Hiding", false)
end

-- Notes --------------------------------------------------------------------------

function Interactables._buildNotes(self: Interactables)
	for _, note in self.world.notes do
		note.part.CanQuery = true
		local p = prompt(note.part, "Read", "Note", 0, 7)
		p.Triggered:Connect(function(player: Player)
			Remotes.Notify:FireClient(player, note.text, "note")
		end)
	end
end

function Interactables.destroy(self: Interactables)
	for _, c in self.connections do
		c:Disconnect()
	end
	table.clear(self.connections)
	for _, locker in self.lockers do
		if locker.occupant then
			locker.occupant:SetAttribute("Hiding", false)
		end
	end
end

return Interactables
