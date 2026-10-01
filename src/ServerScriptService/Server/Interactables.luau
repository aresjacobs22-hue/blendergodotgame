--!strict
-- Everything you can interact with: doors, keys, batteries, hiding lockers, notes,
-- the padlocked exit door, its keypad, and the escape zone behind it.

local Players = game:GetService("Players")
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
	onKey: (player: Player, index: number) -> (),
	onHide: (player: Player, locker: Locker) -> (),
	onExitOpened: (player: Player) -> (),
	onEscaped: (player: Player) -> (),
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
		padlocks: { { BasePart } },
		padlocksLeft: number,
		exitLeaves: { { part: BasePart, opened: CFrame } },
		keypad: BasePart,
		keypadText: TextLabel,
		exitOpen: boolean,
		escaped: { [Player]: boolean },
		lastCodeTry: { [Player]: number },
		connections: { RBXScriptConnection },
	},
	Interactables
))

local part = WorldBuilder.part
local decor = WorldBuilder.decor

local function prompt(parent: Instance, action: string, object: string, hold: number?, distance: number?): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = hold or 0
	p.MaxActivationDistance = distance or 8
	p.RequiresLineOfSight = false
	p.Parent = parent
	return p
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

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
		padlocks = {},
		padlocksLeft = Config.Maze.KeyCount,
		exitLeaves = {},
		keypad = (nil :: any) :: BasePart,
		keypadText = (nil :: any) :: TextLabel,
		exitOpen = false,
		escaped = {},
		lastCodeTry = {},
		connections = {},
	}, Interactables)

	self:_buildDoors()
	self:_buildKeys()
	self:_buildBatteries()
	self:_buildLockers()
	self:_buildNotes()
	self:_buildExit()

	table.insert(self.connections, Remotes.LeaveHiding.OnServerEvent:Connect(function(player: Player)
		self:leave(player, false)
	end))
	table.insert(self.connections, Remotes.SubmitCode.OnServerEvent:Connect(function(player: Player, code: unknown)
		self:_submitCode(player, code)
	end))
	table.insert(self.connections, world.escapeZone.Touched:Connect(function(hit: BasePart)
		if not self.exitOpen then
			return
		end
		local character = hit:FindFirstAncestorOfClass("Model")
		local player = character and Players:GetPlayerFromCharacter(character)
		if player and not self.escaped[player] and self.hooks.isAlive(player) then
			self.escaped[player] = true
			self.hooks.onEscaped(player)
		end
	end))

	return self
end

-- Doors ------------------------------------------------------------------------

function Interactables._buildDoors(self: Interactables)
	for key, kind in self.layout.edges do
		if kind == "door" then
			local x, z, dir = Maze.parseEdgeKey(key)
			local frame = WorldBuilder.edgeFrame(x, z, dir)
			local w, h = WorldBuilder.DOOR_WIDTH - 0.2, WorldBuilder.DOOR_HEIGHT - 0.15
			local closed = frame * CFrame.new(0, h / 2 + 0.05, 0)
			local hinge = frame * CFrame.new(-w / 2, h / 2 + 0.05, 0)
			local opened = hinge * CFrame.Angles(0, math.rad(-100), 0) * hinge:Inverse() * closed

			local door = part(self.folder, "Door", Vector3.new(w, h, 0.35), closed, Enum.Material.Wood, Color3.fromRGB(80, 68, 58))
			door.CollisionGroup = "Furniture"
			for _, side in { -1, 1 } do
				local knob = part(self.folder, "Knob", Vector3.new(0.35, 0.35, 0.35), closed * CFrame.new(w / 2 - 0.6, -0.7, side * 0.3), Enum.Material.Metal, Color3.fromRGB(170, 170, 160), Enum.PartType.Ball)
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
			-- a couple of doors start ajar
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

-- Keys -------------------------------------------------------------------------

local function backWallSide(layout: Layout, x: number, z: number): string
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

