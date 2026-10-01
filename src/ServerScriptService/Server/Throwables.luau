--!strict
-- Bottles lying around the map. Pick them up (you can carry 3) and throw one with G:
-- it smashes where it lands and the monster goes to look. Blind things hate this.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local Audio = require(ReplicatedStorage.Shared.Audio)
local Maze = require(ReplicatedStorage.Shared.Maze)
local Interactables = require(script.Parent.Interactables)
local WorldBuilder = require(script.Parent.WorldBuilder)

local Remotes = ReplicatedStorage.Remotes

local Throwables = {}

export type Hooks = {
	isAlive: (player: Player) -> boolean,
	onNoise: (position: Vector3, radius: number) -> (),
}

export type Throwables = { destroy: () -> () }

Throwables.MAX_CARRY = 3
Throwables.RANGE = 55
Throwables.NOISE = 120

local BOTTLE_COLORS = { Color3.fromRGB(40, 90, 50), Color3.fromRGB(90, 60, 30), Color3.fromRGB(150, 160, 160) }

local function bottleModel(world: WorldBuilder.World, parent: Instance, cf: CFrame, color: Color3): BasePart
	local ctx = world.ctx
	local body = ctx.part(parent, "Bottle", Vector3.new(1.0, 0.45, 0.45), cf * CFrame.Angles(0, 0, math.rad(90)), Enum.Material.Glass, color, Enum.PartType.Cylinder)
	body.Transparency = 0.15
	body.CanCollide = false
	body.CanTouch = false
	local neck = ctx.decor(ctx.part(body, "Neck", Vector3.new(0.45, 0.18, 0.18), body.CFrame * CFrame.new(0.65, 0, 0), Enum.Material.Glass, color, Enum.PartType.Cylinder))
	neck.Transparency = 0.15
	return body
end

-- Where a throw lands: along the look direction until it hits something, then down to the floor.
local function landingPoint(world: WorldBuilder.World, origin: Vector3, look: Vector3, range: number): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { world.model }
	local flatLook = Vector3.new(look.X, math.clamp(look.Y, -0.5, 0.4), look.Z)
	if flatLook.Magnitude < 0.01 then
		flatLook = Vector3.new(0, 0, -1)
	end
	local dir = flatLook.Unit * range
	local hit = workspace:Raycast(origin, dir, params)
	local point = if hit then hit.Position - dir.Unit * 1.2 else origin + dir
	local down = workspace:Raycast(point + Vector3.new(0, 2, 0), Vector3.new(0, -40, 0), params)
	return if down then down.Position + Vector3.new(0, 0.2, 0) else Vector3.new(point.X, 0.2, point.Z)
end

function Throwables.new(layout: Maze.Layout, world: WorldBuilder.World, hooks: Hooks): Throwables
	local folder = Instance.new("Folder")
	folder.Name = "Bottles"
	folder.Parent = world.model
	local random = Random.new(layout.seed + 7)
	local connections: { RBXScriptConnection } = {}
	local destroyed = false

	-- scatter some bottles through the maze, away from objective spots and lockers
	local avoid: { [string]: boolean } = {}
	for _, s in layout.spots do
		avoid[Maze.key(s.x, s.z)] = true
	end
	for _, l in layout.lockers do
		avoid[Maze.key(l.x, l.z)] = true
	end
	local count = math.clamp(math.floor(layout.width * layout.depth / 16), 6, 12)
	local placed = 0
	local tries = 0
	while placed < count and tries < 200 do
		tries += 1
		local x, z = random:NextInteger(0, layout.width - 1), random:NextInteger(0, layout.depth - 1)
		local k = Maze.key(x, z)
		if not avoid[k] and not Maze.isHub(layout, x, z) then
			avoid[k] = true
			placed += 1
			local c = world.ctx.cellCenter(x, z)
			local cf = CFrame.new(c + Vector3.new(random:NextNumber(-3, 3), 0.23, random:NextNumber(-3, 3))) * CFrame.Angles(0, random:NextNumber(0, 6.28), 0)
			local bottle = bottleModel(world, folder, cf, BOTTLE_COLORS[random:NextInteger(1, #BOTTLE_COLORS)])
			bottle.CanQuery = true
			local p = Interactables.prompt(bottle, "Pick up", "Bottle", 0, 7)
			p.Triggered:Connect(function(player: Player)
				if destroyed or not hooks.isAlive(player) or bottle.Parent == nil then
					return
				end
				local have = player:GetAttribute("Bottles")
				local n = if typeof(have) == "number" then have else 0
				if n >= Throwables.MAX_CARRY then
					Remotes.Notify:FireClient(player, "You can't carry any more.")
					return
				end
				player:SetAttribute("Bottles", n + 1)
				Audio.play("KeypadBeep", bottle, 0.4, 0.5, 30)
				bottle:Destroy()
			end)
		end
	end

	table.insert(connections, Remotes.Throw.OnServerEvent:Connect(function(player: Player, look: unknown)
		if destroyed or typeof(look) ~= "Vector3" or look.Magnitude < 0.5 or look.Magnitude > 2 then
			return
		end
		if not hooks.isAlive(player) or player:GetAttribute("Hiding") == true then
			return
		end
		local have = player:GetAttribute("Bottles")
		local n = if typeof(have) == "number" then have else 0
		if n <= 0 then
			return
		end
		local character = player.Character
		local head = if character then character:FindFirstChild("Head") :: BasePart? else nil
		if not head then
			return
		end
		player:SetAttribute("Bottles", n - 1)
		local dir = look.Unit
		local origin = head.Position + dir * 1.5
		local target = landingPoint(world, origin, dir, Throwables.RANGE)
		local bottle = bottleModel(world, folder, CFrame.new(origin), BOTTLE_COLORS[random:NextInteger(1, #BOTTLE_COLORS)])
		Audio.play("BottleWhoosh", bottle, 0.8, 1, 40)
		local flight = math.clamp((target - origin).Magnitude / 60, 0.25, 0.9)
		local arc = math.clamp((target - origin).Magnitude * 0.12, 1, 6)
		local start = os.clock()
		local spin = random:NextNumber(8, 14)
		local conn: RBXScriptConnection? = nil
		conn = RunService.Heartbeat:Connect(function()
			local a = math.clamp((os.clock() - start) / flight, 0, 1)
			local pos = origin:Lerp(target, a) + Vector3.new(0, math.sin(a * math.pi) * arc, 0)
			bottle.CFrame = CFrame.new(pos) * CFrame.Angles(a * spin, 0, a * spin * 0.5)
			if a >= 1 then
				if conn then
					conn:Disconnect()
				end
				bottle:Destroy()
				Audio.playAt("GlassShatter", target, 1.7, random:NextNumber(0.9, 1.1), 150)
				for _ = 1, 6 do
					local shard = world.ctx.part(folder, "Shard", Vector3.new(0.35, 0.05, 0.25), CFrame.new(target + Vector3.new(random:NextNumber(-1.2, 1.2), 0, random:NextNumber(-1.2, 1.2))) * CFrame.Angles(0, random:NextNumber(0, 6), 0), Enum.Material.Glass, Color3.fromRGB(120, 150, 130), nil)
					shard.CanCollide = false
					shard.CanQuery = false
					shard.Transparency = 0.2
					Debris:AddItem(shard, 12)
				end
				if not destroyed then
					hooks.onNoise(target, Throwables.NOISE)
				end
			end
		end)
		table.insert(connections, conn :: RBXScriptConnection)
	end))

	return {
		destroy = function()
			destroyed = true
			for _, c in connections do
				c:Disconnect()
			end
		end,
	}
end

return Throwables
