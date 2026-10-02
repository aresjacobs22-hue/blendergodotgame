--!strict
-- The lobby: a circle of old stone in the fog, nothing around it but dark. Four doors
-- stand on their own around the edge, each with light leaking from behind it and a
-- square marked out on the ground in front of it. Something tall stands where the fog
-- begins. Every so often it's somewhere else.
--
-- Walk into an empty square and you choose the night and how many of you there'll be.
-- One: you go straight through. More: the sign over the door counts down from 10 and
-- whoever is standing in the square when it reaches 0 goes through with you.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Monsters = require(ReplicatedStorage.Shared.Monsters)
local Nights = require(ReplicatedStorage.Shared.Nights)

local Remotes = ReplicatedStorage.Remotes

local Lobby = {}

Lobby.ORIGIN = Vector3.new(-1200, 0, 0) -- far from where the nights are built
Lobby.RADIUS = 66 -- the stone circle
Lobby.PAD_SIZE = 12
Lobby.COUNTDOWN = 10
Lobby.MAX_PLAYERS = 4

-- The lobby's light: grey dark, fog closing in.
Lobby.LIGHTING = {
	Ambient = Color3.fromRGB(48, 48, 52),
	FogColor = Color3.fromRGB(14, 14, 16),
	FogStart = 25,
	FogEnd = 150,
	Saturation = -1,
	Contrast = 0.25,
	Brightness = 0,
	Tint = Color3.fromRGB(255, 255, 255),
	Bloom = 0.6,
	Exposure = 0,
	LampColor = Color3.fromRGB(230, 222, 205),
	Reverb = "Plain",
} :: Nights.Lighting

export type Hooks = {
	highest: (player: Player) -> number, -- highest night this player may choose
	launch: (players: { Player }, night: number) -> (), -- send them through
	isOpen: () -> boolean, -- false while a night is being played in this server
}

export type Pad = {
	index: number,
	center: Vector3,
	state: string, -- "idle" | "choosing" | "waiting" | "gone"
	leader: Player?,
	night: number,
	capacity: number,
	order: { Player }, -- who's standing in it, in the order they stepped in
	declined: { [Player]: boolean }, -- closed the choice: not asked again until they step out
	deadline: number,
	count: TextLabel,
	timer: TextLabel,
}

export type Lobby = {
	model: Model,
	pads: { Pad },
	spawnCFrame: () -> CFrame,
	choose: (player: Player, index: number, night: number, players: number) -> (),
	cancel: (player: Player, index: number) -> (),
	destroy: () -> (),
}

local PALE = Color3.fromRGB(205, 200, 188)
local STONE = Color3.fromRGB(64, 64, 66)

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, material: Enum.Material, color: Color3, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Material = material
	p.Color = color
	if shape then
		p.Shape = shape
	end
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function deco(p: Part): Part
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	return p
end

local function lamp(parent: Instance, at: Vector3, brightness: number, range: number): Part
	local bulb = deco(part(parent, "Bulb", Vector3.new(0.6, 0.6, 0.6), CFrame.new(at), Enum.Material.Neon, Lobby.LIGHTING.LampColor, Enum.PartType.Ball))
	deco(part(parent, "Cord", Vector3.new(0.06, 6, 0.06), CFrame.new(at + Vector3.new(0, 3.3, 0)), Enum.Material.SmoothPlastic, Color3.fromRGB(15, 15, 15)))
	local light = Instance.new("PointLight")
	light.Brightness = brightness
	light.Range = range
	light.Color = Lobby.LIGHTING.LampColor
	light.Shadows = true
	light.Parent = bulb
	bulb:SetAttribute("BaseBrightness", brightness)
	CollectionService:AddTag(bulb, "FlickerLight")
	return bulb
end