function Interactables._buildKeys(self: Interactables)
	local metal = Color3.fromRGB(196, 196, 190)
	for index, cell in self.layout.keys do
		local frame = WorldBuilder.sideFrame(cell.x, cell.z, backWallSide(self.layout, cell.x, cell.z))
		local crate = part(self.folder, "KeyCrate", Vector3.new(2.6, 2.6, 2.6), frame * CFrame.new(0, 1.3, -1.7), Enum.Material.WoodPlanks, Color3.fromRGB(96, 86, 74))
		crate.CollisionGroup = "Furniture"

		local model = Instance.new("Model")
		model.Name = "Key" .. index
		local base = frame * CFrame.new(0, 2.68, -1.7) * CFrame.Angles(0, self.world.random:NextNumber(0, math.pi * 2), 0)
		local shaft = decor(part(model, "Shaft", Vector3.new(1.6, 0.18, 0.18), base * CFrame.new(0.2, 0, 0), Enum.Material.Metal, metal))
		shaft.CanQuery = true
		shaft.Reflectance = 0.15
		decor(part(model, "Bow", Vector3.new(0.12, 0.9, 0.9), base * CFrame.new(-0.85, 0, 0) * CFrame.Angles(0, 0, math.rad(90)), Enum.Material.Metal, metal, Enum.PartType.Cylinder))
		decor(part(model, "Tooth", Vector3.new(0.16, 0.12, 0.4), base * CFrame.new(0.85, 0, 0.22), Enum.Material.Metal, metal))
		decor(part(model, "Tooth", Vector3.new(0.16, 0.12, 0.28), base * CFrame.new(0.55, 0, 0.16), Enum.Material.Metal, metal))
		local tag = decor(part(model, "Tag", Vector3.new(0.6, 0.03, 0.8), base * CFrame.new(-1.6, 0, 0.3) * CFrame.Angles(0, 0.3, 0), Enum.Material.SmoothPlastic, Color3.fromRGB(220, 214, 198)))
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Top
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 120
		gui.Parent = tag
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.SpecialElite
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(20, 20, 20)
		local mask = {}
		for i = 1, #self.layout.code do
			mask[i] = if i == index then string.sub(self.layout.code, i, i) else "_"
		end
		label.Text = table.concat(mask, " ")
		label.Parent = gui
		local glint = Instance.new("PointLight")
		glint.Range = 6
		glint.Brightness = 0.9
		glint.Parent = shaft
		model.PrimaryPart = shaft
		model.Parent = self.folder

		local p = prompt(shaft, "Take", "Key", 0.5, 8)
		p.Triggered:Connect(function(player: Player)
			if not self.hooks.isAlive(player) or model.Parent == nil then
				return
			end
			Audio.play("KeyPickup", crate, 1, 1, 70)
			model:Destroy()
			self.hooks.onKey(player, index)
			self.hooks.onNoise(crate.Position, 45) -- rattling the key loose carries
		end)
	end
end

-- Batteries --------------------------------------------------------------------

function Interactables._buildBatteries(self: Interactables)
	for _, cell in self.layout.batteries do
		local frame = WorldBuilder.sideFrame(cell.x, cell.z, backWallSide(self.layout, cell.x, cell.z))
		local battery = decor(part(self.folder, "Battery", Vector3.new(1.1, 0.5, 0.5), frame * CFrame.new(self.world.random:NextNumber(-2.5, 2.5), 0.26, -0.7) * CFrame.Angles(0, self.world.random:NextNumber(-0.6, 0.6), 0), Enum.Material.Metal, Color3.fromRGB(70, 70, 70), Enum.PartType.Cylinder))
		battery.CanQuery = true
		decor(part(battery, "BatteryCap", Vector3.new(0.12, 0.3, 0.3), battery.CFrame * CFrame.new(0.6, 0, 0), Enum.Material.Metal, Color3.fromRGB(200, 200, 200), Enum.PartType.Cylinder))
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
	for _, spot in self.layout.lockers do
		local w, h, depth = 4.2, 8.4, 3.4
		local center = WorldBuilder.sideFrame(spot.x, spot.z, spot.side) * CFrame.new(0, 0, -depth / 2)
		local material = if spot.house then Enum.Material.Wood else Enum.Material.Metal
		local color = if spot.house then Color3.fromRGB(70, 58, 50) else Color3.fromRGB(100, 102, 104)

		local model = Instance.new("Model")
		model.Name = if spot.house then "Wardrobe" else "Locker"
		local function panel(name: string, size: Vector3, offset: CFrame)
			local p = part(model, name, size, center * offset, material, color)
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

		local anchor = decor(part(model, "PromptAnchor", Vector3.new(1, 1, 1), center * CFrame.new(0, 3.5, -depth / 2 - 0.3), Enum.Material.SmoothPlastic, Color3.new()))
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
	self.lastCodeTry[player] = nil
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

-- Exit door, padlocks, keypad ------------------------------------------------------

