--!strict
-- The five monsters, built from parts. Every limb hangs off a Motor6D so clients can
-- animate them procedurally (MonsterAnimator). Shared so the menu can show previews.
--
--   Hollow   night 1  tall, arms dragging on the floor, jaw hanging open
--   Crawler  night 2  pale, low, eight long legs, an upside-down face
--   Listener night 3  eyeless, long drooping neck, mouth that splits sideways
--   Statue   night 4  marble, only moves when unseen, a new pose every time
--   Amalgam  night 5  three heads, six arms, four legs, a glowing core

local Audio = require(script.Parent.Audio)

export type Rig = {
	model: Model,
	root: BasePart,
	humanoid: Humanoid?,
	head: BasePart,
	growl: Sound?,
	rootHeight: number,
	kind: string,
	joints: { Motor6D },
}

export type Options = {
	preview: boolean?, -- no Humanoid, no sounds, anchored: for menus and decoys
	decoy: boolean?, -- a harmless look-alike (statue night)
}

type Builder = {
	limb: (name: string, size: Vector3, color: Color3?, material: Enum.Material?, shape: Enum.PartType?) -> Part,
	joint: (name: string, parent: BasePart, child: BasePart, c0: CFrame, c1: CFrame) -> Motor6D,
	model: Model,
	root: Part,
}

local Monsters = {}

local function rad(deg: number): number
	return math.rad(deg)
end

local function egg(p: BasePart)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
end

local function newBuilder(kind: string, rootHeight: number, options: Options): (Builder, { Motor6D })
	local model = Instance.new("Model")
	model.Name = if options.decoy then "Statue" else "Monster"
	local preview = options.preview == true

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1.5)
	root.Transparency = 1
	root.CanCollide = not preview
	root.CanQuery = false
	root.Anchored = preview
	if not preview then
		root.CollisionGroup = "Monster"
	end
	root.CFrame = CFrame.new(0, rootHeight, 0)
	root.Parent = model
	model.PrimaryPart = root

	local joints: { Motor6D } = {}
	local b: Builder = {
		model = model,
		root = root,
		limb = function(name: string, size: Vector3, color: Color3?, material: Enum.Material?, shape: Enum.PartType?): Part
			local p = Instance.new("Part")
			p.Name = name
			p.Size = size
			p.Color = color or Color3.fromRGB(14, 14, 14)
			p.Material = material or Enum.Material.Slate
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.Massless = true
			if not preview then
				p.CollisionGroup = "Monster"
			end
			p.TopSurface = Enum.SurfaceType.Smooth
			p.BottomSurface = Enum.SurfaceType.Smooth
			if shape then
				p.Shape = shape
			end
			p.Parent = model
			return p
		end,
		joint = function(name: string, parent: BasePart, child: BasePart, c0: CFrame, c1: CFrame): Motor6D
			local m = Instance.new("Motor6D")
			m.Name = name
			m.Part0 = parent
			m.Part1 = child
			m.C0 = c0
			m.C1 = c1
			child.CFrame = parent.CFrame * c0 * c1:Inverse()
			m.Parent = parent
			table.insert(joints, m)
			return m
		end,
	}
	model:SetAttribute("Kind", kind)
	return b, joints
end

local function eye(b: Builder, parent: BasePart, size: number, at: Vector3, color: Color3, glow: boolean?): Part
	local e = b.limb("Eye", Vector3.new(size, size, size), color, Enum.Material.Neon, Enum.PartType.Ball)
	e.CastShadow = false
	b.joint("EyeJoint", parent, e, CFrame.new(at), CFrame.new())
	if glow then
		local light = Instance.new("PointLight")
		light.Name = "EyeGlow"
		light.Range = 9
		light.Brightness = 1.2
		light.Color = color
		light.Shadows = false
		light.Parent = e
	end
	return e
end

local function tooth(b: Builder, parent: BasePart, at: CFrame, length: number, color: Color3)
	local t = b.limb("Tooth", Vector3.new(0.12, length, 0.12), color, Enum.Material.SmoothPlastic)
	b.joint("ToothJoint", parent, t, at, CFrame.new())
end

---------------------------------------------------------------------------
-- Night 1: THE HOLLOW

