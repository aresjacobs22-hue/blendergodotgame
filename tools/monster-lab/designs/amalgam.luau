
---------------------------------------------------------------------------
-- Shared bits for the Amalgam: glowing veins, many-eyed heads, many arms.

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

---------------------------------------------------------------------------
-- AMALGAM A: the Mass. A hunched heap of fused bodies, three heads, a glowing heart
-- caged behind its ribs, two huge knuckle-dragging arms and four more on its back.

Designs.AmalgamA = { height = 7.5, build = function(b: Builder): BasePart
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
end }

---------------------------------------------------------------------------
-- AMALGAM B: the Tower. Bodies stacked on bodies, arms reaching out of it at every
-- height, faces pushing out of its sides, one huge head at the top.

Designs.AmalgamB = { height = 7.1, build = function(b: Builder): BasePart
	local limb, joint = b.limb, b.joint
	local pelvis = limb("Pelvis", Vector3.new(3.0, 1.8, 2.6), A_SKIN)
	egg(pelvis)
	joint("Waist", b.root, pelvis, cf(0, 0.3, 0), cf())
	local torso = limb("Torso", Vector3.new(3.6, 3.6, 2.9), A_SKIN)
	egg(torso)
	joint("Spine", pelvis, torso, cf(0, 0.6, 0) * ang(rad(-6), 0, 0), cf(0, -1.6, 0))
	local mid = limb("TorsoMid", Vector3.new(3.1, 3.4, 2.5), A_SKIN)
	egg(mid)
	joint("Spine2", torso, mid, cf(0, 1.6, 0) * ang(rad(-8), rad(10), rad(4)), cf(0, -1.5, 0))
	local top = limb("TorsoTop", Vector3.new(2.6, 3.0, 2.1), A_SKIN)
	egg(top)
	joint("Spine3", mid, top, cf(0, 1.5, 0) * ang(rad(-10), rad(-14), rad(-5)), cf(0, -1.3, 0))
	veins(b, torso, 9, 0.2)
	veins(b, mid, 8, 1.4)
	veins(b, top, 6, 2.2)
	-- the heart shows through a split down its middle
	blob(b, "Split", mid, cf(0, 0, -1.1), Vector3.new(0.7, 2.6, 0.6), A_BLACK, Enum.Material.SmoothPlastic)
	local core = limb("Core", Vector3.new(0.9, 0.9, 0.9), A_VEIN, Enum.Material.Neon, Enum.PartType.Ball)
	core.CastShadow = false
	joint("CoreJoint", mid, core, cf(0, 0, -1.0), cf())
	local coreLight = Instance.new("PointLight")
	coreLight.Name = "EyeGlow"
	coreLight.Color = A_VEIN
	coreLight.Range = 16
	coreLight.Brightness = 1.6
	coreLight.Parent = core
	for _, side in { -1, 1 } do
		blob(b, "Lip", mid, cf(side * 0.32, 0, -1.12) * ang(0, 0, rad(side * 3)), Vector3.new(0.3, 2.7, 0.5), A_SKIN2)
		for t = 0, 4 do
			fang(b, mid, cf(side * 0.22, 0.9 - t * 0.45, -1.2) * ang(0, 0, side * rad(90)), 0.18, 0.07, A_BONE)
		end
	end

	local head = amalgamHead(b, top, "Head", "Neck", "Jaw", cf(0, 1.4, -0.5) * ang(rad(12), 0, 0), 1.45, 5, true)
	-- faces pushing out of its sides
	amalgamHead(b, torso, "HeadL", "NeckL", "JawL2", cf(-1.5, 0.3, -0.9) * ang(rad(5), rad(35), rad(15)), 0.75, 2, false)
	amalgamHead(b, torso, "HeadR", "NeckR", "JawR2", cf(1.5, 0.3, -0.9) * ang(rad(5), rad(-35), rad(-15)), 0.75, 3, false)

	-- the front arms come out of the top body
	for _, side in { -1, 1 } do
		local p = sideName(side)
		local upper = segTo(b, p .. "UpperArm", p .. "Shoulder", top, Vector3.new(side * 1.2, 0.8, -0.2), Vector3.new(side * 0.8, 0.6, -0.5), 3.2, 0.7, A_SKIN)
		bulge(b, upper, 0.5, 1.9, 0.95, A_SKIN)
		local lower = segTo(b, p .. "LowerArm", p .. "Elbow", upper, Vector3.new(0, -1.6, 0), Vector3.new(side * 0.2, 0.3, -1), 3.2, 0.55, A_SKIN)
		hand(b, lower, p, 3.2, 1.0, 1.4)
	end
	-- and more arms out of every body, reaching for you
	local spots: { { part: BasePart, at: Vector3, side: number } } = {
		{ part = mid, at = Vector3.new(-1.4, 0.5, 0.2), side = -1 },
		{ part = mid, at = Vector3.new(1.4, 0.5, 0.2), side = 1 },
		{ part = torso, at = Vector3.new(-1.6, 1.0, 0.4), side = -1 },
		{ part = torso, at = Vector3.new(1.6, 1.0, 0.4), side = 1 },
	}
	for i, s in spots do
		local part, at, side = s.part, s.at, s.side
		local dirs = { Vector3.new(side * 1, 0.9, -0.2), Vector3.new(side * 1, 0.9, -0.2), Vector3.new(side * 1, -0.5, -0.6), Vector3.new(side * 1, -0.5, -0.6) }
		local dirs2 = { Vector3.new(side * 0.3, 1, -0.6), Vector3.new(side * 0.3, 1, -0.6), Vector3.new(side * 0.2, -0.9, -0.8), Vector3.new(side * 0.2, -0.9, -0.8) }
		local upper = segTo(b, "BackUpper" .. i, "BackArm" .. i, part, at, dirs[i], 2.6, 0.45, A_SKIN)
		local lower = segTo(b, "BackLower" .. i, "BackElbow" .. i, upper, Vector3.new(0, -1.3, 0), dirs2[i], 2.5, 0.36, A_SKIN2)
		hand(b, lower, "Back" .. i, 2.5, 0.7, 1.1)
	end
	amalgamLegs(b, pelvis, 1.2, -0.5, 0.8, 0.95)
	return head
end }