-- A door standing on its own, slightly open, light coming from the other side.
local function door(parent: Instance, at: CFrame): (TextLabel, TextLabel)
	local wood = Color3.fromRGB(38, 32, 28)
	local W, H = 6, 11
	part(parent, "DoorPost", Vector3.new(0.8, H, 0.9), at * CFrame.new(-W / 2 - 0.4, H / 2, 0), Enum.Material.Wood, wood)
	part(parent, "DoorPost", Vector3.new(0.8, H, 0.9), at * CFrame.new(W / 2 + 0.4, H / 2, 0), Enum.Material.Wood, wood)
	part(parent, "Lintel", Vector3.new(W + 1.6, 0.8, 0.9), at * CFrame.new(0, H + 0.4, 0), Enum.Material.Wood, wood)
	-- the door itself, hinged on the left and open a crack
	local hinge = at * CFrame.new(-W / 2, 0, 0) * CFrame.Angles(0, math.rad(-22), 0)
	part(parent, "Door", Vector3.new(W, H - 0.1, 0.35), hinge * CFrame.new(W / 2, H / 2, 0), Enum.Material.Wood, Color3.fromRGB(30, 26, 23))
	deco(part(parent, "Knob", Vector3.new(0.35, 0.35, 0.35), hinge * CFrame.new(W - 0.6, H * 0.45, -0.3), Enum.Material.Metal, Color3.fromRGB(110, 104, 96), Enum.PartType.Ball))
	-- what leaks out of the gap
	local gap = deco(part(parent, "Gap", Vector3.new(0.25, H - 0.4, 0.2), at * CFrame.new(W / 2 - 0.3, H / 2, 0.2), Enum.Material.Neon, Color3.fromRGB(235, 228, 210)))
	gap.Transparency = 0.15
	local glow = Instance.new("SpotLight")
	glow.Face = Enum.NormalId.Front
	glow.Angle = 80
	glow.Range = 28
	glow.Brightness = 2.4
	glow.Color = Color3.fromRGB(235, 228, 210)
	glow.Parent = gap
	-- the sign above it: how many are going, and how long until they do
	local plate = part(parent, "Sign", Vector3.new(4.4, 2.4, 0.2), at * CFrame.new(0, H + 2.2, -0.1), Enum.Material.SmoothPlastic, Color3.fromRGB(10, 10, 10))
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.PixelsPerStud = 50
	gui.Parent = plate
	local count = Instance.new("TextLabel")
	count.Name = "Count"
	count.BackgroundTransparency = 1
	count.Size = UDim2.fromScale(1, 0.35)
	count.Font = Enum.Font.Garamond
	count.TextScaled = true
	count.TextColor3 = PALE
	count.TextTransparency = 0.25
	count.Text = ""
	count.Parent = gui
	local timer = Instance.new("TextLabel")
	timer.Name = "Timer"
	timer.BackgroundTransparency = 1
	timer.Position = UDim2.fromScale(0, 0.35)
	timer.Size = UDim2.fromScale(1, 0.65)
	timer.Font = Enum.Font.Garamond
	timer.TextScaled = true
	timer.TextColor3 = PALE
	timer.Text = ""
	timer.Parent = gui
	return count, timer
end

-- The square in front of a door, marked out with faded tape.
local function square(parent: Instance, center: Vector3, facing: CFrame)
	local S = Lobby.PAD_SIZE
	local tape = Color3.fromRGB(150, 146, 136)
	local frame = CFrame.new(center) * facing.Rotation
	for _, e in { { 0, S / 2, S, 0.3 }, { 0, -S / 2, S, 0.3 }, { S / 2, 0, 0.3, S }, { -S / 2, 0, 0.3, S } } do
		local strip = deco(part(parent, "Tape", Vector3.new(e[3], 0.05, e[4]), frame * CFrame.new(e[1], 0.03, e[2]), Enum.Material.SmoothPlastic, tape))
		strip.Transparency = 0.35
	end
end