local function buildHollow(b: Builder): (BasePart, number)
	local SKIN = Color3.fromRGB(14, 14, 14)
	local SKIN_LIGHT = Color3.fromRGB(34, 34, 34)
	local BONE = Color3.fromRGB(205, 200, 188)
	local limb, joint = b.limb, b.joint

	local pelvis = limb("Pelvis", Vector3.new(1.9, 1.1, 1.2), SKIN)
	joint("Waist", b.root, pelvis, CFrame.new(0, 0.2, 0), CFrame.new())
	local torso = limb("Torso", Vector3.new(2.5, 3, 1.4), SKIN)
	joint("Spine", pelvis, torso, CFrame.new(0, 0.5, 0) * CFrame.Angles(rad(-32), 0, 0), CFrame.new(0, -1.5, 0))
	for i, y in { 0.35, -0.2, -0.75 } do
		local rib = limb("Rib", Vector3.new(2.2 - i * 0.2, 0.16, 0.1), BONE, Enum.Material.SmoothPlastic)
		joint("RibJoint", torso, rib, CFrame.new(0, y, -0.72), CFrame.new())
	end
	for i = 0, 3 do
		local spike = limb("Spike", Vector3.new(0.28, 0.9 - i * 0.1, 0.28), BONE, Enum.Material.SmoothPlastic)
		joint("SpikeJoint", torso, spike, CFrame.new(0, 1.1 - i * 0.65, 0.72) * CFrame.Angles(rad(-35), 0, 0), CFrame.new(0, -0.3, 0))
	end

	local head = limb("Head", Vector3.new(1.5, 2.3, 1.8), SKIN_LIGHT)
	egg(head)
	joint("Neck", torso, head, CFrame.new(0, 1.5, -0.2) * CFrame.Angles(rad(27), 0, 0), CFrame.new(0, -0.9, 0.3))
	local gullet = limb("Gullet", Vector3.new(1.05, 0.7, 0.9), Color3.new(0, 0, 0), Enum.Material.SmoothPlastic)
	joint("GulletJoint", head, gullet, CFrame.new(0, -0.55, -0.45), CFrame.new())
	local jaw = limb("Jaw", Vector3.new(1.25, 0.3, 1.3), SKIN_LIGHT)
	joint("Jaw", head, jaw, CFrame.new(0, -0.8, 0.2), CFrame.new(0, 0, 0.6))
	for i = -2, 2 do
		tooth(b, jaw, CFrame.new(i * 0.24, 0.3, -0.5 + math.abs(i) * 0.1), 0.38, BONE)
		tooth(b, head, CFrame.new(i * 0.24 + 0.05, -0.85, -0.62 + math.abs(i) * 0.1), 0.42, BONE)
	end
	local white = Color3.new(1, 1, 1)
	eye(b, head, 0.42, Vector3.new(0.32, 0.35, -0.8), white, true)
	eye(b, head, 0.26, Vector3.new(-0.35, 0.42, -0.78), white)
	eye(b, head, 0.2, Vector3.new(-0.08, 0.68, -0.72), white)
	eye(b, head, 0.22, Vector3.new(0.48, 0.74, -0.6), white)
	eye(b, head, 0.18, Vector3.new(-0.55, 0.08, -0.64), white)
	eye(b, head, 0.16, Vector3.new(0.06, 0.12, -0.86), white)

	for _, side in { -1, 1 } do
		local p = if side < 0 then "L" else "R"
		local upper = limb(p .. "UpperArm", Vector3.new(0.55, 3.4, 0.55), SKIN)
		joint(p .. "Shoulder", torso, upper, CFrame.new(side * 1.45, 1.2, 0) * CFrame.Angles(rad(32), 0, rad(side * 7)), CFrame.new(0, 1.7, 0))
		local lower = limb(p .. "LowerArm", Vector3.new(0.45, 3.2, 0.45), SKIN)
		joint(p .. "Elbow", upper, lower, CFrame.new(0, -1.7, 0) * CFrame.Angles(rad(-10), 0, 0), CFrame.new(0, 1.6, 0))
		local hand = limb(p .. "Hand", Vector3.new(0.65, 0.5, 0.4), SKIN_LIGHT)
		joint(p .. "Wrist", lower, hand, CFrame.new(0, -1.6, 0), CFrame.new(0, 0.25, 0))
		for f = 0, 3 do
			local finger = limb(p .. "Finger", Vector3.new(0.12, 1.5, 0.12), SKIN_LIGHT)
			joint(p .. "Finger" .. (f + 1), hand, finger, CFrame.new(-0.24 + f * 0.16, -0.25, 0) * CFrame.Angles(rad(-10), 0, rad(-12 + f * 8)), CFrame.new(0, 0.75, 0))
		end
	end
	for _, side in { -1, 1 } do
		local p = if side < 0 then "L" else "R"
		local thigh = limb(p .. "Thigh", Vector3.new(0.8, 2.7, 0.8), SKIN)
		joint(p .. "Hip", pelvis, thigh, CFrame.new(side * 0.65, -0.3, 0) * CFrame.Angles(rad(30), 0, 0), CFrame.new(0, 1.35, 0))
		local shin = limb(p .. "Shin", Vector3.new(0.6, 3, 0.6), SKIN)
		joint(p .. "Knee", thigh, shin, CFrame.new(0, -1.35, 0) * CFrame.Angles(rad(-65), 0, 0), CFrame.new(0, 1.5, 0))
		local foot = limb(p .. "Foot", Vector3.new(0.7, 0.35, 1.6), SKIN_LIGHT)
		joint(p .. "Ankle", shin, foot, CFrame.new(0, -1.5, 0) * CFrame.Angles(rad(35), 0, 0), CFrame.new(0, 0, 0.6))
	end
	return head, 5.2