function Interactables._buildExit(self: Interactables)
	local e = self.layout.exitCell
	-- the exit edge belongs to the virtual cell south of the hall: Back face = hall side
	local frame = WorldBuilder.edgeFrame(e.x, e.z - 1, "N")
	local w, h = WorldBuilder.EXIT_WIDTH, WorldBuilder.EXIT_HEIGHT
	local steel = Color3.fromRGB(86, 86, 90)

	for _, sx in { -1, 1 } do
		local closed = frame * CFrame.new(sx * w / 4, h / 2 + 0.02, 0)
		local hinge = frame * CFrame.new(sx * w / 2, h / 2 + 0.02, 0)
		local opened = hinge * CFrame.Angles(0, math.rad(-sx * 95), 0) * hinge:Inverse() * closed
		local leaf = part(self.folder, "ExitDoor", Vector3.new(w / 2 - 0.08, h - 0.05, 0.5), closed, Enum.Material.DiamondPlate, steel)
		table.insert(self.exitLeaves, { part = leaf :: BasePart, opened = opened })
	end
	-- a chain across both leaves
	for i = 0, 12 do
		decor(part(self.folder, "Chain", Vector3.new(0.32, 0.18, 0.18), frame * CFrame.new(-2.4 + i * 0.4, 5.1 + math.sin(i * 0.5) * 0.15, 0.42) * CFrame.Angles(i % 2 * math.rad(90), 0, 0), Enum.Material.Metal, Color3.fromRGB(120, 120, 120)))
	end
	for i = 1, Config.Maze.KeyCount do
		local x = -1.05 + (i - 1) * 0.7
		local y = 4.4 + (i % 2) * 0.55
		local body = decor(part(self.folder, "Padlock", Vector3.new(0.55, 0.65, 0.25), frame * CFrame.new(x, y, 0.5), Enum.Material.Metal, Color3.fromRGB(150, 150, 146)))
		local shackle = decor(part(self.folder, "Shackle", Vector3.new(0.38, 0.45, 0.08), frame * CFrame.new(x, y + 0.5, 0.5), Enum.Material.Metal, Color3.fromRGB(180, 180, 176)))
		table.insert(self.padlocks, { body, shackle })
	end

	local keypad = part(self.folder, "Keypad", Vector3.new(1.2, 1.8, 0.3), frame * CFrame.new(w / 2 + 1.15, 4.8, 0.65), Enum.Material.Metal, Color3.fromRGB(40, 40, 42))
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 100
	gui.LightInfluence = 0
	gui.Brightness = 1.5
	gui.Parent = keypad
	local text = Instance.new("TextLabel")
	text.BackgroundColor3 = Color3.fromRGB(12, 12, 12)
	text.BorderSizePixel = 0
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.Code
	text.TextScaled = true
	text.TextColor3 = Color3.fromRGB(210, 210, 210)
	text.Parent = gui
	local glow = Instance.new("PointLight")
	glow.Range = 7
	glow.Brightness = 0.5
	glow.Parent = keypad
	self.keypad = keypad
	self.keypadText = text
	self:_refreshKeypad()

	local p = prompt(keypad, "Use", "Keypad", 0, 7)
	p.Triggered:Connect(function(player: Player)
		if self.exitOpen or not self.hooks.isAlive(player) then
			return
		end
		if self.padlocksLeft > 0 then
			Audio.play("KeypadError", keypad, 0.8, 1, 50)
			Remotes.Notify:FireClient(player, string.format("%d padlocks still hold the door. Find the keys.", self.padlocksLeft))
			return
		end
		Remotes.OpenKeypad:FireClient(player)
	end)
end

function Interactables._refreshKeypad(self: Interactables)
	if self.exitOpen then
		self.keypadText.Text = "OPEN"
	elseif self.padlocksLeft > 0 then
		self.keypadText.Text = string.format("LOCKED\n%d/%d", Config.Maze.KeyCount - self.padlocksLeft, Config.Maze.KeyCount)
	else
		self.keypadText.Text = "ENTER\nCODE"
	end
end

function Interactables.removePadlock(self: Interactables)
	if self.padlocksLeft <= 0 then
		return
	end
	local lock = self.padlocks[self.padlocksLeft]
	self.padlocksLeft -= 1
	for _, p in lock do
		p.Anchored = false
		p.CanCollide = true
	end
	Audio.play("Unlock", self.keypad, 0.9, 0.9, 120)
	self:_refreshKeypad()
end

function Interactables._submitCode(self: Interactables, player: Player, code: unknown)
	if typeof(code) ~= "string" or #code > 8 then
		return
	end
	if self.exitOpen or self.padlocksLeft > 0 or not self.hooks.isAlive(player) then
		return
	end
	local now = os.clock()
	local last = self.lastCodeTry[player]
	if last and now - last < 0.8 then
		return
	end
	self.lastCodeTry[player] = now
	local root = rootOf(player)
	if not root or (root.Position - self.keypad.Position).Magnitude > 16 then
		return
	end
	if code == self.layout.code then
		self:_openExit(player)
	else
		Audio.play("KeypadError", self.keypad, 1.3, 1, 100)
		self.keypadText.Text = "WRONG"
		task.delay(1.2, function()
			if self.keypad.Parent then
				self:_refreshKeypad()
			end
		end)
		Remotes.Notify:FireClient(player, "Wrong code. That buzzer was loud...")
		self.hooks.onNoise(self.keypad.Position, 70)
	end
end

function Interactables._openExit(self: Interactables, player: Player)
	self.exitOpen = true
	self:_refreshKeypad()
	Audio.play("Unlock", self.keypad, 1.2, 1, 120)
	task.delay(0.6, function()
		if not self.keypad.Parent then
			return
		end
		for _, leaf in self.exitLeaves do
			TweenService:Create(leaf.part, TweenInfo.new(2.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { CFrame = leaf.opened }):Play()
		end
		Audio.play("DoorOpen", self.exitLeaves[1].part, 1.4, 0.55, 140)
		self.world.exitLight.Enabled = true
	end)
	self.hooks.onExitOpened(player)
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
