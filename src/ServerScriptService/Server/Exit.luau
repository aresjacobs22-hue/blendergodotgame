--!strict
-- The way out, in the hub's south wall. Styles:
--   double  two heavy doors that swing outward (house, ward)
--   grand   the same, tall and bronze (atrium)
--   lift    two steel doors that slide apart (sewer)
--   portal  a dark membrane that dissolves (void)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Audio = require(ReplicatedStorage.Shared.Audio)
local WorldBuilder = require(script.Parent.WorldBuilder)

type World = WorldBuilder.World

local Exit = {}
Exit.__index = Exit

export type Exit = typeof(setmetatable(
	{} :: {
		world: World,
		style: string,
		frame: CFrame,
		folder: Folder,
		leaves: { { part: BasePart, opened: CFrame } },
		membrane: BasePart?,
		isOpen: boolean,
		width: number,
		height: number,
	},
	Exit
))

function Exit.new(world: World): Exit
	local ctx = world.ctx
	local folder = Instance.new("Folder")
	folder.Name = "Exit"
	folder.Parent = world.model
	local style = world.theme.exitStyle
	local frame = world.exitFrame
	local w, h = ctx.exitWidth, ctx.exitHeight

	local self = setmetatable({
		world = world,
		style = style,
		frame = frame,
		folder = folder,
		leaves = {},
		membrane = nil :: BasePart?,
		isOpen = false,
		width = w,
		height = h,
	}, Exit)

	if style == "portal" then
		local membrane = ctx.part(folder, "Membrane", Vector3.new(w, h, 0.3), frame * CFrame.new(0, h / 2, 0), Enum.Material.Neon, Color3.fromRGB(40, 0, 60), nil)
		membrane.Transparency = 0.1
		membrane.CastShadow = true
		self.membrane = membrane
	else
		local material = Enum.Material.DiamondPlate
		local color = Color3.fromRGB(86, 86, 90)
		if style == "grand" then
			material = Enum.Material.Metal
			color = Color3.fromRGB(150, 112, 60)
		elseif style == "lift" then
			material = Enum.Material.Metal
			color = Color3.fromRGB(120, 124, 126)
		elseif world.night.theme == "ward" then
			material = Enum.Material.Metal
			color = Color3.fromRGB(190, 192, 194)
		end
		for _, sx in { -1, 1 } do
			local closed = frame * CFrame.new(sx * w / 4, h / 2 + 0.02, 0)
			local opened: CFrame
			if style == "lift" then
				opened = closed * CFrame.new(sx * (w / 2 - 0.3), 0, 0)
			else
				local hinge = frame * CFrame.new(sx * w / 2, h / 2 + 0.02, 0)
				opened = hinge * CFrame.Angles(0, math.rad(-sx * 95), 0) * hinge:Inverse() * closed
			end
			local leaf = ctx.part(folder, "ExitDoor", Vector3.new(w / 2 - 0.08, h - 0.05, 0.5), closed, material, color, nil)
			if world.night.theme == "ward" then
				-- round porthole windows
				local window = ctx.part(folder, "Porthole", Vector3.new(0.6, 1.3, 1.3), closed * CFrame.new(0, h * 0.18, 0) * CFrame.Angles(0, math.rad(90), 0), Enum.Material.Glass, Color3.fromRGB(40, 10, 10), Enum.PartType.Cylinder)
				window.Anchored = false
				window.CanCollide = false
				window.Massless = true
				window.Transparency = 0.3
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = leaf
				weld.Part1 = window
				weld.Parent = window
			end
			table.insert(self.leaves, { part = leaf :: BasePart, opened = opened })
		end
	end
	return self
end

-- Where to hang padlocks / mount a keypad: frame offsets on the hub side.
function Exit.hubSide(self: Exit, x: number, y: number): CFrame
	return self.frame * CFrame.new(x, y, 0.5)
end

function Exit.open(self: Exit)
	if self.isOpen then
		return
	end
	self.isOpen = true
	local anchor = if self.membrane then self.membrane else self.leaves[1].part
	Audio.play("Unlock", anchor, 1.2, 1, 120)
	task.delay(0.6, function()
		if not self.folder.Parent then
			return
		end
		local membrane = self.membrane
		if membrane then
			membrane.CanCollide = false
			TweenService:Create(membrane, TweenInfo.new(2, Enum.EasingStyle.Sine), { Transparency = 1 }):Play()
			Audio.play("HeartShatter", membrane, 1, 0.6, 140)
		else
			for _, leaf in self.leaves do
				TweenService:Create(leaf.part, TweenInfo.new(if self.style == "lift" then 2 else 2.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { CFrame = leaf.opened }):Play()
			end
			Audio.play("DoorOpen", anchor, 1.4, if self.style == "lift" then 0.8 else 0.55, 140)
		end
		self.world.exitLight.Enabled = true
	end)
end

return Exit