end

---------------------------------------------------------------------------
-- Night 2: THE CRAWLER

local function buildCrawler(b: Builder): (BasePart, number)
	local PALE = Color3.fromRGB(205, 194, 186)
	local DARK = Color3.fromRGB(96, 84, 80)
	local BONE = Color3.fromRGB(230, 222, 210)
	local limb, joint = b.limb, b.joint
	local smooth = Enum.Material.SmoothPlastic

	local body = limb("Body", Vector3.new(2.2, 1.2, 4.2), PALE, smooth)
	egg(body)
	joint("Waist", b.root, body, CFrame.new(0, 0.4, 0), CFrame.new())
	local abdomen = limb("Abdomen", Vector3.new(1.8, 1.3, 2.8), PALE, smooth)
	egg(abdomen)
	joint("Tail", body, abdomen, CFrame.new(0, 0.2, 2) * CFrame.Angles(rad(12), 0, 0), CFrame.new(0, 0, -1.2))
	for i = 0, 5 do
		local spike = limb("Spike", Vector3.new(0.18, 0.6, 0.18), BONE, smooth)
		joint("SpikeJoint", body, spike, CFrame.new(0, 0.55, -1.6 + i * 0.65) * CFrame.Angles(rad(30), 0, 0), CFrame.new(0, -0.25, 0))
	end

	-- the head hangs off the front with its face upside down: eyes at the bottom, mouth on top
	local head = limb("Head", Vector3.new(1.4, 1.6, 1.5), PALE, smooth)
	egg(head)
	joint("Neck", body, head, CFrame.new(0, 0.35, -2.2) * CFrame.Angles(rad(-8), 0, 0), CFrame.new(0, 0, 0.55))
	local mouth = limb("Mouth", Vector3.new(0.95, 0.35, 0.3), Color3.new(0, 0, 0), smooth)
	joint("MouthJoint", head, mouth, CFrame.new(0, 0.42, -0.6), CFrame.new())
	local jaw = limb("Jaw", Vector3.new(0.95, 0.22, 0.65), PALE, smooth)
	joint("Jaw", head, jaw, CFrame.new(0, 0.62, -0.3), CFrame.new(0, 0, 0.3))
	for i = -2, 2 do
		tooth(b, jaw, CFrame.new(i * 0.18, -0.2, -0.28), 0.3, BONE)
		tooth(b, head, CFrame.new(i * 0.18, 0.28, -0.68), 0.28, BONE)
	end
	local pale = Color3.fromRGB(255, 245, 235)
	eye(b, head, 0.42, Vector3.new(-0.3, -0.35, -0.6), pale, true)
	eye(b, head, 0.42, Vector3.new(0.3, -0.35, -0.6), pale)

	-- eight legs, knees arched above the body like a spider
	local zs = { -1.5, -0.55, 0.45, 1.4 }
	local yaws = { 35, 12, -12, -35 }
	for i = 1, 4 do
		for _, side in { -1, 1 } do
			local p = (if side < 0 then "L" else "R") .. i
			local upper = limb(p .. "UpperLeg", Vector3.new(0.28, 2.6, 0.28), DARK, smooth)
			joint(p .. "Hip", body, upper, CFrame.new(side * 1.0, 0.2, zs[i]) * CFrame.Angles(0, side * rad(yaws[i]), 0) * CFrame.Angles(0, 0, side * rad(150)), CFrame.new(0, 1.3, 0))
			local lower = limb(p .. "LowerLeg", Vector3.new(0.2, 5, 0.2), PALE, smooth)
			joint(p .. "Knee", upper, lower, CFrame.new(0, -1.3, 0) * CFrame.Angles(0, 0, side * rad(-141)), CFrame.new(0, 2.5, 0))
		end
	end
	return head, 2.3
end

---------------------------------------------------------------------------
-- Night 3: THE LISTENER

