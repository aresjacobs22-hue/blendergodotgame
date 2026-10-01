--!strict
-- The five monsters, built from parts. Every limb hangs off a Motor6D so clients can
-- animate them procedurally (MonsterAnimator). Shared so the menu can show previews.
--
--   Hollow   night 1  starved and black, a deer skull for a head, arms dragging
--   Crawler  night 2  a patient bent over backwards on all fours, four extra arms
--   Listener night 3  blind; its whole head splits open down the middle
--   Statue   night 4  marble Mourner or Saint, only moves when unseen
--   Amalgam  night 5  three heads, six arms, four legs, a heart caged in its ribs
--
-- The designs (and a renderer that shows them) live in tools/monster-lab.

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
	variant: string?, -- statue night: "Mourner" or "Saint"
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

-- CFrame.lookAt, spelled out with fromMatrix (Lune's test runtime disagrees with
-- Roblox's lookAt; this gives the same result in both).
local function lookAt(pos: Vector3, target: Vector3): CFrame
	local look = (target - pos).Unit
	local right = look:Cross(Vector3.yAxis)
	if right.Magnitude < 1e-4 then
		right = look:Cross(Vector3.zAxis)
	end
	right = right.Unit
	return CFrame.fromMatrix(pos, right, right:Cross(look), -look)
end

local rgb = Color3.fromRGB
local ang = CFrame.Angles
local cf = CFrame.new

-- An ellipsoid fixed to a parent.
local function blob(b: Builder, name: string, parent: BasePart, at: CFrame, size: Vector3, color: Color3, material: Enum.Material?): Part
	local p = b.limb(name, size, color, material)
	egg(p)
	b.joint(name .. "Joint", parent, p, at, CFrame.new())
	return p
end

-- An organic limb segment hanging below its joint: an ellipsoid a little longer than
-- the joint-to-joint length so neighbouring segments overlap. The next joint sits at
-- (0, -length / 2, 0) in the segment's space.
local function seg(b: Builder, name: string, jointName: string, parent: BasePart, c0: CFrame, length: number, thick: number, color: Color3, material: Enum.Material?, depth: number?): Part
	local p = b.limb(name, Vector3.new(thick, length * 1.22, depth or thick), color, material)
	egg(p)
	b.joint(jointName, parent, p, c0, CFrame.new(0, length / 2, 0))
	return p
end

local function ball(b: Builder, name: string, parent: BasePart, at: Vector3, d: number, color: Color3, material: Enum.Material?): Part
	local p = b.limb(name, Vector3.new(d, d, d), color, material, Enum.PartType.Ball)
	b.joint(name .. "Joint", parent, p, CFrame.new(at), CFrame.new())
	return p
end

-- A pointed tooth/claw/spike: a thin ellipsoid half sunk into its parent. `at` is the
-- root of the tooth; it points along the frame's -Y.
local function fang(b: Builder, parent: BasePart, at: CFrame, length: number, width: number, color: Color3)
	local t = b.limb("Tooth", Vector3.new(width, length * 2, width), color, Enum.Material.SmoothPlastic)
	egg(t)
	b.joint("ToothJoint", parent, t, at, CFrame.new())
end

-- A point on the surface of an ellipsoid part (local space), plus a frame there whose
-- -Z points out of the surface.
local function onSurface(size: Vector3, dir: Vector3): (Vector3, CFrame)
	local a, bb, c = size.X / 2, size.Y / 2, size.Z / 2
	local d = dir.Unit
	local t = 1 / math.sqrt((d.X / a) ^ 2 + (d.Y / bb) ^ 2 + (d.Z / c) ^ 2)
	local p = d * t
	local n = Vector3.new(p.X / (a * a), p.Y / (bb * bb), p.Z / (c * c)).Unit
	return p, lookAt(p, p + n)
end

-- Like seg, but the segment rises above its joint; the next joint is at (0, length / 2, 0).
local function rise(b: Builder, name: string, jointName: string, parent: BasePart, c0: CFrame, length: number, thick: number, color: Color3, material: Enum.Material?, depth: number?): Part
	local p = b.limb(name, Vector3.new(thick, length * 1.22, depth or thick), color, material)
	egg(p)
	b.joint(jointName, parent, p, c0, CFrame.new(0, -length / 2, 0))
	return p
end

local function sideName(side: number): string
	return if side < 0 then "L" else "R"
end

-- Muscle on a limb segment: a fatter ellipsoid over the upper part of it.
local function bulge(b: Builder, seg: BasePart, at: number, length: number, thick: number, color: Color3, material: Enum.Material?)
	blob(b, "Muscle", seg, CFrame.new(0, at, 0), Vector3.new(thick, length, thick * 0.95), color, material)
end

-- A row of fangs around the edge of a mouth on an ellipsoid head. `y` is the gum line
-- (head space), `half` the half-width; teeth point down (up = false) or up.
local function fangRow(b: Builder, parent: BasePart, size: Vector3, y: number, half: number, count: number, length: number, width: number, up: boolean, color: Color3, inset: number?)
	for i = 0, count - 1 do
		local u = if count == 1 then 0 else (i / (count - 1)) * 2 - 1
		local x = u * half
		local p, frame = onSurface(size, Vector3.new(x, y, -size.Z / 2))
		local l = length * (1 - 0.35 * math.abs(u)) * (0.85 + ((i * 37) % 7) / 20)
		local tilt = ang(0, 0, -u * 0.25)
		local at = CFrame.new(p) * (frame - frame.Position) * CFrame.new(0, 0, inset or 0.04) * tilt
		if up then
			at = at * ang(0, 0, math.pi)
		end
		fang(b, parent, at, l, width, color)
	end
end

-- A leg that arches up and out from the body and comes down to the floor, spider style.
-- The lower segment is sized so its tip just touches the ground in the rest pose.
-- Joint names (<p>Hip, <p>Knee) are what MonsterAnimator drives.
local function archLeg(b: Builder, body: BasePart, p: string, at: Vector3, side: number, yaw: number, upperLen: number, thick: number, lift: number, knee: number, color: Color3, material: Enum.Material?, lowerThick: number?, suffix: string?): (Part, Part, number)
	local upper = seg(b, p .. "UpperLeg", p .. "Hip" .. (suffix or ""), body, CFrame.new(at) * CFrame.Angles(0, side * math.rad(yaw), 0) * CFrame.Angles(0, 0, side * math.rad(lift)), upperLen, thick, color, material)
	local c0 = CFrame.new(0, -upperLen / 2, 0) * CFrame.Angles(0, 0, side * math.rad(-knee))
	local kneeFrame = upper.CFrame * c0
	local down = -kneeFrame.UpVector
	local length = if down.Y < -0.05 then kneeFrame.Position.Y / -down.Y * 0.93 else 3
	local lower = seg(b, p .. "LowerLeg", p .. "Knee" .. (suffix or ""), upper, c0, length, lowerThick or thick * 0.7, color, material)
	return upper, lower, length
end

-- A joint frame at `at` (parent space) whose -Y (down = true) or +Y points along the
-- world direction `dir`, keeping its X axis as close to the model's X as possible.
local function aimFrame(parent: BasePart, at: Vector3, dir: Vector3, down: boolean): CFrame
	local up = if down then -dir.Unit else dir.Unit
	local x = Vector3.xAxis - up * up:Dot(Vector3.xAxis)
	if x.Magnitude < 0.05 then
		x = Vector3.zAxis - up * up:Dot(Vector3.zAxis)
	end
	local right = x.Unit
	local back = right:Cross(up)
	local world = CFrame.fromMatrix(parent.CFrame:PointToWorldSpace(at), right, up, back)
	return parent.CFrame:Inverse() * world
end

-- seg / rise, aimed along a world direction (rest pose) instead of relative angles.
local function segTo(b: Builder, name: string, jointName: string, parent: BasePart, at: Vector3, dir: Vector3, length: number, thick: number, color: Color3, material: Enum.Material?, depth: number?): Part
	return seg(b, name, jointName, parent, aimFrame(parent, at, dir, true), length, thick, color, material, depth)
end
local function riseTo(b: Builder, name: string, jointName: string, parent: BasePart, at: Vector3, dir: Vector3, length: number, thick: number, color: Color3, material: Enum.Material?, depth: number?): Part
	return rise(b, name, jointName, parent, aimFrame(parent, at, dir, false), length, thick, color, material, depth)
end
-- Places a part at a point (parent space) facing a world direction (-Z along `look`).
local function faceTo(parent: BasePart, at: Vector3, look: Vector3, tilt: number?): CFrame
	local world = lookAt(parent.CFrame:PointToWorldSpace(at), parent.CFrame:PointToWorldSpace(at) + look) * CFrame.Angles(0, 0, tilt or 0)
	return parent.CFrame:Inverse() * world
end

---------------------------------------------------------------------------
-- Night 1: THE HOLLOW. Starved, black, with a bare deer skull for a head, antlers,
-- pinpoint eyes and a jaw hanging open. Its fingers drag along the floor.

local function buildHollow(b: Builder): BasePart
	local SKIN = rgb(26, 26, 26)
	local SKIN2 = rgb(40, 40, 40)
	local BONE = rgb(214, 208, 196)
	local BLACK = rgb(0, 0, 0)
	local limb, joint = b.limb, b.joint

	local pelvis = limb("Pelvis", Vector3.new(1.7, 1.2, 1.1), SKIN)
	egg(pelvis)
	joint("Waist", b.root, pelvis, cf(0, 0.2, 0), cf())
	local torso = limb("Torso", Vector3.new(2.3, 3.6, 1.3), SKIN)
	egg(torso)
	joint("Spine", pelvis, torso, cf(0, 0.3, 0) * ang(rad(-30), 0, 0), cf(0, -1.6, 0))
	blob(b, "Belly", torso, cf(0, -1.4, 0.08), Vector3.new(1.25, 1.7, 0.8), SKIN)
	for i = 0, 4 do
		blob(b, "Rib", torso, cf(0, 1.0 - i * 0.4, -0.34) * ang(rad(-8 - i * 3), 0, rad((i % 2 - 0.5) * 6)), Vector3.new(2.05 - i * 0.16, 0.17, 0.74), SKIN2)
	end
	for i = 0, 6 do
		ball(b, "Vertebra", torso, Vector3.new(0, 1.55 - i * 0.5, 0.56 - math.abs(i - 3) * 0.04), 0.38 - i * 0.02, SKIN2)
	end
	for _, s in { -1, 1 } do
		blob(b, "Blade", torso, cf(s * 0.55, 0.85, 0.45) * ang(0, 0, rad(s * 15)), Vector3.new(0.85, 1.25, 0.35), SKIN2)
	end

	local neck = rise(b, "NeckBone", "NeckBase", torso, cf(0, 1.5, -0.1) * ang(rad(-10), 0, 0), 1.3, 0.48, SKIN)
	-- a long bare skull, bone white against the black body
	local SKULL = rgb(214, 208, 194)
	local head = limb("Head", Vector3.new(1.15, 1.05, 1.3), SKULL, Enum.Material.SmoothPlastic)
	egg(head)
	joint("Neck", neck, head, cf(0, 0.65, 0) * ang(rad(34), 0, 0), cf(0, -0.35, 0.35))
	local snout = blob(b, "Snout", head, cf(0, -0.18, -0.72) * ang(rad(-6), 0, 0), Vector3.new(0.72, 0.5, 1.55), SKULL, Enum.Material.SmoothPlastic)
	for _, s in { -1, 1 } do
		blob(b, "Socket", head, cf(s * 0.3, 0.04, -0.46) * ang(0, rad(s * 22), rad(-s * 22)), Vector3.new(0.38, 0.3, 0.4), BLACK, Enum.Material.SmoothPlastic)
		eye(b, head, 0.08, Vector3.new(s * 0.33, 0.03, -0.6), rgb(255, 255, 255), s < 0)
		blob(b, "Cheekbone", head, cf(s * 0.42, -0.12, -0.25), Vector3.new(0.25, 0.3, 0.55), SKULL, Enum.Material.SmoothPlastic)
		for i = 0, 5 do
			local z = -0.08 - i * 0.12
			fang(b, snout, cf(s * (0.25 - i * 0.022), -0.16, z) * ang(rad(4), 0, rad(-s * 6)), 0.2 + (if i == 1 then 0.12 else (i % 2) * 0.05), 0.06, BONE)
		end
		-- antler stubs
		local HORN = rgb(120, 116, 108)
		local horn = rise(b, "Horn", "HornJoint", head, cf(s * 0.36, 0.38, 0.2) * ang(rad(40), 0, rad(-s * 50)), 0.9, 0.17, HORN, Enum.Material.SmoothPlastic)
		local horn2 = rise(b, "Horn", "HornJoint", horn, cf(0, 0.42, 0) * ang(rad(-30), 0, rad(s * 45)), 0.9, 0.14, HORN, Enum.Material.SmoothPlastic)
		rise(b, "Horn", "HornJoint", horn2, cf(0, 0.42, 0) * ang(rad(-25), 0, rad(-s * 30)), 0.7, 0.1, HORN, Enum.Material.SmoothPlastic)
		rise(b, "Horn", "HornJoint", horn2, cf(0, 0.1, 0) * ang(rad(35), 0, rad(s * 20)), 0.55, 0.09, HORN, Enum.Material.SmoothPlastic)
		rise(b, "Horn", "HornJoint", horn, cf(0, 0.0, 0) * ang(rad(-45), 0, rad(-s * 10)), 0.5, 0.09, HORN, Enum.Material.SmoothPlastic)
	end
	blob(b, "Nostril", snout, cf(0, 0.1, -0.68), Vector3.new(0.2, 0.16, 0.18), BLACK, Enum.Material.SmoothPlastic)
	blob(b, "Gullet", head, cf(0, -0.45, -0.45), Vector3.new(0.5, 0.5, 1.2), BLACK, Enum.Material.SmoothPlastic)
	local jaw = limb("Jaw", Vector3.new(0.58, 0.24, 1.6), SKULL, Enum.Material.SmoothPlastic)
	egg(jaw)
	joint("Jaw", head, jaw, cf(0, -0.4, 0.15) * ang(rad(-30), 0, 0), cf(0, 0, 0.72))
	for _, s in { -1, 1 } do
		for i = 0, 5 do
			fang(b, jaw, cf(s * (0.2 - i * 0.02), 0.08, 0.05 - i * 0.12) * ang(0, 0, math.pi + rad(s * 6)), 0.16 + (i % 2) * 0.05, 0.055, BONE)
		end
	end

	for _, side in { -1, 1 } do
		local p = sideName(side)
		blob(b, p .. "ShoulderMass", torso, cf(side * 0.85, 1.15, 0.05) * ang(0, 0, rad(side * 35)), Vector3.new(1.1, 0.75, 0.8), SKIN)
		local upper = seg(b, p .. "UpperArm", p .. "Shoulder", torso, cf(side * 1.08, 1.2, 0.05) * ang(rad(44), 0, rad(side * 8)), 3.3, 0.42, SKIN)
		bulge(b, upper, 0.55, 1.9, 0.6, SKIN)
		ball(b, p .. "ElbowKnob", upper, Vector3.new(0, -1.62, 0.06), 0.34, SKIN2)
		local lower = seg(b, p .. "LowerArm", p .. "Elbow", upper, cf(0, -1.65, 0) * ang(rad(-16), 0, 0), 3.5, 0.32, SKIN)
		bulge(b, lower, 0.8, 1.7, 0.48, SKIN)
		local hand = limb(p .. "Hand", Vector3.new(0.62, 0.85, 0.3), SKIN2)
		egg(hand)
		joint(p .. "Wrist", lower, hand, cf(0, -1.75, 0), cf(0, 0.32, 0))
		for f = 0, 3 do
			local finger = seg(b, p .. "Finger", p .. "Finger" .. (f + 1), hand, cf(-0.22 + f * 0.145, -0.3, 0) * ang(rad(-12), 0, rad(-9 + f * 6)), 1.2, 0.12, SKIN2)
			local tip = seg(b, p .. "FingerTip", p .. "FingerTip" .. (f + 1), finger, cf(0, -0.6, 0) * ang(rad(-22), 0, 0), 1.0, 0.1, SKIN2)
			fang(b, tip, cf(0, -0.55, 0), 0.24, 0.075, BONE)
		end
	end
	for _, side in { -1, 1 } do
		local p = sideName(side)
		local thigh = seg(b, p .. "Thigh", p .. "Hip", pelvis, cf(side * 0.55, -0.25, 0) * ang(rad(28), 0, rad(side * 4)), 2.8, 0.6, SKIN)
		bulge(b, thigh, 0.35, 2.2, 0.85, SKIN)
		ball(b, p .. "KneeKnob", thigh, Vector3.new(0, -1.38, -0.06), 0.42, SKIN2)
		local shin = seg(b, p .. "Shin", p .. "Knee", thigh, cf(0, -1.4, 0) * ang(rad(-75), 0, 0), 3.0, 0.4, SKIN)
		bulge(b, shin, 0.7, 1.6, 0.58, SKIN)
		local foot = seg(b, p .. "Foot", p .. "Ankle", shin, cf(0, -1.5, 0) * ang(rad(60), 0, 0), 1.5, 0.36, SKIN2)
		for t = -1, 1 do
			local toe = limb("Toe", Vector3.new(0.17, 0.17, 1.15), SKIN2)
			egg(toe)
			joint("ToeJoint", foot, toe, cf(t * 0.12, -0.75, 0) * ang(rad(-13), rad(-t * 16), 0) * cf(0, 0, -0.45), cf())
			fang(b, toe, cf(0, 0, -0.55) * ang(rad(90), 0, 0), 0.18, 0.08, BONE)
		end
	end
	return head
end

---------------------------------------------------------------------------
-- Night 2: THE CRAWLER. A patient in a torn gown, bent over backwards and running on
-- all fours, with four arms too many. Its head hangs upside down at the front,
-- eyes rolled back, hair dragging on the floor.

local function buildCrawler(b: Builder): BasePart
	local SKIN = rgb(190, 176, 168)
	local SKIN2 = rgb(176, 160, 152)
	local GOWN = rgb(118, 132, 134)
	local HAIR = rgb(14, 10, 10)
	local BLACK = rgb(0, 0, 0)
	local TEETH = rgb(226, 218, 200)
	local smooth = Enum.Material.Plastic
	local fabric = Enum.Material.Fabric
	local limb, joint = b.limb, b.joint

	-- the torso lies belly up, chest towards the front
	local body = limb("Body", Vector3.new(1.9, 1.0, 3.0), SKIN, smooth)
	egg(body)
	joint("Waist", b.root, body, cf(0, 0.4, 0) * ang(rad(-8), 0, 0), cf())
	for i = 0, 3 do
		blob(b, "Rib", body, cf(0, 0.32, -0.95 + i * 0.32), Vector3.new(1.8 - i * 0.1, 0.3, 0.16), SKIN2, smooth)
	end
	blob(b, "Gown", body, cf(0, 0.1, 0.2), Vector3.new(1.85, 0.8, 2.45), GOWN, fabric)
	local abdomen = limb("Abdomen", Vector3.new(1.7, 0.95, 1.6), GOWN, fabric)
	egg(abdomen)
	joint("Tail", body, abdomen, cf(0, -0.05, 1.3), cf(0, 0, -0.3))

	-- head hanging back off the front, upside down, looking at you
	local neck = seg(b, "NeckBone", "NeckBase", body, cf(0, 0.0, -1.45) * ang(rad(-50), 0, 0), 0.8, 0.38, SKIN, smooth)
	local hs = Vector3.new(1.2, 1.45, 1.3)
	local head = limb("Head", hs, SKIN, smooth)
	egg(head)
	joint("Neck", neck, head, cf(0, -0.4, 0) * ang(rad(50), 0, rad(10)), cf(0, 0.55, 0.15))
	for _, s in { -1, 1 } do
		-- eyes rolled all the way back: nothing but white
		blob(b, "Socket", head, cf(s * 0.24, -0.2, -0.55), Vector3.new(0.36, 0.26, 0.2), rgb(70, 40, 42), smooth)
		local e = b.limb("Eye", Vector3.new(0.26, 0.16, 0.12), rgb(255, 250, 244), Enum.Material.Neon)
		egg(e)
		e.CastShadow = false
		joint("EyeJoint", head, e, cf(s * 0.24, -0.21, -0.6) * ang(0, rad(s * 15), 0), cf())
	end
	blob(b, "Nose", head, cf(0, 0.02, -0.66) * ang(rad(180), 0, 0), Vector3.new(0.2, 0.3, 0.2), SKIN2, smooth)
	blob(b, "Gullet", head, cf(0, 0.38, -0.44), Vector3.new(0.75, 0.42, 0.5), BLACK, smooth)
	fangRow(b, head, hs, 0.2, 0.3, 8, 0.14, 0.07, true, TEETH, 0.03)
	local jaw = limb("Jaw", Vector3.new(0.8, 0.36, 0.8), SKIN, smooth)
	egg(jaw)
	joint("Jaw", head, jaw, cf(0, 0.5, 0.0) * ang(rad(28), 0, 0), cf(0, 0, 0.28))
	for i = -3, 3 do
		fang(b, jaw, cf(i * 0.09, -0.1, -0.33 + math.abs(i) * 0.03), 0.12, 0.07, TEETH)
	end
	-- hair hangs from the crown (underneath) to the floor
	for i = 0, 29 do
		local a = i / 30 * math.pi * 2
		local r = 0.38 + (i % 3) * 0.08
		local len = 1.8 + ((i * 7) % 5) * 0.2
		local strand = limb("Hair", Vector3.new(0.11, len, 0.09), HAIR, smooth)
		egg(strand)
		local at = Vector3.new(math.cos(a) * r, -0.45, 0.05 + math.sin(a) * r * 0.9)
		joint("HairJoint", head, strand, (head.CFrame:Inverse() * CFrame.new(head.CFrame:PointToWorldSpace(at))) * ang(0, a, rad(((i * 3) % 5 - 2) * 3)), cf(0, len / 2 - 0.1, 0))
	end

	-- arms in front, legs behind, and four more arms out of its sides
	local legs = {
		{ z = -1.1, yaw = 34, len = 1.7, thick = 0.3, lift = 62, knee = 58, color = SKIN },
		{ z = -0.45, yaw = 8, len = 1.5, thick = 0.22, lift = 112, knee = 118, color = SKIN2 },
		{ z = 0.15, yaw = -14, len = 1.5, thick = 0.22, lift = 112, knee = 118, color = SKIN2 },
		{ z = 1.35, yaw = -30, len = 1.9, thick = 0.38, lift = 58, knee = 52, color = SKIN },
	}
	for i, l in legs do
		for _, side in { -1, 1 } do
			local p = sideName(side) .. i
			local upper, lower, len = archLeg(b, if i == 4 then abdomen :: BasePart else body, p, Vector3.new(side * 0.78, -0.1, if i == 4 then 0.1 else l.z), side, l.yaw, l.len, l.thick, l.lift, l.knee, l.color, smooth, l.thick * 0.8)
			ball(b, "Joint", upper, Vector3.new(0, -l.len / 2, 0), l.thick * 0.9, l.color, smooth)
			bulge(b, upper, l.len * 0.12, l.len * 0.7, l.thick * 1.35, l.color, smooth)
			-- hands for the arms, feet for the legs
			if i < 4 then
				local hand = limb("Hand", Vector3.new(0.35, 0.5, 0.18), SKIN2, smooth)
				egg(hand)
				joint("HandJoint", lower, hand, cf(0, -len / 2, 0), cf(0, 0.15, 0))
				for f = 0, 3 do
					local finger = limb("Finger", Vector3.new(0.06, 0.6, 0.06), SKIN2, smooth)
					egg(finger)
					joint("FingerJoint", hand, finger, cf(-0.12 + f * 0.08, -0.2, 0) * ang(rad(10), 0, rad(-20 + f * 13)), cf(0, 0.25, 0))
				end
			else
				local foot = limb("Foot", Vector3.new(0.38, 0.6, 0.25), SKIN2, smooth)
				egg(foot)
				joint("FootJoint", lower, foot, cf(0, -len / 2, 0), cf(0, 0.15, 0))
			end
		end
	end
	return head
end

---------------------------------------------------------------------------
-- Night 3: THE LISTENER. Starved and blind, its hands held up beside its long head.
-- The whole head is two halves: when it hears you, it splits open down the middle.

local function wet(p: BasePart, amount: number?)
	p.Reflectance = amount or 0.06
end

local function glowSpots(b: Builder, part: BasePart, from: number, to: number, count: number, z: number, color: Color3)
	for i = 0, count - 1 do
		local y = from + (to - from) * i / math.max(1, count - 1)
		local s = b.limb("Glow", Vector3.new(0.18, 0.18, 0.18), color, Enum.Material.Neon, Enum.PartType.Ball)
		s.CastShadow = false
		b.joint("GlowJoint", part, s, CFrame.new((i % 2 - 0.5) * 0.45, y, z), CFrame.new())
	end
end

local function buildListener(b: Builder): BasePart
	local SKIN = rgb(46, 52, 48)
	local SKIN2 = rgb(70, 78, 72)
	local INSIDE = rgb(120, 34, 44)
	local BONE = rgb(222, 224, 206)
	local GLOW = rgb(120, 255, 190)
	local mat = Enum.Material.SmoothPlastic
	local limb, joint = b.limb, b.joint

	local pelvis = limb("Pelvis", Vector3.new(1.4, 1.0, 0.9), SKIN, mat)
	egg(pelvis)
	wet(pelvis)
	joint("Waist", b.root, pelvis, cf(0, 0.2, 0), cf())
	local torso = limb("Torso", Vector3.new(1.6, 3.0, 0.95), SKIN, mat)
	egg(torso)
	wet(torso)
	joint("Spine", pelvis, torso, cf(0, 0.3, 0) * ang(rad(-16), 0, 0), cf(0, -1.4, 0))
	for i = 0, 4 do
		blob(b, "Rib", torso, cf(0, 0.85 - i * 0.36, -0.3), Vector3.new(1.55 - i * 0.12, 0.13, 0.55), SKIN2, mat)
	end
	blob(b, "Belly", torso, cf(0, -1.15, 0.05), Vector3.new(0.9, 1.2, 0.6), SKIN, mat)
	glowSpots(b, torso, 1.1, -0.9, 5, 0.45, GLOW)

	local n1 = riseTo(b, "NeckA", "NeckA", torso, Vector3.new(0, 1.45, -0.05), Vector3.new(0, 1, -0.3), 0.8, 0.36, SKIN, mat)
	local n2 = riseTo(b, "NeckB", "NeckB", n1, Vector3.new(0, 0.4, 0), Vector3.new(0, 1, -0.6), 0.7, 0.34, SKIN, mat)
	local head = limb("Head", Vector3.new(0.4, 0.7, 1.2), INSIDE, mat)
	egg(head)
	joint("Neck", n2, head, faceTo(n2, Vector3.new(0, 0.4, 0), Vector3.new(0, -0.15, -1)), cf(0, -0.15, 0.35))
	local throat = b.limb("Throat", Vector3.new(0.26, 0.26, 0.26), rgb(255, 110, 100), Enum.Material.Neon, Enum.PartType.Ball)
	throat.CastShadow = false
	joint("ThroatJoint", head, throat, cf(0, 0, 0.15), cf())
	-- two halves of a long smooth skull, teeth all along the seam, slightly parted
	for _, side in { -1, 1 } do
		local p = sideName(side)
		local half = limb("Jaw" .. p, Vector3.new(0.6, 1.0, 2.2), SKIN2, mat)
		egg(half)
		wet(half)
		joint("Jaw" .. p, head, half, cf(side * 0.02, 0.05, 0.55) * ang(0, side * rad(-9), 0), cf(-side * 0.26, 0, 0.95))
		blob(b, "Gum", half, cf(-side * 0.22, 0, -0.1), Vector3.new(0.14, 0.78, 1.9), INSIDE, mat)
		-- teeth down the whole seam, so from the front its face is one long toothed slit
		for t = 0, 7 do
			local z = -0.95 + t * 0.2
			fang(b, half, cf(-side * 0.26, 0.28 - math.abs(t - 3.5) * 0.015, z) * ang(0, 0, side * rad(90)), 0.15, 0.045, BONE)
			fang(b, half, cf(-side * 0.26, 0.0, z) * ang(0, 0, side * rad(90)), 0.13, 0.045, BONE)
			fang(b, half, cf(-side * 0.26, -0.28 + math.abs(t - 3.5) * 0.015, z) * ang(0, 0, side * rad(90)), 0.15, 0.045, BONE)
		end
		for v = 0, 2 do
			fang(b, half, cf(-side * 0.2 + side * v * 0.03, 0.4 - v * 0.4, -1.08 + math.abs(v - 1) * 0.05) * ang(0, 0, side * rad(90)), 0.12, 0.045, BONE)
		end
		local fin = limb("Ear" .. p, Vector3.new(0.06, 1.1, 1.0), SKIN2, mat)
		egg(fin)
		fin.Transparency = 0.2
		joint("Ear" .. p, half, fin, cf(side * 0.24, 0.1, 0.5) * ang(rad(-25), 0, side * rad(-35)), cf(0, -0.4, 0))
	end

	-- hands held up by its head, fingers spread, listening
	for _, side in { -1, 1 } do
		local p = sideName(side)
		local upper = segTo(b, p .. "UpperArm", p .. "Shoulder", torso, Vector3.new(side * 0.9, 1.15, 0), Vector3.new(side * 0.6, -0.4, -0.7), 1.8, 0.3, SKIN, mat)
		local lower = segTo(b, p .. "LowerArm", p .. "Elbow", upper, Vector3.new(0, -0.9, 0), Vector3.new(-side * 0.5, 1, -0.2), 2.0, 0.24, SKIN, mat)
		local hand = limb(p .. "Hand", Vector3.new(0.45, 0.6, 0.2), SKIN2, mat)
		egg(hand)
		joint(p .. "Wrist", lower, hand, cf(0, -1.0, 0) * ang(0, rad(side * 80), 0), cf(0, 0.25, 0))
		for f = 0, 2 do
			local finger = seg(b, p .. "Finger", p .. "Finger" .. (f + 1), hand, cf(-0.13 + f * 0.13, -0.25, 0) * ang(rad(-6), 0, rad(-20 + f * 20)), 1.5, 0.08, SKIN2, mat)
			fang(b, finger, cf(0, -0.75, 0), 0.13, 0.06, BONE)
		end
	end
	for _, side in { -1, 1 } do
		local p = sideName(side)
		local thigh = segTo(b, p .. "Thigh", p .. "Hip", pelvis, Vector3.new(side * 0.45, -0.25, 0), Vector3.new(side * 0.12, -1, -0.25), 2.6, 0.44, SKIN, mat)
		bulge(b, thigh, 0.4, 1.7, 0.58, SKIN, mat)
		local shin = segTo(b, p .. "Shin", p .. "Knee", thigh, Vector3.new(0, -1.3, 0), Vector3.new(0, -1, 0.22), 2.7, 0.32, SKIN, mat)
		local foot = limb(p .. "Foot", Vector3.new(0.5, 0.28, 1.45), SKIN2, mat)
		egg(foot)
		joint(p .. "Ankle", shin, foot, faceTo(shin, Vector3.new(0, -1.35, 0), Vector3.new(0, 0, -1)), cf(0, 0.1, 0.45))
	end
	return head
end

---------------------------------------------------------------------------
-- Night 4: THE STATUE. Two kinds, picked at random each round (the decoys mix both):
--   Mourner  a hooded figure in long robes, its face lost in the hood
--   Saint    a crown of spikes and three faces, front and both sides
-- Arms, elbows, neck and spine use plain joint frames so the poses below mean the
-- same thing on both. The real one has red points of light for eyes.

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

local MARBLE = rgb(226, 225, 219)
local MARBLE2 = rgb(206, 205, 198)
local CRACK = rgb(70, 70, 68)
local RED = rgb(255, 50, 40)

local function crack(b: Builder, parent: BasePart, at: CFrame, length: number, color: Color3?)
	local c = b.limb("Crack", Vector3.new(0.04, length, 0.04), color or CRACK, Enum.Material.SmoothPlastic)
	b.joint("CrackJoint", parent, c, at, CFrame.new())
end

-- arms that hang straight down from plain joints; returns the hands
local function statueArms(b: Builder, torso: BasePart, shoulderX: number, shoulderY: number, upperLen: number, lowerLen: number, thick: number, color: Color3, material: Enum.Material, sleeve: Color3?)
	for _, side in { -1, 1 } do
		local p = sideName(side)
		local upper = seg(b, p .. "UpperArm", p .. "Shoulder", torso, cf(side * shoulderX, shoulderY, 0), upperLen, thick, sleeve or color, material)
		if sleeve then
			blob(b, "Sleeve", upper, cf(0, -upperLen * 0.1, 0), Vector3.new(thick * 1.35, upperLen * 1.05, thick * 1.35), sleeve, material)
		end
		local lower = seg(b, p .. "LowerArm", p .. "Elbow", upper, cf(0, -upperLen / 2, 0), lowerLen, thick * 0.82, sleeve or color, material)
		if sleeve then
			blob(b, "Cuff", lower, cf(0, -lowerLen * 0.12, 0), Vector3.new(thick * 1.6, lowerLen * 0.85, thick * 1.6), sleeve, material)
		end
		local hand = b.limb(p .. "Hand", Vector3.new(0.42, 0.62, 0.2), color, material)
		egg(hand)
		b.joint(p .. "Wrist", lower, hand, cf(0, -lowerLen / 2, 0), cf(0, 0.25, 0))
		for f = 0, 3 do
			local finger = b.limb("Finger", Vector3.new(0.08, 0.6, 0.08), color, material)
			egg(finger)
			b.joint("FingerJoint", hand, finger, cf(-0.13 + f * 0.085, -0.3, 0) * ang(rad(-8), 0, rad(-6 + f * 4)), cf(0, 0.22, 0))
		end
	end
end

local function buildMourner(b: Builder, decoy: boolean): BasePart
	local marble = Enum.Material.Marble
	local limb, joint = b.limb, b.joint
	local pelvis = limb("Pelvis", Vector3.new(1.8, 1.0, 1.2), MARBLE2, marble)
	egg(pelvis)
	joint("Waist", b.root, pelvis, cf(0, 0.2, 0), cf())
	-- the robe: long folds from the waist to the floor
	for i = 0, 15 do
		local a = i / 16 * math.pi * 2
		local len = 4.75
		local fold = limb("Robe", Vector3.new(0.6, len, 0.32), MARBLE2, marble)
		egg(fold)
		joint("RobeJoint", pelvis, fold, cf(0, 0.0, 0) * ang(0, a, 0) * cf(0, 0, -0.62) * ang(rad(8), 0, 0), cf(0, len / 2 - 0.15, 0))
	end
	blob(b, "Skirt", pelvis, cf(0, -2.0, 0), Vector3.new(2.0, 4.2, 1.7), MARBLE2, marble)
	local torso = limb("Torso", Vector3.new(2.1, 2.7, 1.25), MARBLE2, marble)
	egg(torso)
	joint("Spine", pelvis, torso, cf(0, 0.5, 0), cf(0, -1.3, 0))
	blob(b, "Shoulders", torso, cf(0, 0.9, 0), Vector3.new(2.5, 1.0, 1.35), MARBLE2, marble)
	-- a cape over the shoulders that the hood grows out of
	blob(b, "Cape", torso, cf(0, 0.55, 0.25), Vector3.new(2.7, 2.6, 1.6), MARBLE2, marble)
	for i = 0, 5 do
		local x = (i - 2.5) * 0.42
		blob(b, "CapeFold", torso, cf(x, -0.2, 0.75 + math.abs(x) * -0.12) * ang(rad(4), 0, rad(-x * 4)), Vector3.new(0.4, 2.6, 0.35), MARBLE2, marble)
	end
	-- the hood
	local head = limb("Head", Vector3.new(1.1, 1.35, 1.2), MARBLE, marble)
	egg(head)
	joint("Neck", torso, head, cf(0, 1.45, 0), cf(0, -0.75, 0))
	local hood = blob(b, "Hood", head, cf(0, 0.12, 0.32), Vector3.new(1.7, 2.1, 1.75), MARBLE2, marble)
	blob(b, "HoodPeak", hood, cf(0, 0.62, -0.42) * ang(rad(-30), 0, 0), Vector3.new(1.0, 0.5, 1.0), MARBLE2, marble)
	blob(b, "HoodDrape", hood, cf(0, -0.85, 0.15), Vector3.new(1.9, 1.3, 1.6), MARBLE2, marble)
	for _, s in { -1, 1 } do
		blob(b, "HoodEdge", hood, cf(s * 0.6, -0.2, -0.42) * ang(0, rad(s * 25), rad(s * 3)), Vector3.new(0.2, 1.7, 0.75), MARBLE2, marble)
		blob(b, "Socket", head, cf(s * 0.22, 0.12, -0.5) * ang(0, 0, rad(s * -10)), Vector3.new(0.3, 0.18, 0.2), rgb(26, 26, 28), Enum.Material.SmoothPlastic)
		blob(b, "Tear", head, cf(s * 0.23, -0.15, -0.53), Vector3.new(0.05, 0.38, 0.06), rgb(70, 70, 68), Enum.Material.SmoothPlastic)
		if not decoy then
			eye(b, head, 0.08, Vector3.new(s * 0.22, 0.11, -0.58), RED, s < 0)
		end
	end
	blob(b, "Nose", head, cf(0, -0.08, -0.58), Vector3.new(0.14, 0.38, 0.18), MARBLE, marble)
	blob(b, "Mouth", head, cf(0, -0.38, -0.52), Vector3.new(0.28, 0.07, 0.08), rgb(60, 60, 58), Enum.Material.SmoothPlastic)
	crack(b, hood, cf(0.3, 0.4, -0.7) * ang(0, 0, rad(25)), 0.7)
	crack(b, torso, cf(-0.4, 0.2, -0.62) * ang(0, 0, rad(-20)), 0.9)
	crack(b, torso, cf(-0.2, -0.3, -0.62) * ang(0, 0, rad(30)), 0.6)
	statueArms(b, torso, 1.15, 0.85, 2.3, 2.2, 0.48, MARBLE, marble, MARBLE2)
	for _, side in { -1, 1 } do
		local foot = limb(sideName(side) .. "Foot", Vector3.new(0.55, 0.35, 1.0), MARBLE, marble)
		egg(foot)
		joint(sideName(side) .. "FootJoint", pelvis, foot, cf(side * 0.4, -4.4, -0.8), cf())
	end
	return head
end

local function buildSaint(b: Builder, decoy: boolean): BasePart
	local marble = Enum.Material.Marble
	local limb, joint = b.limb, b.joint
	local pelvis = limb("Pelvis", Vector3.new(1.8, 1.0, 1.2), MARBLE2, marble)
	egg(pelvis)
	joint("Waist", b.root, pelvis, cf(0, 0.2, 0), cf())
	for i = 0, 11 do
		local a = i / 12 * math.pi * 2
		local len = 4.7
		local fold = limb("Robe", Vector3.new(0.75, len, 0.3), MARBLE2, marble)
		egg(fold)
		joint("RobeJoint", pelvis, fold, ang(0, a, 0) * cf(0, 0, -0.65) * ang(rad(4), 0, 0), cf(0, len / 2 - 0.15, 0))
	end
	blob(b, "Skirt", pelvis, cf(0, -2.0, 0), Vector3.new(1.85, 4.3, 1.6), MARBLE2, marble)
	local torso = limb("Torso", Vector3.new(1.9, 2.7, 1.15), MARBLE2, marble)
	egg(torso)
	joint("Spine", pelvis, torso, cf(0, 0.5, 0), cf(0, -1.3, 0))
	local sash = limb("Sash", Vector3.new(0.35, 3.0, 0.2), MARBLE, marble)
	joint("SashJoint", torso, sash, cf(0, 0.0, -0.55) * ang(0, 0, rad(32)), cf())
	local hs = Vector3.new(1.25, 1.4, 1.25)
	local head = limb("Head", hs, MARBLE, marble)
	egg(head)
	joint("Neck", torso, head, cf(0, 1.45, 0), cf(0, -0.8, 0))
	-- three faces
	for f, yaw in { 0, 90, -90 } do
		local face = blob(b, "Face", head, ang(0, rad(yaw), 0) * cf(0, -0.05, -0.47), Vector3.new(0.75, 1.0, 0.4), MARBLE, marble)
		for _, s in { -1, 1 } do
			blob(b, "Socket", face, cf(s * 0.17, 0.14, -0.15) * ang(0, 0, rad(s * -18)), Vector3.new(0.25, 0.18, 0.12), rgb(20, 20, 20), Enum.Material.SmoothPlastic)
			if not decoy then
				eye(b, face, 0.06, Vector3.new(s * 0.17, 0.15, -0.2), RED, f == 1 and s < 0)
			end
		end
		blob(b, "Mouth", face, cf(0, -0.24, -0.14), Vector3.new(0.2, 0.42, 0.12), rgb(20, 20, 20), Enum.Material.SmoothPlastic)
		blob(b, "Brow", face, cf(0, 0.3, -0.1), Vector3.new(0.6, 0.14, 0.2), MARBLE2, marble)
	end
	-- the crown: spikes radiating out of the back of its head
	for i = 0, 10 do
		local a = (i / 10 - 0.5) * math.pi * 1.3
		local len = 1.0 + (i % 2) * 0.5
		local spike = limb("Spike", Vector3.new(0.12, len * 2, 0.12), MARBLE2, marble)
		egg(spike)
		joint("SpikeJoint", head, spike, cf(0, 0.25, 0.25) * ang(0, 0, a) * cf(0, 0.55, 0), cf())
	end
	local ring = limb("Halo", Vector3.new(0.12, 2.6, 2.6), MARBLE2, marble, Enum.PartType.Cylinder)
	joint("HaloJoint", head, ring, cf(0, 0.35, 0.45) * ang(0, rad(90), 0), cf())
	crack(b, head, cf(0.25, 0.45, -0.55) * ang(0, 0, rad(30)), 0.5)
	crack(b, torso, cf(0.4, 0.3, -0.58) * ang(0, 0, rad(-25)), 0.9)
	statueArms(b, torso, 1.1, 0.9, 2.3, 2.2, 0.42, MARBLE, marble, nil)
	for _, side in { -1, 1 } do
		local foot = limb(sideName(side) .. "Foot", Vector3.new(0.55, 0.35, 1.0), MARBLE, marble)
		egg(foot)
		joint(sideName(side) .. "FootJoint", pelvis, foot, cf(side * 0.4, -4.4, -0.8), cf())
	end
	return head
end

---------------------------------------------------------------------------
-- Night 5: THE AMALGAM. A hunched heap of fused bodies, three heads, a glowing heart
-- caged behind its ribs, two huge knuckle-dragging arms, four more on its back.

local A_SKIN = rgb(28, 20, 36)
local A_SKIN2 = rgb(54, 40, 66)
local A_VEIN = rgb(190, 70, 255)
local A_BONE = rgb(215, 205, 225)
local A_EYE = rgb(240, 205, 255)
local A_BLACK = rgb(0, 0, 0)

-- glowing veins crawling over an ellipsoid part
local function veins(b: Builder, part: BasePart, count: number, seed: number)
	for i = 1, count do
		local a = i * 2.39996 + seed
		local y = math.sin(i * 1.7 + seed) * 0.8
		local dir = Vector3.new(math.cos(a), y, math.sin(a))
		local p, frame = onSurface(part.Size, dir)
		local v = b.limb("Vein", Vector3.new(0.12, 1.2 + (i % 3) * 0.5, 0.08), A_VEIN, Enum.Material.Neon)
		egg(v)
		v.CastShadow = false
		b.joint("VeinJoint", part, v, CFrame.new(p) * (frame - frame.Position) * ang(0, 0, a * 3) * cf(0, 0, 0.02), cf())
	end
end

-- a head with a hinged jaw, teeth and a cluster of eyes; returns head, jaw
local function amalgamHead(b: Builder, parent: BasePart, name: string, neckName: string, jawName: string, c0: CFrame, size: number, eyes: number, glow: boolean): (Part, Part)
	local hs = Vector3.new(1.6, 1.8, 1.9) * size
	local h = b.limb(name, hs, A_SKIN2)
	egg(h)
	b.joint(neckName, parent, h, c0, cf(0, -0.5 * size, 0.5 * size))
	blob(b, "Gullet", h, cf(0, -0.5 * size, -0.45 * size), Vector3.new(1.1, 0.8, 0.9) * size, A_BLACK, Enum.Material.SmoothPlastic)
	fangRow(b, h, hs, -0.32 * size, 0.55 * size, 9, 0.32 * size, 0.08 * size, false, A_BONE, 0.05 * size)
	local js = Vector3.new(1.3, 0.4, 1.5) * size
	local jaw = b.limb("Jaw", js, A_SKIN2)
	egg(jaw)
	b.joint(jawName, h, jaw, cf(0, -0.75 * size, 0.25 * size) * ang(rad(-22), 0, 0), cf(0, 0, 0.62 * size))
	for t = -3, 3 do
		fang(b, jaw, cf(t * 0.15 * size, 0.14 * size, (-0.55 + math.abs(t) * 0.08) * size) * ang(0, 0, math.pi), (0.26 - math.abs(t) * 0.02) * size, 0.07 * size, A_BONE)
	end
	for e = 1, eyes do
		local a = e * 2.4
		local r = if e == 1 then 0 else 0.3 + (e % 2) * 0.12
		local p = onSurface(hs, Vector3.new(math.cos(a) * r, 0.25 + math.sin(a) * r * 0.7, -0.75))
		local d = (if e == 1 then 0.34 else 0.16 + (e % 3) * 0.05) * size
		blob(b, "Socket", h, CFrame.new(p), Vector3.new(d * 1.4, d * 1.4, d), A_BLACK, Enum.Material.SmoothPlastic)
		eye(b, h, d, p + (p - Vector3.zero).Unit * 0.02, A_EYE, glow and e == 1)
	end
	return h, jaw
end

local function hand(b: Builder, lower: BasePart, p: string, length: number, size: number, fingerLen: number)
	local hd = b.limb(p .. "Hand", Vector3.new(0.9, 0.6, 0.5) * size, A_SKIN2)
	egg(hd)
	b.joint(p .. "Wrist", lower, hd, cf(0, -length / 2, 0), cf(0, 0.25 * size, 0))
	for f = 0, 3 do
		local finger = seg(b, p .. "Finger", p .. "Finger" .. (f + 1), hd, cf((-0.33 + f * 0.22) * size, -0.25 * size, 0) * ang(rad(-10), 0, rad(-12 + f * 8)), fingerLen, 0.17 * size, A_SKIN2)
		fang(b, finger, cf(0, -fingerLen / 2 - 0.05, 0), 0.25 * size, 0.1 * size, A_BONE)
	end
end

-- four digitigrade legs: LHip/RHip in front, LHip2/RHip2 behind
local function amalgamLegs(b: Builder, pelvis: BasePart, width: number, z0: number, z1: number, scale: number)
	for pair = 1, 2 do
		for _, side in { -1, 1 } do
			local p = sideName(side)
			local suffix = if pair == 1 then "" else "2"
			local z = if pair == 1 then z0 else z1
			local thigh = seg(b, p .. "Thigh" .. suffix, p .. "Hip" .. suffix, pelvis, cf(side * width, -0.5, z) * ang(rad(30), 0, rad(side * 8)), 3.3 * scale, 1.0 * scale, A_SKIN)
			bulge(b, thigh, 0.4, 2.4 * scale, 1.35 * scale, A_SKIN)
			local shin = seg(b, p .. "Shin" .. suffix, p .. "Knee" .. suffix, thigh, cf(0, -1.65 * scale, 0) * ang(rad(-68), 0, 0), 3.6 * scale, 0.7 * scale, A_SKIN)
			local foot = seg(b, p .. "Foot" .. suffix, p .. "Ankle" .. suffix, shin, cf(0, -1.8 * scale, 0) * ang(rad(58), 0, 0), 1.5 * scale, 0.5 * scale, A_SKIN2)
			for t = -1, 1 do
				local toe = b.limb("Toe", Vector3.new(0.25, 0.25, 1.3) * scale, A_SKIN2)
				egg(toe)
				b.joint("ToeJoint", foot, toe, cf(t * 0.18 * scale, -0.72 * scale, 0) * ang(rad(-20), rad(-t * 18), 0) * cf(0, 0, -0.5 * scale), cf())
				fang(b, toe, cf(0, 0, -0.62 * scale) * ang(rad(90), 0, 0), 0.25 * scale, 0.1 * scale, A_BONE)
			end
		end
	end
end

-- long thin arms out of its back that never stop moving (BackArm1..4)
local function backArms(b: Builder, torso: BasePart, spots: { Vector3 }, len: number)
	for i, at in spots do
		local side = if at.X < 0 then -1 else 1
		local upper = riseTo(b, "BackUpper" .. i, "BackArm" .. i, torso, at, Vector3.new(side * 0.8, 1, 0.5), len, 0.38, A_SKIN)
		local lower = segTo(b, "BackLower" .. i, "BackElbow" .. i, upper, Vector3.new(0, len / 2, 0), Vector3.new(side * 0.6, -1, -0.3), len * 0.95, 0.28, A_SKIN2)
		local claw = b.limb("BackClaw" .. i, Vector3.new(0.18, 1.4, 0.18), A_BONE, Enum.Material.SmoothPlastic)
		egg(claw)
		b.joint("BackClawJoint" .. i, lower, claw, cf(0, -len * 0.475, 0), cf(0, 0.55, 0))
	end
end

local function buildAmalgam(b: Builder): BasePart
	local limb, joint = b.limb, b.joint
	local pelvis = limb("Pelvis", Vector3.new(3.2, 1.8, 2.6), A_SKIN)
	egg(pelvis)
	joint("Waist", b.root, pelvis, cf(0, 0.3, 0), cf())
	local torso = limb("Torso", Vector3.new(4.8, 5.4, 3.8), A_SKIN)
	egg(torso)
	joint("Spine", pelvis, torso, cf(0, 0.6, 0) * ang(rad(-32), 0, 0), cf(0, -2.4, 0))
	blob(b, "Hump", torso, cf(0, 1.2, 0.9), Vector3.new(4.2, 3.4, 2.6), A_SKIN)
	-- the caged heart
	blob(b, "Cavity", torso, cf(0, 0.2, -1.55), Vector3.new(2.3, 2.8, 1.0), A_BLACK, Enum.Material.SmoothPlastic)
	local core = limb("Core", Vector3.new(1.4, 1.4, 1.4), A_VEIN, Enum.Material.Neon, Enum.PartType.Ball)
	core.CastShadow = false
	joint("CoreJoint", torso, core, cf(0, 0.2, -1.45), cf())
	local coreLight = Instance.new("PointLight")
	coreLight.Name = "EyeGlow"
	coreLight.Color = A_VEIN
	coreLight.Range = 16
	coreLight.Brightness = 1.6
	coreLight.Parent = core
	for i = 0, 5 do
		local y = 1.3 - i * 0.45
		blob(b, "Rib", torso, cf(0, y, -1.85 + math.abs(y - 0.2) * 0.12) * ang(rad(-6), 0, 0), Vector3.new(2.7 - math.abs(i - 2.5) * 0.25, 0.2, 0.45), A_BONE, Enum.Material.SmoothPlastic)
	end
	blob(b, "Sternum", torso, cf(0, 0.25, -1.95), Vector3.new(0.3, 2.6, 0.3), A_BONE, Enum.Material.SmoothPlastic)
	veins(b, torso, 14, 0.3)
	veins(b, pelvis, 5, 1.1)
	for i = 0, 5 do
		fang(b, torso, cf((i % 2 - 0.5) * 0.9, 2.2 - i * 0.55, 1.6 + i * 0.05) * ang(rad(-120), 0, 0), 0.5 - i * 0.04, 0.22, A_BONE)
	end

	local head = amalgamHead(b, torso, "Head", "Neck", "Jaw", cf(0, 2.5, -1.3) * ang(rad(38), 0, 0), 1.25, 5, true)
	amalgamHead(b, torso, "HeadL", "NeckL", "JawL2", cf(-2.1, 1.7, -0.7) * ang(rad(30), rad(25), rad(28)), 0.85, 2, false)
	amalgamHead(b, torso, "HeadR", "NeckR", "JawR2", cf(2.1, 1.7, -0.7) * ang(rad(30), rad(-25), rad(-28)), 0.85, 3, false)

	for _, side in { -1, 1 } do
		local p = sideName(side)
		blob(b, p .. "ShoulderMass", torso, cf(side * 2.1, 1.1, -0.4), Vector3.new(1.8, 1.6, 1.8), A_SKIN)
		local upper = seg(b, p .. "UpperArm", p .. "Shoulder", torso, cf(side * 2.3, 1.1, -0.5) * ang(rad(40), 0, rad(side * 12)), 4.0, 0.9, A_SKIN)
		bulge(b, upper, 0.6, 2.4, 1.25, A_SKIN)
		local lower = seg(b, p .. "LowerArm", p .. "Elbow", upper, cf(0, -2, 0) * ang(rad(-14), 0, 0), 4.0, 0.72, A_SKIN)
		bulge(b, lower, 0.8, 2.0, 1.0, A_SKIN)
		veins(b, upper, 2, side)
		hand(b, lower, p, 4.0, 1.2, 1.6)
	end
	backArms(b, torso, { Vector3.new(-1.2, 1.8, 1.4), Vector3.new(1.2, 1.8, 1.4), Vector3.new(-1.4, 0.6, 1.6), Vector3.new(1.4, 0.6, 1.6) }, 3.4)
	amalgamLegs(b, pelvis, 1.3, -0.6, 0.8, 1)
	return head
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
	Hollow = 6.1,
	Crawler = 3.0,
	Listener = 5.2,
	Statue = 4.6,
	Amalgam = 7.5,
}

Monsters.STATUE_VARIANTS = { "Mourner", "Saint" }

function Monsters.rootHeight(kind: string): number
	return ROOT_HEIGHTS[kind] or 6
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
	local model = b.model
	local head: BasePart
	if kind == "Crawler" then
		head = buildCrawler(b)
	elseif kind == "Listener" then
		head = buildListener(b)
	elseif kind == "Statue" then
		local variant = opts.variant or "Mourner"
		head = if variant == "Saint" then buildSaint(b, opts.decoy == true) else buildMourner(b, opts.decoy == true)
		model:SetAttribute("Variant", variant)
	elseif kind == "Amalgam" then
		head = buildAmalgam(b)
	else
		head = buildHollow(b)
	end
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