local function deadTree(parent: Instance, at: Vector3, random: Random)
	local bark = Color3.fromRGB(28, 26, 25)
	local trunkH = 16
	part(parent, "Trunk", Vector3.new(trunkH, 1.6, 1.6), CFrame.new(at + Vector3.new(0, trunkH / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), Enum.Material.Wood, bark, Enum.PartType.Cylinder)
	for i = 1, 7 do
		local h = 6 + i * 1.4
		local len = 3 + random:NextNumber() * 5
		local yaw = random:NextNumber(0, math.pi * 2)
		local tilt = math.rad(random:NextNumber(25, 65))
		local base = CFrame.new(at + Vector3.new(0, h, 0)) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(0, 0, -tilt)
		deco(part(parent, "Branch", Vector3.new(0.35 + 0.05 * (8 - i), len, 0.35 + 0.05 * (8 - i)), base * CFrame.new(0, len / 2, 0), Enum.Material.Wood, bark))
	end
end

function Lobby.new(hooks: Hooks): Lobby
	local O = Lobby.ORIGIN
	local random = Random.new()
	local model = Instance.new("Model")
	model.Name = "Lobby"

	-- the stone circle, cracked, and nothing beyond it
	part(model, "Ground", Vector3.new(2, Lobby.RADIUS * 2 + 8, Lobby.RADIUS * 2 + 8), CFrame.new(O + Vector3.new(0, -1, 0)) * CFrame.Angles(0, 0, math.rad(90)), Enum.Material.Slate, STONE, Enum.PartType.Cylinder)
	for _ = 1, 70 do
		local a, r = random:NextNumber(0, math.pi * 2), random:NextNumber(0, Lobby.RADIUS)
		local s = random:NextNumber(2, 7)
		local tile = deco(part(model, "Flagstone", Vector3.new(s, 0.08, s * random:NextNumber(0.6, 1.4)), CFrame.new(O + Vector3.new(math.cos(a) * r, 0.02, math.sin(a) * r)) * CFrame.Angles(0, random:NextNumber(0, 3), 0), Enum.Material.Slate, STONE:Lerp(Color3.new(0, 0, 0), random:NextNumber(0.1, 0.5))))
		tile.CastShadow = false
	end
	-- an invisible edge so nobody walks off into the dark
	for i = 0, 23 do
		local a = i / 24 * math.pi * 2
		local wall = part(model, "Edge", Vector3.new(19, 30, 2), CFrame.new(O + Vector3.new(math.cos(a) * (Lobby.RADIUS + 3), 15, math.sin(a) * (Lobby.RADIUS + 3))) * CFrame.Angles(0, -a + math.pi / 2, 0), Enum.Material.SmoothPlastic, STONE)
		wall.Transparency = 1
	end
	deadTree(model, O + Vector3.new(9, 0, -6), random)

	-- the four doors, each with its square and a bare bulb over it
	local pads: { Pad } = {}
	for i = 1, 4 do
		local a = (i - 0.5) / 4 * math.pi * 2
		local doorAt = O + Vector3.new(math.cos(a) * 44, 0, math.sin(a) * 44)
		local facing = CFrame.lookAt(doorAt, Vector3.new(O.X, 0, O.Z))
		local count, timer = door(model, facing)
		local center = doorAt + facing.LookVector * (Lobby.PAD_SIZE / 2 + 1.5)
		square(model, center, facing)
		-- an invisible marker of the square, so it's easy to find (and test)
		local marker = deco(part(model, "Pad" .. i, Vector3.new(Lobby.PAD_SIZE, 0.2, Lobby.PAD_SIZE), CFrame.new(center) * facing.Rotation, Enum.Material.SmoothPlastic, STONE))
		marker.Transparency = 1
		lamp(model, center + Vector3.new(0, 9, 0), 1.3, 24)
		table.insert(pads, {
			index = i,
			center = center,
			state = "idle",
			leader = nil,
			night = 1,
			capacity = 1,
			order = {},
			declined = {},
			deadline = 0,
			count = count,
			timer = timer,
		})
	end

	-- the one watching from the fog
	local watcher = Monsters.build("Hollow", { preview = true })
	watcher.model.Name = "Watcher"
	local function moveWatcher()
		local a = random:NextNumber(0, math.pi * 2)
		local at = O + Vector3.new(math.cos(a) * 84, watcher.rootHeight, math.sin(a) * 84)
		watcher.model:PivotTo(CFrame.lookAt(at, Vector3.new(O.X, at.Y, O.Z)))
		Monsters.solve(watcher)
	end
	moveWatcher()
	watcher.model.Parent = model
	model.Parent = workspace

	local function inLobby(player: Player): Vector3?
		if player:GetAttribute("Where") ~= "lobby" then
			return nil
		end
		local character = player.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
		return if root then root.Position else nil
	end

	local function inside(pad: Pad, player: Player): boolean
		local pos = inLobby(player)
		if not pos then
			return false
		end
		local d = pos - pad.center
		local half = Lobby.PAD_SIZE / 2
		return math.abs(d.X) <= half and math.abs(d.Z) <= half and d.Y < 12
	end

	local function reset(pad: Pad)
		pad.state = "idle"
		pad.leader = nil
		pad.capacity = 1
		pad.deadline = 0
	end

	local function members(pad: Pad): { Player }
		local out = {}
		for _, p in pad.order do
			if #out < pad.capacity then
				table.insert(out, p)
			end
		end
		return out
	end

	local function go(pad: Pad, group: { Player })
		pad.state = "gone"
		for _, p in group do
			Remotes.Lobby:FireClient(p, "launch", pad.night)
		end
		hooks.launch(group, pad.night)
		task.delay(2, function()
			if pad.state == "gone" then
				reset(pad)
			end
		end)
	end

	local function sign(pad: Pad)
		if pad.state == "waiting" then
			pad.count.Text = string.format("%d / %d", #members(pad), pad.capacity)
			pad.timer.Text = tostring(math.max(1, math.ceil(pad.deadline - os.clock())))
		elseif pad.state == "choosing" then
			pad.count.Text = ""
			pad.timer.Text = "· · ·"
		else
			pad.count.Text = ""
			pad.timer.Text = ""
		end
	end

	local function update()
		local open = hooks.isOpen()
		for _, pad in pads do
			-- who's standing in it now, keeping the order they came in
			local still = {}
			for _, p in pad.order do
				if inside(pad, p) then
					table.insert(still, p)
				end
			end
			for _, p in Players:GetPlayers() do
				if inside(pad, p) and not table.find(still, p) then
					table.insert(still, p)
				end
			end
			pad.order = still
			for p in pad.declined do
				if not table.find(still, p) then
					pad.declined[p] = nil
				end
			end

			if not open then
				if pad.state == "choosing" and pad.leader then
					Remotes.Lobby:FireClient(pad.leader, "close", pad.index)
				end
				if pad.state ~= "gone" then
					reset(pad)
				end
			elseif pad.state == "idle" then
				for _, p in still do
					if not pad.declined[p] then
						pad.state = "choosing"
						pad.leader = p
						Remotes.Lobby:FireClient(p, "choose", pad.index, math.min(hooks.highest(p), Nights.count))
						break
					end
				end
			elseif pad.state == "choosing" then
				local leader = pad.leader
				if not leader or not table.find(still, leader) then
					if leader then
						Remotes.Lobby:FireClient(leader, "close", pad.index)
					end
					reset(pad)
				end
			elseif pad.state == "waiting" then
				if #still == 0 then
					reset(pad)
				elseif os.clock() >= pad.deadline then
					go(pad, members(pad))
				end
			end
			sign(pad)
		end
	end

	local connections: { RBXScriptConnection } = {}
	local accum = 0
	table.insert(connections, RunService.Heartbeat:Connect(function(dt: number)
		accum += dt
		if accum >= 0.2 then
			accum = 0
			update()
		end
	end))
	local alive = true
	task.spawn(function()
		while alive do
			task.wait(random:NextNumber(45, 90))
			if alive then
				moveWatcher()
			end
		end
	end)

	local lobby: Lobby
	lobby = {
		model = model,
		pads = pads,
		spawnCFrame = function(): CFrame
			local a = random:NextNumber(0, math.pi * 2)
			local at = O + Vector3.new(math.cos(a) * 6, 3.5, math.sin(a) * 6)
			return CFrame.lookAt(at, at + Vector3.new(math.cos(a), 0, math.sin(a)))
		end,
		-- the leader picked a night and how many of them there'll be
		choose = function(player: Player, index: number, night: number, count: number)
			local pad = pads[index]
			if not pad or pad.state ~= "choosing" or pad.leader ~= player then
				return
			end
			pad.night = math.clamp(math.floor(night), 1, math.min(hooks.highest(player), Nights.count))
			pad.capacity = math.clamp(math.floor(count), 1, Lobby.MAX_PLAYERS)
			if pad.capacity == 1 then
				go(pad, { player })
			else
				pad.state = "waiting"
				pad.deadline = os.clock() + Lobby.COUNTDOWN
				sign(pad)
			end
		end,
		cancel = function(player: Player, index: number)
			local pad = pads[index]
			if pad and pad.state == "choosing" and pad.leader == player then
				pad.declined[player] = true
				reset(pad)
			end
		end,
		destroy = function()
			alive = false
			for _, c in connections do
				c:Disconnect()
			end
			model:Destroy()
		end,
	}

	table.insert(connections, Remotes.Lobby.OnServerEvent:Connect(function(player: Player, action: unknown, index: unknown, night: unknown, count: unknown)
		if typeof(index) ~= "number" then
			return
		end
		if action == "choose" and typeof(night) == "number" and typeof(count) == "number" then
			lobby.choose(player, index, night, count)
		elseif action == "cancel" then
			lobby.cancel(player, index)
		end
	end))

	return lobby
end

return Lobby