local function buildListener(b: Builder): (BasePart, number)
	local SKIN = Color3.fromRGB(46, 54, 50)
	local SKIN_LIGHT = Color3.fromRGB(70, 80, 74)
	local BONE = Color3.fromRGB(200, 205, 190)
	local GLOW = Color3.fromRGB(120, 255, 190)
	local limb, joint = b.limb, b.joint
	local wet = Enum.Material.SmoothPlastic

	local pelvis = limb("Pelvis", Vector3.new(1.6, 1, 1), SKIN, wet)
	pelvis.Reflectance = 0.15
	joint("Waist", b.root, pelvis, CFrame.new(0, 0.2, 0), CFrame.new())
	local torso = limb("Torso", Vector3.new(1.8, 3, 1), SKIN, wet)
	torso.Reflectance = 0.15
	joint("Spine", pelvis, torso, CFrame.new(0, 0.4, 0) * CFrame.Angles(rad(-15), 0, 0), CFrame.new(0, -1.5, 0))
	for i = 0, 3 do
		local rib = limb("Rib", Vector3.new(1.7, 0.14, 0.12), BONE, wet)
		joint("RibJoint", torso, rib, CFrame.new(0, 0.9 - i * 0.45, -0.52), CFrame.new())
	end
	-- faint glowing spots down its back: the only way to see it in the dark
	for i = 0, 4 do
		local spot = limb("Glow", Vector3.new(0.22, 0.22, 0.22), GLOW, Enum.Material.Neon, Enum.PartType.Ball)
		spot.CastShadow = false
		joint("GlowJoint", torso, spot, CFrame.new((i % 2 - 0.5) * 0.5, 1.2 - i * 0.55, 0.52), CFrame.new())
	end
	local glow = Instance.new("PointLight")
	glow.Name = "EyeGlow"
	glow.Color = GLOW
	glow.Range = 8
	glow.Brightness = 0.7
	glow.Parent = torso

	local a = limb("NeckA", Vector3.new(0.45, 1, 0.45), SKIN, wet)
	joint("NeckA", torso, a, CFrame.new(0, 1.5, -0.1) * CFrame.Angles(rad(-30), 0, 0), CFrame.new(0, -0.5, 0))
	local nb = limb("NeckB", Vector3.new(0.4, 1, 0.4), SKIN, wet)
	joint("NeckB", a, nb, CFrame.new(0, 0.5, 0) * CFrame.Angles(rad(-20), 0, 0), CFrame.new(0, -0.5, 0))
	local nc = limb("NeckC", Vector3.new(0.38, 1, 0.38), SKIN, wet)
	joint("NeckC", nb, nc, CFrame.new(0, 0.5, 0) * CFrame.Angles(rad(-20), 0, 0), CFrame.new(0, -0.5, 0))

	-- eyeless skull, long and smooth
	local head = limb("Head", Vector3.new(1.2, 1.4, 2.4), SKIN_LIGHT, wet)
	egg(head)
	head.Reflectance = 0.2
	joint("Neck", nc, head, CFrame.new(0, 0.5, 0) * CFrame.Angles(rad(70), 0, 0), CFrame.new(0, -0.2, 0.7))
	local gullet = limb("Gullet", Vector3.new(0.5, 1, 1.2), Color3.new(0, 0, 0), wet)
	joint("GulletJoint", head, gullet, CFrame.new(0, -0.1, -0.7), CFrame.new())
	-- the mouth splits sideways into two halves
	for _, side in { -1, 1 } do
		local p = if side < 0 then "L" else "R"
		local half = limb("Jaw" .. p, Vector3.new(0.35, 1.1, 1.4), SKIN_LIGHT, wet)
		joint("Jaw" .. p, head, half, CFrame.new(side * 0.32, -0.1, -0.6), CFrame.new(0, 0, 0.6))
		for t = 0, 3 do
			tooth(b, half, CFrame.new(-side * 0.18, -0.4 + t * 0.27, -0.55) * CFrame.Angles(0, 0, rad(90)), 0.3, BONE)
		end
		local ear = limb("Ear" .. p, Vector3.new(0.08, 1.5, 1.3), SKIN_LIGHT, wet)
		ear.Transparency = 0.15
		joint("Ear" .. p, head, ear, CFrame.new(side * 0.6, 0.25, 0.3) * CFrame.Angles(0, 0, side * rad(-25)), CFrame.new(0, -0.5, 0))
	end

	-- long arms held up near its head, listening
	for _, side in { -1, 1 } do
		local p = if side < 0 then "L" else "R"
		local upper = limb(p .. "UpperArm", Vector3.new(0.35, 3, 0.35), SKIN, wet)
		joint(p .. "Shoulder", torso, upper, CFrame.new(side * 1.0, 1.3, 0) * CFrame.Angles(rad(75), 0, rad(side * 20)), CFrame.new(0, 1.5, 0))
		local lower = limb(p .. "LowerArm", Vector3.new(0.3, 3, 0.3), SKIN, wet)
		joint(p .. "Elbow", upper, lower, CFrame.new(0, -1.5, 0) * CFrame.Angles(rad(70), 0, 0), CFrame.new(0, 1.5, 0))
		local hand = limb(p .. "Hand", Vector3.new(0.5, 0.4, 0.3), SKIN_LIGHT, wet)
		joint(p .. "Wrist", lower, hand, CFrame.new(0, -1.5, 0), CFrame.new(0, 0.2, 0))
		for f = 0, 2 do
			local finger = limb(p .. "Finger", Vector3.new(0.1, 1.6, 0.1), SKIN_LIGHT, wet)
			joint(p .. "Finger" .. (f + 1), hand, finger, CFrame.new(-0.15 + f * 0.15, -0.2, 0) * CFrame.Angles(rad(-15), 0, rad(-10 + f * 10)), CFrame.new(0, 0.8, 0))
		end
	end
	for _, side in { -1, 1 } do
		local p = if side < 0 then "L" else "R"
		local thigh = limb(p .. "Thigh", Vector3.new(0.5, 2.6, 0.5), SKIN, wet)
		joint(p .. "Hip", pelvis, thigh, CFrame.new(side * 0.5, -0.3, 0) * CFrame.Angles(rad(10), 0, 0), CFrame.new(0, 1.3, 0))
		local shin = limb(p .. "Shin", Vector3.new(0.4, 2.6, 0.4), SKIN, wet)
		joint(p .. "Knee", thigh, shin, CFrame.new(0, -1.3, 0) * CFrame.Angles(rad(-20), 0, 0), CFrame.new(0, 1.3, 0))
		local foot = limb(p .. "Foot", Vector3.new(0.55, 0.3, 1.5), SKIN_LIGHT, wet)
		joint(p .. "Ankle", shin, foot, CFrame.new(0, -1.3, 0) * CFrame.Angles(rad(10), 0, 0), CFrame.new(0, 0, 0.5))
	end
	return head, 5
