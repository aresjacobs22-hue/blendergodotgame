
---------------------------------------------------------------------------
-- Statues. Arms, elbows, neck and spine are built with plain (unrotated) joint frames
-- so the STATUE_POSES offsets mean the same thing on every design.

Designs.STATUE_POSES = {
	{ LShoulder = ang(rad(85), 0, rad(-8)), RShoulder = ang(rad(85), 0, rad(8)), Neck = ang(rad(-8), 0, 0) },
	{ LShoulder = ang(rad(140), 0, rad(25)), RShoulder = ang(rad(140), 0, rad(-25)), LElbow = ang(rad(95), 0, 0), RElbow = ang(rad(95), 0, 0), Neck = ang(rad(18), 0, 0) },
	{ RShoulder = ang(rad(95), rad(-10), 0), LShoulder = ang(rad(10), 0, rad(-10)), Neck = ang(0, rad(-25), rad(10)) },
	{ Spine = ang(rad(-25), 0, 0), LShoulder = ang(rad(70), 0, rad(-30)), RShoulder = ang(rad(70), 0, rad(30)), LElbow = ang(rad(30), 0, 0), RElbow = ang(rad(30), 0, 0), Neck = ang(rad(-25), 0, 0) },
	{ Neck = ang(rad(5), rad(10), rad(65)), Spine = ang(0, rad(15), rad(-6)), LShoulder = ang(rad(-10), 0, rad(-6)) },
	{ LShoulder = ang(rad(165), 0, rad(-15)), RShoulder = ang(rad(165), 0, rad(15)), LElbow = ang(rad(40), 0, 0), RElbow = ang(rad(40), 0, 0), Neck = ang(rad(-15), 0, 0) },
} :: { { [string]: CFrame } }