---------------------------------------------------------------------------
-- AMALGAM C: the Maw. The whole front of it is one enormous mouth with its heart
-- glowing at the back of the throat. Two heads on long necks watch over it.

Designs.AmalgamC = { height = 7.2, build = function(b: Builder): BasePart
	local limb, joint = b.limb, b.joint
	local pelvis = limb("Pelvis", Vector3.new(3.2, 1.8, 2.8), A_SKIN)
	egg(pelvis)
	joint("Waist", b.root, pelvis, cf(0, 0.3, 0), cf())
	local torso = limb("Torso", Vector3.new(4.4, 4.2, 4.4), A_SKIN)
	egg(torso)
	joint("Spine", pelvis, torso, cf(0, 0.6, 0) * ang(rad(-12), 0, 0), cf(0, -1.6, 0.6))
	veins(b, torso, 12, 0.7)
	-- the maw: the upper jaw is its "head"
	local hs = Vector3.new(4.0, 2.4, 4.4)
	local head = limb("Head", hs, A_SKIN2)
	egg(head)
	joint("Neck", torso, head, cf(0, 0.9, -1.2) * ang(rad(14), 0, 0), cf(0, 0, 1.2))
	veins(b, head, 8, 2.0)
	local throat = limb("Throat", Vector3.new(3.0, 2.4, 3.0), A_BLACK, Enum.Material.SmoothPlastic)
	egg(throat)
	joint("ThroatJoint", head, throat, cf(0, -1.0, 0.1), cf())
	local core = limb("Core", Vector3.new(1.3, 1.3, 1.3), A_VEIN, Enum.Material.Neon, Enum.PartType.Ball)
	core.CastShadow = false
	joint("CoreJoint", head, core, cf(0, -1.0, 0.9), cf())
	local coreLight = Instance.new("PointLight")
	coreLight.Name = "EyeGlow"
	coreLight.Color = A_VEIN
	coreLight.Range = 18
	coreLight.Brightness = 1.8
	coreLight.Parent = core
	fangRow(b, head, hs, -0.55, 1.75, 15, 0.7, 0.16, false, A_BONE, 0.12)
	local js = Vector3.new(3.6, 1.2, 4.0)
	local jaw = limb("Jaw", js, A_SKIN2)
	egg(jaw)
	joint("Jaw", head, jaw, cf(0, -1.0, 1.0) * ang(rad(-30), 0, 0), cf(0, 0.1, 1.6))
	fangRow(b, jaw, js, 0.25, 1.55, 13, 0.6, 0.15, true, A_BONE, 0.12)
	local tongue = limb("Tongue", Vector3.new(1.2, 0.4, 3.0), rgb(90, 30, 110))
	egg(tongue)
	joint("TongueJoint", jaw, tongue, cf(0, 0.35, -0.6) * ang(rad(8), 0, 0), cf())
	-- little eyes all along the top of the maw
	for i = 0, 6 do
		local u = i / 6 * 2 - 1
		local p = onSurface(hs, Vector3.new(u * 1.4, 0.65, -1.2))
		eye(b, head, 0.22 - math.abs(u) * 0.06, p, A_EYE, false)
	end

	-- two heads on long necks rising out of its back
	for _, side in { -1, 1 } do
		local n1 = riseTo(b, "NeckSeg", "NeckSegA", torso, Vector3.new(side * 1.0, 1.6, 0.6), Vector3.new(side * 0.4, 1, 0.1), 2.0, 0.6, A_SKIN)
		local n2 = riseTo(b, "NeckSeg", "NeckSegB", n1, Vector3.new(0, 1.0, 0), Vector3.new(side * 0.2, 0.7, -0.7), 1.8, 0.52, A_SKIN)
		veins(b, n1, 2, side)
		amalgamHead(b, n2, if side < 0 then "HeadL" else "HeadR", if side < 0 then "NeckL" else "NeckR", if side < 0 then "JawL2" else "JawR2", faceTo(n2, Vector3.new(0, 1.0, 0), Vector3.new(-side * 0.2, -0.45, -1)), 0.8, 3, false)
	end

	for _, side in { -1, 1 } do
		local p = sideName(side)
		local upper = segTo(b, p .. "UpperArm", p .. "Shoulder", torso, Vector3.new(side * 2.0, 0.2, -0.8), Vector3.new(side * 0.5, -1, -0.5), 3.2, 0.75, A_SKIN)
		bulge(b, upper, 0.5, 2.0, 1.0, A_SKIN)
		local lower = segTo(b, p .. "LowerArm", p .. "Elbow", upper, Vector3.new(0, -1.6, 0), Vector3.new(side * 0.1, -1, -0.15), 3.0, 0.6, A_SKIN)
		hand(b, lower, p, 3.0, 1.1, 1.4)
	end
	backArms(b, torso, { Vector3.new(-1.3, 1.2, 1.6), Vector3.new(1.3, 1.2, 1.6), Vector3.new(-1.6, 0.0, 1.8), Vector3.new(1.6, 0.0, 1.8) }, 3.2)
	amalgamLegs(b, pelvis, 1.3, -0.6, 0.9, 0.95)
	return head
end }