end

---------------------------------------------------------------------------
-- Night 4: THE STATUE

-- Offsets applied on top of the statue's rest pose. A new one each time it moves.
Monsters.STATUE_POSES = {
	{ -- reaching for you
		LShoulder = CFrame.Angles(rad(85), 0, rad(-8)),
		RShoulder = CFrame.Angles(rad(85), 0, rad(8)),
		Neck = CFrame.Angles(rad(-8), 0, 0),
	},
	{ -- weeping, hands over its face
		LShoulder = CFrame.Angles(rad(140), 0, rad(25)),
		RShoulder = CFrame.Angles(rad(140), 0, rad(-25)),
		LElbow = CFrame.Angles(rad(95), 0, 0),
		RElbow = CFrame.Angles(rad(95), 0, 0),
		Neck = CFrame.Angles(rad(18), 0, 0),
	},
	{ -- pointing at you
		RShoulder = CFrame.Angles(rad(95), rad(-10), 0),
		LShoulder = CFrame.Angles(rad(10), 0, rad(-10)),
		Neck = CFrame.Angles(0, rad(-25), rad(10)),
	},
	{ -- mid-lunge
		Spine = CFrame.Angles(rad(-25), 0, 0),
		LShoulder = CFrame.Angles(rad(70), 0, rad(-30)),
		RShoulder = CFrame.Angles(rad(70), 0, rad(30)),
		LElbow = CFrame.Angles(rad(30), 0, 0),
		RElbow = CFrame.Angles(rad(30), 0, 0),
		Neck = CFrame.Angles(rad(-25), 0, 0),
	},
	{ -- head tilted all the way over
		Neck = CFrame.Angles(rad(5), rad(10), rad(65)),
		Spine = CFrame.Angles(0, rad(15), rad(-6)),
		LShoulder = CFrame.Angles(rad(-10), 0, rad(-6)),
	},
	{ -- arms up, about to grab
		LShoulder = CFrame.Angles(rad(165), 0, rad(-15)),
		RShoulder = CFrame.Angles(rad(165), 0, rad(15)),
		LElbow = CFrame.Angles(rad(40), 0, 0),
		RElbow = CFrame.Angles(rad(40), 0, 0),
		Neck = CFrame.Angles(rad(-15), 0, 0),
	},
} :: { { [string]: CFrame } }

