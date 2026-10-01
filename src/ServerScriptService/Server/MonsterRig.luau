--!strict
-- Builds the monster out of parts: ~10 studs tall, hunched, a visible ribcage, arms
-- that drag along the floor, legs that bend the wrong way, a jaw that unhinges and
-- six glowing eyes. Every limb hangs off a Motor6D that clients animate
-- procedurally (see MonsterAnimator), so it twitches and jerks instead of walking.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Audio = require(ReplicatedStorage.Shared.Audio)

export type Rig = {
	model: Model,
	root: BasePart,
	humanoid: Humanoid,
	head: BasePart,
	growl: Sound?,
}

local MonsterRig = {}

MonsterRig.ROOT_HEIGHT = 5.2 -- HipHeight + half the root's height

local SKIN = Color3.fromRGB(14, 14, 14)
local SKIN_LIGHT = Color3.fromRGB(34, 34, 34)
local BONE = Color3.fromRGB(205, 200, 188)
local EYE = Color3.fromRGB(255, 255, 255)

local function limb(model: Model, name: string, size: Vector3, color: Color3?, material: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color or SKIN
	p.Material = material or Enum.Material.Slate
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CollisionGroup = "Monster"
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = model
	return p
end

-- Joint `child` to `parent`. c0 = joint position in parent space, c1 = in child space.
local function joint(name: string, parent: BasePart, child: BasePart, c0: CFrame, c1: CFrame): Motor6D
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = parent
	m.Part1 = child
	m.C0 = c0
	m.C1 = c1
	child.CFrame = parent.CFrame * c0 * c1:Inverse()
	m.Parent = parent
	return m
end

local function egg(p: BasePart)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
end

local function rad(deg: number): number
	return math.rad(deg)
end

function MonsterRig.build(): Rig
	local model = Instance.new("Model")
	model.Name = "Monster"

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1.5)
	root.Transparency = 1
	root.CanCollide = true
	root.CanQuery = false
	root.CollisionGroup = "Monster"
	root.CFrame = CFrame.new(0, MonsterRig.ROOT_HEIGHT, 0)
	root.Parent = model
	model.PrimaryPart = root

	-- body
	local pelvis = limb(model, "Pelvis", Vector3.new(1.9, 1.1, 1.2))
	joint("Waist", root, pelvis, CFrame.new(0, 0.2, 0), CFrame.new())

	local torso = limb(model, "Torso", Vector3.new(2.5, 3, 1.4))
	joint("Spine", pelvis, torso, CFrame.new(0, 0.5, 0) * CFrame.Angles(rad(-32), 0, 0), CFrame.new(0, -1.5, 0))
	for i, y in { 0.35, -0.2, -0.75 } do
		local rib = limb(model, "Rib", Vector3.new(2.2 - i * 0.2, 0.16, 0.1), BONE, Enum.Material.SmoothPlastic)
		joint("RibJoint", torso, rib, CFrame.new(0, y, -0.72), CFrame.new())
	end
	for i = 0, 3 do
		local spike = limb(model, "Spike", Vector3.new(0.28, 0.9 - i * 0.1, 0.28), BONE, Enum.Material.SmoothPlastic)
		joint("SpikeJoint", torso, spike, CFrame.new(0, 1.1 - i * 0.65, 0.72) * CFrame.Angles(rad(-35), 0, 0), CFrame.new(0, -0.3, 0))
	end

	-- head: an elongated skull with an unhinged jaw
	local head = limb(model, "Head", Vector3.new(1.5, 2.3, 1.8), SKIN_LIGHT)
	egg(head)
	joint("Neck", torso, head, CFrame.new(0, 1.5, -0.2) * CFrame.Angles(rad(27), 0, 0), CFrame.new(0, -0.9, 0.3))

	local gullet = limb(model, "Gullet", Vector3.new(1.05, 0.7, 0.9), Color3.new(0, 0, 0), Enum.Material.SmoothPlastic)
	joint("GulletJoint", head, gullet, CFrame.new(0, -0.55, -0.45), CFrame.new())

	local jaw = limb(model, "Jaw", Vector3.new(1.25, 0.3, 1.3), SKIN_LIGHT)
	joint("Jaw", head, jaw, CFrame.new(0, -0.8, 0.2), CFrame.new(0, 0, 0.6))
	for i = -2, 2 do
		local lower = limb(model, "Tooth", Vector3.new(0.12, 0.38, 0.12), BONE, Enum.Material.SmoothPlastic)
		joint("ToothJoint", jaw, lower, CFrame.new(i * 0.24, 0.3, -0.5 + math.abs(i) * 0.1), CFrame.new())
		local upper = limb(model, "Tooth", Vector3.new(0.12, 0.42, 0.12), BONE, Enum.Material.SmoothPlastic)
		joint("ToothJoint", head, upper, CFrame.new(i * 0.24 + 0.05, -0.85, -0.62 + math.abs(i) * 0.1), CFrame.new())
	end

	local eyes: { { any } } = {
		{ 0.42, Vector3.new(0.32, 0.35, -0.8) },
		{ 0.26, Vector3.new(-0.35, 0.42, -0.78) },
		{ 0.2, Vector3.new(-0.08, 0.68, -0.72) },
		{ 0.22, Vector3.new(0.48, 0.74, -0.6) },
		{ 0.18, Vector3.new(-0.55, 0.08, -0.64) },
		{ 0.16, Vector3.new(0.06, 0.12, -0.86) },
	}
	for i, e in eyes do
		local size = e[1] :: number
		local eye = limb(model, "Eye", Vector3.new(size, size, size), EYE, Enum.Material.Neon, Enum.PartType.Ball)
		eye.CastShadow = false
		joint("EyeJoint", head, eye, CFrame.new(e[2] :: Vector3), CFrame.new())
		if i == 1 then
			local light = Instance.new("PointLight")
			light.Name = "EyeGlow"
			light.Range = 9
			light.Brightness = 1.2
			light.Shadows = false
			light.Parent = eye
		end
	end

	-- arms: long enough to drag their fingers along the floor
	for _, side in { -1, 1 } do
		local prefix = if side < 0 then "L" else "R"
		local upper = limb(model, prefix .. "UpperArm", Vector3.new(0.55, 3.4, 0.55))
		joint(prefix .. "Shoulder", torso, upper, CFrame.new(side * 1.45, 1.2, 0) * CFrame.Angles(rad(32), 0, rad(side * 7)), CFrame.new(0, 1.7, 0))
		local lower = limb(model, prefix .. "LowerArm", Vector3.new(0.45, 3.2, 0.45))
		joint(prefix .. "Elbow", upper, lower, CFrame.new(0, -1.7, 0) * CFrame.Angles(rad(-10), 0, 0), CFrame.new(0, 1.6, 0))
		local hand = limb(model, prefix .. "Hand", Vector3.new(0.65, 0.5, 0.4), SKIN_LIGHT)
		joint(prefix .. "Wrist", lower, hand, CFrame.new(0, -1.6, 0), CFrame.new(0, 0.25, 0))
		for f = 0, 3 do
			local finger = limb(model, prefix .. "Finger", Vector3.new(0.12, 1.5, 0.12), SKIN_LIGHT)
			joint(prefix .. "Finger" .. (f + 1), hand, finger, CFrame.new(-0.24 + f * 0.16, -0.25, 0) * CFrame.Angles(rad(-10), 0, rad(-12 + f * 8)), CFrame.new(0, 0.75, 0))
		end
	end

	-- legs: thigh forward, shin back (digitigrade)
	for _, side in { -1, 1 } do
		local prefix = if side < 0 then "L" else "R"
		local thigh = limb(model, prefix .. "Thigh", Vector3.new(0.8, 2.7, 0.8))
		joint(prefix .. "Hip", pelvis, thigh, CFrame.new(side * 0.65, -0.3, 0) * CFrame.Angles(rad(30), 0, 0), CFrame.new(0, 1.35, 0))
		local shin = limb(model, prefix .. "Shin", Vector3.new(0.6, 3, 0.6))
		joint(prefix .. "Knee", thigh, shin, CFrame.new(0, -1.35, 0) * CFrame.Angles(rad(-65), 0, 0), CFrame.new(0, 1.5, 0))
		local foot = limb(model, prefix .. "Foot", Vector3.new(0.7, 0.35, 1.6), SKIN_LIGHT)
		joint(prefix .. "Ankle", shin, foot, CFrame.new(0, -1.5, 0) * CFrame.Angles(rad(35), 0, 0), CFrame.new(0, 0, 0.6))
	end

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = MonsterRig.ROOT_HEIGHT - root.Size.Y / 2
	humanoid.WalkSpeed = 0
	humanoid.MaxHealth = 1e6
	humanoid.Health = 1e6
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.UseJumpPower = true
	humanoid.JumpPower = 0
	humanoid.Parent = model
	for _, s in { Enum.HumanoidStateType.Dead, Enum.HumanoidStateType.Jumping, Enum.HumanoidStateType.Climbing, Enum.HumanoidStateType.Swimming, Enum.HumanoidStateType.FallingDown, Enum.HumanoidStateType.Ragdoll, Enum.HumanoidStateType.Seated } do
		humanoid:SetStateEnabled(s, false)
	end

	local growl = Audio.create("MonsterGrowlLoop", head, 1.2)
	if growl then
		growl.RollOffMode = Enum.RollOffMode.InverseTapered
		growl.RollOffMinDistance = 8
		growl.RollOffMaxDistance = 90
	end

	model:SetAttribute("State", "Dormant")
	model:SetAttribute("TargetUserId", 0)

	return {
		model = model,
		root = root,
		humanoid = humanoid,
		head = head,
		growl = growl,
	}
end

return MonsterRig