function Designs.applyStatuePose(rig: any, index: number)
	local pose = Designs.STATUE_POSES[(index - 1) % #Designs.STATUE_POSES + 1]
	for _, m in rig.joints do
		local offset = pose[m.Name]
		if offset then
			m.C0 = m.C0 * offset
		end
	end
end

function Designs.solve(rig: any)
	for _, m in rig.joints do
		m.Part1.CFrame = m.Part0.CFrame * m.C0 * m.C1:Inverse()
	end
end

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

---------------------------------------------------------------------------
-- STATUE A: the Mourner. A hooded figure in long robes, the face lost in the shadow of
-- the hood. The real one has two red points of light in there.

Designs.StatueA = { height = 4.6, build = function(b: Builder, decoy: boolean?): BasePart
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
end }

---------------------------------------------------------------------------
-- STATUE B: the Mannequin. Tall, smooth, jointed like an artist's doll, with a blank
-- egg for a head. A crack runs down its face; in the real one, something red glows
-- through it.

Designs.StatueB = { height = 5.1, build = function(b: Builder, decoy: boolean?): BasePart
	local marble = Enum.Material.Marble
	local limb, joint = b.limb, b.joint
	local pelvis = limb("Pelvis", Vector3.new(1.5, 1.0, 0.95), MARBLE, marble)
	egg(pelvis)
	joint("Waist", b.root, pelvis, cf(0, 0.2, 0), cf())
	local torso = limb("Torso", Vector3.new(1.75, 2.6, 1.0), MARBLE, marble)
	egg(torso)
	joint("Spine", pelvis, torso, cf(0, 0.55, 0), cf(0, -1.25, 0))
	blob(b, "Chest", torso, cf(0, 0.55, -0.05), Vector3.new(1.9, 1.3, 1.05), MARBLE, marble)
	ball(b, "WaistBall", pelvis, Vector3.new(0, 0.5, 0), 0.75, MARBLE2, marble)
	local neck = limb("NeckBone", Vector3.new(0.4, 1.0, 0.4), MARBLE2, marble)
	egg(neck)
	joint("NeckBase", torso, neck, cf(0, 1.35, 0), cf(0, -0.4, 0))
	local hs = Vector3.new(1.0, 1.45, 1.15)
	local head = limb("Head", hs, MARBLE, marble)
	egg(head)
	joint("Neck", neck, head, cf(0, 0.35, 0), cf(0, -0.6, 0.05))
	-- the crack down its face
	local crackColor = if decoy then CRACK else RED
	local crackMat = if decoy then Enum.Material.SmoothPlastic else Enum.Material.Neon
	local pts = { { 0.05, 0.6 }, { -0.06, 0.35 }, { 0.08, 0.1 }, { -0.04, -0.15 }, { 0.06, -0.42 } }
	for i = 1, #pts - 1 do
		local a, c = pts[i], pts[i + 1]
		local p1 = onSurface(hs, Vector3.new(a[1], a[2], -0.57))
		local p2 = onSurface(hs, Vector3.new(c[1], c[2], -0.57))
		local mid = (p1 + p2) / 2
		local seg2 = b.limb("Crack", Vector3.new(0.05, (p2 - p1).Magnitude + 0.03, 0.05), crackColor, crackMat)
		seg2.CastShadow = false
		joint("CrackJoint", head, seg2, CFrame.new(mid) * ang(0, 0, math.atan2(-(p2.X - p1.X), p2.Y - p1.Y)), cf())
	end
	if not decoy then
		local glow = Instance.new("PointLight")
		glow.Name = "EyeGlow"
		glow.Color = RED
		glow.Range = 7
		glow.Brightness = 1
		glow.Parent = head
	end
	for _, side in { -1, 1 } do
		ball(b, "ShoulderBall", torso, Vector3.new(side * 1.0, 1.05, 0), 0.6, MARBLE2, marble)
	end
	-- arms
	for _, side in { -1, 1 } do
		local p = sideName(side)
		local upper = seg(b, p .. "UpperArm", p .. "Shoulder", torso, cf(side * 1.05, 1.05, 0), 2.4, 0.42, MARBLE, marble)
		ball(b, "ElbowBall", upper, Vector3.new(0, -1.2, 0), 0.4, MARBLE2, marble)
		local lower = seg(b, p .. "LowerArm", p .. "Elbow", upper, cf(0, -1.2, 0), 2.3, 0.34, MARBLE, marble)
		ball(b, "WristBall", lower, Vector3.new(0, -1.15, 0), 0.28, MARBLE2, marble)
		local hand = limb(p .. "Hand", Vector3.new(0.4, 0.65, 0.18), MARBLE, marble)
		egg(hand)
		joint(p .. "Wrist", lower, hand, cf(0, -1.15, 0), cf(0, 0.32, 0))
		for f = 0, 3 do
			local finger = limb("Finger", Vector3.new(0.07, 0.7, 0.07), MARBLE, marble)
			egg(finger)
			joint("FingerJoint", hand, finger, cf(-0.12 + f * 0.08, -0.3, 0) * ang(rad(-6), 0, rad(-5 + f * 3)), cf(0, 0.28, 0))
		end
	end
	for _, side in { -1, 1 } do
		local p = sideName(side)
		ball(b, "HipBall", pelvis, Vector3.new(side * 0.45, -0.35, 0), 0.6, MARBLE2, marble)
		local thigh = seg(b, p .. "Thigh", p .. "Hip", pelvis, cf(side * 0.45, -0.35, 0), 2.3, 0.6, MARBLE, marble)
		ball(b, "KneeBall", thigh, Vector3.new(0, -1.15, 0), 0.48, MARBLE2, marble)
		local shin = seg(b, p .. "Shin", p .. "Knee", thigh, cf(0, -1.15, 0), 2.2, 0.46, MARBLE, marble)
		local foot = limb(p .. "Foot", Vector3.new(0.5, 0.3, 1.2), MARBLE, marble)
		egg(foot)
		joint(p .. "Ankle", shin, foot, cf(0, -1.1, 0), cf(0, 0.05, 0.3))
	end
	return head
end }

---------------------------------------------------------------------------
-- STATUE C: the Saint. A robed saint with a crown of spikes and three faces, front and
-- both sides, all screaming. Whichever way you go, one of them is facing you.

Designs.StatueC = { height = 4.6, build = function(b: Builder, decoy: boolean?): BasePart
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
end }