local function buildStatue(b: Builder, decoy: boolean): (BasePart, number)
	local MARBLE = Color3.fromRGB(226, 225, 219)
	local ROBE = Color3.fromRGB(206, 205, 198)
	local limb, joint = b.limb, b.joint
	local marble = Enum.Material.Marble

	local pelvis = limb("Pelvis", Vector3.new(1.8, 1, 1.1), ROBE, marble)
	joint("Waist", b.root, pelvis, CFrame.new(0, 0.2, 0), CFrame.new())
	local robe = limb("Robe", Vector3.new(2.9, 4.6, 2.4), ROBE, marble)
	egg(robe)
	joint("RobeJoint", pelvis, robe, CFrame.new(0, -2, 0), CFrame.new())
	local hem = limb("Hem", Vector3.new(2.6, 0.6, 2.2), ROBE, marble, Enum.PartType.Cylinder)
	joint("HemJoint", pelvis, hem, CFrame.new(0, -3.9, 0) * CFrame.Angles(0, 0, rad(90)), CFrame.new())
	local torso = limb("Torso", Vector3.new(2.2, 2.8, 1.2), MARBLE, marble)
	joint("Spine", pelvis, torso, CFrame.new(0, 0.5, 0), CFrame.new(0, -1.4, 0))
	local head = limb("Head", Vector3.new(1.3, 1.6, 1.4), MARBLE, marble)
	egg(head)
	joint("Neck", torso, head, CFrame.new(0, 1.4, 0), CFrame.new(0, -0.95, 0))
	-- hollow eyes; the real one has something glowing in them
	for _, side in { -1, 1 } do
		local socket = limb("Socket", Vector3.new(0.3, 0.2, 0.12), Color3.fromRGB(10, 10, 10), Enum.Material.SmoothPlastic)
		joint("SocketJoint", head, socket, CFrame.new(side * 0.28, 0.12, -0.64), CFrame.new())
		if not decoy then
			eye(b, head, 0.12, Vector3.new(side * 0.28, 0.12, -0.67), Color3.fromRGB(255, 60, 50), side < 0)
		end
	end
	local mouth = limb("MouthLine", Vector3.new(0.4, 0.06, 0.1), Color3.fromRGB(40, 40, 40), Enum.Material.SmoothPlastic)
	joint("MouthJoint", head, mouth, CFrame.new(0, -0.38, -0.66), CFrame.new())
	-- cracks
	for i = 1, 4 do
		local crack = limb("Crack", Vector3.new(0.05, 0.9, 0.05), Color3.fromRGB(70, 70, 68), Enum.Material.SmoothPlastic)
		joint("CrackJoint", torso, crack, CFrame.new(-0.6 + i * 0.3, 0.3 - i * 0.2, -0.61) * CFrame.Angles(0, 0, rad(25 * (i % 2 * 2 - 1))), CFrame.new())
	end
	for _, side in { -1, 1 } do
		local p = if side < 0 then "L" else "R"
		local upper = limb(p .. "UpperArm", Vector3.new(0.6, 2.4, 0.6), MARBLE, marble)
		joint(p .. "Shoulder", torso, upper, CFrame.new(side * 1.4, 1.1, 0), CFrame.new(0, 1.1, 0))
		local lower = limb(p .. "LowerArm", Vector3.new(0.5, 2.3, 0.5), MARBLE, marble)
		joint(p .. "Elbow", upper, lower, CFrame.new(0, -1.1, 0), CFrame.new(0, 1.1, 0))
		local hand = limb(p .. "Hand", Vector3.new(0.55, 0.75, 0.3), MARBLE, marble)
		joint(p .. "Wrist", lower, hand, CFrame.new(0, -1.15, 0), CFrame.new(0, 0.35, 0))
		local foot = limb(p .. "Foot", Vector3.new(0.6, 0.35, 1.2), MARBLE, marble)
		joint(p .. "FootJoint", pelvis, foot, CFrame.new(side * 0.55, -4.05, -0.7), CFrame.new())
	end
	return head, 4.4
end

---------------------------------------------------------------------------
-- Night 5: THE AMALGAM

local function buildAmalgam(b: Builder): (BasePart, number)
	local SKIN = Color3.fromRGB(12, 9, 16)
	local SKIN_LIGHT = Color3.fromRGB(32, 24, 40)
	local VEIN = Color3.fromRGB(190, 70, 255)
	local BONE = Color3.fromRGB(215, 205, 225)
	local limb, joint = b.limb, b.joint

	local pelvis = limb("Pelvis", Vector3.new(3, 1.6, 2.4), SKIN)
	joint("Waist", b.root, pelvis, CFrame.new(0, 0.3, 0), CFrame.new())
	local torso = limb("Torso", Vector3.new(4.6, 5.4, 3.6), SKIN)
	egg(torso)
	joint("Spine", pelvis, torso, CFrame.new(0, 0.6, 0) * CFrame.Angles(rad(-28), 0, 0), CFrame.new(0, -2.5, 0))
	local core = limb("Core", Vector3.new(1.3, 1.3, 1.3), VEIN, Enum.Material.Neon, Enum.PartType.Ball)
	core.CastShadow = false
	joint("CoreJoint", torso, core, CFrame.new(0, 0.2, -1.65), CFrame.new())
	local coreLight = Instance.new("PointLight")
	coreLight.Name = "EyeGlow"
	coreLight.Color = VEIN
	coreLight.Range = 16
	coreLight.Brightness = 1.6
	coreLight.Parent = core
	for i = 1, 7 do
		local vein = limb("Vein", Vector3.new(0.1, 2.2, 0.1), VEIN, Enum.Material.Neon)
		vein.CastShadow = false
		local angle = i * 0.9
		joint("VeinJoint", torso, vein, CFrame.new(math.cos(angle) * 1.3, math.sin(angle) * 1.6, -1.55 + math.abs(math.sin(angle)) * 0.4) * CFrame.Angles(0, 0, angle), CFrame.new())
	end

	-- three heads
	local function makeHead(name: string, neckName: string, jawName: string, attach: CFrame, size: number, eyes: number): Part
		local h = limb(name, Vector3.new(1.6, 2.2, 1.9) * size, SKIN_LIGHT)
		egg(h)
		joint(neckName, torso, h, attach, CFrame.new(0, -0.9 * size, 0.4 * size))
		local gullet = limb("Gullet", Vector3.new(1.1, 0.7, 0.9) * size, Color3.new(0, 0, 0), Enum.Material.SmoothPlastic)
		joint("GulletJoint", h, gullet, CFrame.new(0, -0.55 * size, -0.45 * size), CFrame.new())
		local jaw = limb("Jaw", Vector3.new(1.3, 0.32, 1.35) * size, SKIN_LIGHT)
		joint(jawName, h, jaw, CFrame.new(0, -0.8 * size, 0.2 * size), CFrame.new(0, 0, 0.6 * size))
		for t = -2, 2 do
			tooth(b, jaw, CFrame.new(t * 0.24 * size, 0.3 * size, (-0.5 + math.abs(t) * 0.1) * size), 0.4 * size, BONE)
			tooth(b, h, CFrame.new(t * 0.24 * size, -0.85 * size, (-0.62 + math.abs(t) * 0.1) * size), 0.45 * size, BONE)
		end
		for e = 1, eyes do
			local ang = e * 2.4
			eye(b, h, (0.18 + (e % 3) * 0.08) * size, Vector3.new(math.cos(ang) * 0.42, 0.3 + math.sin(ang) * 0.35, -0.78) * size, Color3.fromRGB(235, 200, 255), e == 1 and name == "Head")
		end
		return h
	end
	local head = makeHead("Head", "Neck", "Jaw", CFrame.new(0, 2.6, -0.8) * CFrame.Angles(rad(30), 0, 0), 1.2, 5)
	makeHead("HeadL", "NeckL", "JawL2", CFrame.new(-1.9, 2, -0.4) * CFrame.Angles(rad(25), rad(20), rad(30)), 0.85, 2)
	makeHead("HeadR", "NeckR", "JawR2", CFrame.new(1.9, 2, -0.4) * CFrame.Angles(rad(25), rad(-20), rad(-30)), 0.85, 3)

	-- front arms
	for _, side in { -1, 1 } do
		local p = if side < 0 then "L" else "R"
		local upper = limb(p .. "UpperArm", Vector3.new(0.8, 4, 0.8), SKIN)
		joint(p .. "Shoulder", torso, upper, CFrame.new(side * 2.2, 1.4, -0.6) * CFrame.Angles(rad(30), 0, rad(side * 10)), CFrame.new(0, 2, 0))
		local lower = limb(p .. "LowerArm", Vector3.new(0.65, 3.8, 0.65), SKIN)
		joint(p .. "Elbow", upper, lower, CFrame.new(0, -2, 0) * CFrame.Angles(rad(-10), 0, 0), CFrame.new(0, 1.9, 0))
		local hand = limb(p .. "Hand", Vector3.new(0.9, 0.6, 0.5), SKIN_LIGHT)
		joint(p .. "Wrist", lower, hand, CFrame.new(0, -1.9, 0), CFrame.new(0, 0.3, 0))
		for f = 0, 3 do
			local finger = limb(p .. "Finger", Vector3.new(0.16, 1.8, 0.16), SKIN_LIGHT)
			joint(p .. "Finger" .. (f + 1), hand, finger, CFrame.new(-0.33 + f * 0.22, -0.3, 0) * CFrame.Angles(rad(-10), 0, rad(-12 + f * 8)), CFrame.new(0, 0.9, 0))
		end
	end
	-- four spider arms on its back
	for i = 1, 4 do
		local side = if i % 2 == 0 then 1 else -1
		local row = if i <= 2 then 0.6 else -0.6
		local upper = limb("BackUpper" .. i, Vector3.new(0.4, 3.6, 0.4), SKIN)
		joint("BackArm" .. i, torso, upper, CFrame.new(side * 1.2, 1.2 + row, 1.4) * CFrame.Angles(rad(-30 - row * 20), 0, side * rad(-140)), CFrame.new(0, 1.8, 0))
		local lower = limb("BackLower" .. i, Vector3.new(0.3, 3.4, 0.3), SKIN_LIGHT)
		joint("BackElbow" .. i, upper, lower, CFrame.new(0, -1.8, 0) * CFrame.Angles(0, 0, side * rad(100)), CFrame.new(0, 1.7, 0))
		local claw = limb("BackClaw" .. i, Vector3.new(0.2, 1.1, 0.2), BONE, Enum.Material.SmoothPlastic)
		joint("BackClawJoint" .. i, lower, claw, CFrame.new(0, -1.7, 0), CFrame.new(0, 0.5, 0))
	end
	-- four legs
	for pair = 1, 2 do
		for _, side in { -1, 1 } do
			local p = (if side < 0 then "L" else "R")
			local suffix = if pair == 1 then "" else "2"
			local z = if pair == 1 then -0.6 else 0.8
			local thigh = limb(p .. "Thigh" .. suffix, Vector3.new(1.1, 3.3, 1.1), SKIN)
			joint(p .. "Hip" .. suffix, pelvis, thigh, CFrame.new(side * 1.25, -0.5, z) * CFrame.Angles(rad(30), 0, rad(side * 8)), CFrame.new(0, 1.65, 0))
			local shin = limb(p .. "Shin" .. suffix, Vector3.new(0.85, 3.8, 0.85), SKIN)
			joint(p .. "Knee" .. suffix, thigh, shin, CFrame.new(0, -1.65, 0) * CFrame.Angles(rad(-65), 0, 0), CFrame.new(0, 1.9, 0))
			local foot = limb(p .. "Foot" .. suffix, Vector3.new(1, 0.45, 2), SKIN_LIGHT)
			joint(p .. "Ankle" .. suffix, shin, foot, CFrame.new(0, -1.9, 0) * CFrame.Angles(rad(35), 0, 0), CFrame.new(0, 0, 0.7))
		end
	end
	return head, 6.6
end

---------------------------------------------------------------------------

local LOOPS: { [string]: string } = {
	Hollow = "MonsterGrowlLoop",
	Crawler = "CrawlerLoop",
	Listener = "ListenerLoop",
	Amalgam = "AmalgamLoop",
}

local SCREAMS: { [string]: string } = {
	Hollow = "MonsterScream",
	Crawler = "CrawlerScreech",
	Listener = "ListenerShriek",
	Amalgam = "AmalgamRoar",
}
Monsters.SCREAMS = SCREAMS

local ROOT_HEIGHTS: { [string]: number } = {
	Hollow = 5.2,
	Crawler = 2.3,
	Listener = 5,
	Statue = 4.4,
	Amalgam = 6.6,
}

function Monsters.rootHeight(kind: string): number
	return ROOT_HEIGHTS[kind] or 5.2
end

-- Re-place every limb from its joints (for anchored previews and decoys, which
-- have no physics to do it for them).
function Monsters.solve(rig: Rig)
	for _, m in rig.joints do
		local p0, p1 = m.Part0, m.Part1
		if p0 and p1 then
			p1.CFrame = p0.CFrame * m.C0 * m.C1:Inverse()
		end
	end
end

-- Apply a statue pose (by index) on top of the rest pose.
function Monsters.applyStatuePose(rig: Rig, index: number, base: { [Motor6D]: CFrame }?)
	local pose = Monsters.STATUE_POSES[(index - 1) % #Monsters.STATUE_POSES + 1]
	for _, m in rig.joints do
		local rest = if base then base[m] else nil
		rest = rest or m.C0
		local offset = pose[m.Name]
		if offset then
			m.C0 = (rest :: CFrame) * offset
		elseif base then
			m.C0 = rest :: CFrame
		end
	end
end

function Monsters.build(kind: string, options: Options?): Rig
	local opts: Options = options or {}
	local height = Monsters.rootHeight(kind)
	local b, joints = newBuilder(kind, height, opts)
	local head: BasePart
	if kind == "Crawler" then
		head = buildCrawler(b)
	elseif kind == "Listener" then
		head = buildListener(b)
	elseif kind == "Statue" then
		head = buildStatue(b, opts.decoy == true)
	elseif kind == "Amalgam" then
		head = buildAmalgam(b)
	else
		head = buildHollow(b)
	end
	local model = b.model
	local rig: Rig = {
		model = model,
		root = b.root,
		humanoid = nil,
		head = head,
		growl = nil,
		rootHeight = height,
		kind = kind,
		joints = joints,
	}

	if opts.preview then
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
			end
		end
		return rig
	end

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = height - b.root.Size.Y / 2
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
	rig.humanoid = humanoid

	local loop = LOOPS[kind]
	if loop then
		local growl = Audio.create(loop, head, 1.2)
		if growl then
			growl.RollOffMode = Enum.RollOffMode.InverseTapered
			growl.RollOffMinDistance = 8
			growl.RollOffMaxDistance = 90
		end
		rig.growl = growl
	end

	model:SetAttribute("State", "Dormant")
	model:SetAttribute("TargetUserId", 0)
	model:SetAttribute("Pose", 1)
	return rig
end

return Monsters
