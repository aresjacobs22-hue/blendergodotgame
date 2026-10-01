
---------------------------------------------------------------------------
-- HOLLOW A: the Gaunt. Starved, hunched, skull face with pinpoint eyes, jaw hanging.

Designs.HollowA = { height = 6.1, build = function(b: Builder): BasePart
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
end }

---------------------------------------------------------------------------
-- HOLLOW B: the Grin. A tall shadow. In the dark you only see its eyes and a smile
-- from ear to ear, both glowing.

Designs.HollowB = { height = 6.6, build = function(b: Builder): BasePart
	local SKIN = rgb(16, 16, 16)
	local SKIN2 = rgb(26, 26, 26)
	local GLOW = rgb(255, 255, 255)
	local BLACK = rgb(0, 0, 0)
	local mat = Enum.Material.Slate
	local smooth = Enum.Material.SmoothPlastic
	local limb, joint = b.limb, b.joint

	local pelvis = limb("Pelvis", Vector3.new(1.5, 1.1, 1.0), SKIN, mat)
	egg(pelvis)
	joint("Waist", b.root, pelvis, cf(0, 0.2, 0), cf())
	local torso = limb("Torso", Vector3.new(1.8, 3.4, 1.05), SKIN, mat)
	egg(torso)
	joint("Spine", pelvis, torso, cf(0, 0.3, 0) * ang(rad(-12), 0, 0), cf(0, -1.5, 0))
	blob(b, "Chest", torso, cf(0, 0.6, -0.06), Vector3.new(2.0, 1.7, 1.0), SKIN, mat)
	blob(b, "Belly", torso, cf(0, -1.2, 0.06), Vector3.new(1.0, 1.4, 0.7), SKIN, mat)
	for i = 0, 5 do
		ball(b, "Vertebra", torso, Vector3.new(0, 1.3 - i * 0.45, 0.45), 0.26, SKIN2, mat)
	end

	-- a long neck curling forward so the face hangs out in front of it
	local n1 = rise(b, "NeckA", "NeckA", torso, cf(0, 1.55, -0.05) * ang(rad(-16), 0, 0), 1.0, 0.42, SKIN, mat)
	local n2 = rise(b, "NeckB", "NeckB", n1, cf(0, 0.5, 0) * ang(rad(-24), 0, 0), 1.0, 0.38, SKIN, mat)
	local n3 = rise(b, "NeckC", "NeckC", n2, cf(0, 0.5, 0) * ang(rad(-26), 0, 0), 0.8, 0.36, SKIN, mat)
	local hs = Vector3.new(1.45, 1.1, 1.3)
	local head = limb("Head", hs, SKIN, mat)
	egg(head)
	joint("Neck", n3, head, cf(0, 0.4, 0) * ang(rad(86), 0, rad(-10)), cf(0, -0.2, 0.42))
	local js = Vector3.new(1.22, 0.7, 1.12)
	local jaw = limb("Jaw", js, SKIN, mat)
	egg(jaw)
	joint("Jaw", head, jaw, cf(0, -0.3, 0.22) * ang(rad(-16), 0, 0), cf(0, 0.08, 0.22))
	blob(b, "Gullet", head, cf(0, -0.32, -0.08), Vector3.new(1.25, 0.5, 1.05), BLACK, smooth)
	-- eyes: thin glowing crescents, squeezed up by the smile
	for _, s in { -1, 1 } do
		local p, frame = onSurface(hs, Vector3.new(s * 0.34, 0.2, -0.62))
		local rot = frame - frame.Position
		local e = b.limb("Eye", Vector3.new(0.36, 0.22, 0.1), GLOW, Enum.Material.Neon)
		egg(e)
		e.CastShadow = false
		joint("EyeJoint", head, e, CFrame.new(p) * rot * cf(0, 0, 0.03) * ang(0, 0, rad(s * 14)), cf())
		local lid = b.limb("Lid", Vector3.new(0.44, 0.22, 0.12), SKIN, mat)
		egg(lid)
		joint("LidJoint", head, lid, CFrame.new(p) * rot * cf(0, -0.075, 0.01) * ang(0, 0, rad(s * 14)), cf())
	end
	local glow = Instance.new("PointLight")
	glow.Name = "EyeGlow"
	glow.Range = 8
	glow.Brightness = 0.8
	glow.Color = GLOW
	glow.Parent = head
	-- the grin: two rows of glowing fangs, ear to ear, corners turned up
	for i = 0, 15 do
		local u = i / 15 * 2 - 1
		local x = u * 0.7
		local y = -0.3 + 0.24 * u * u
		local len = 0.38 - math.abs(u) * 0.14 + (i % 3) * 0.04
		local p, frame = onSurface(hs + Vector3.new(0.01, 0.01, 0.01), Vector3.new(x, y, -0.66))
		local t = b.limb("Tooth", Vector3.new(0.085, len, 0.05), GLOW, Enum.Material.Neon)
		egg(t)
		t.CastShadow = false
		joint("ToothJoint", head, t, CFrame.new(p) * (frame - frame.Position) * ang(0, 0, -u * 0.5) * cf(0, -len * 0.3, 0), cf())
		local lp, lframe = onSurface(js + Vector3.new(0.01, 0.01, 0.01), Vector3.new(x * 0.95, 0.12 + 0.3 * u * u, -0.6))
		local llen = len * 0.85
		local lt = b.limb("Tooth", Vector3.new(0.085, llen, 0.05), GLOW, Enum.Material.Neon)
		egg(lt)
		lt.CastShadow = false
		joint("ToothJoint", jaw, lt, CFrame.new(lp) * (lframe - lframe.Position) * ang(0, 0, -u * 0.5) * cf(0, llen * 0.3, 0), cf())
	end

	for _, side in { -1, 1 } do
		local p = sideName(side)
		blob(b, p .. "ShoulderMass", torso, cf(side * 0.8, 1.15, 0) * ang(0, 0, rad(side * 28)), Vector3.new(0.8, 0.5, 0.62), SKIN, mat)
		local upper = seg(b, p .. "UpperArm", p .. "Shoulder", torso, cf(side * 1.0, 1.2, 0) * ang(rad(18), 0, rad(side * 6)), 3.3, 0.34, SKIN, mat)
		bulge(b, upper, 0.5, 1.7, 0.48, SKIN, mat)
		local lower = seg(b, p .. "LowerArm", p .. "Elbow", upper, cf(0, -1.65, 0) * ang(rad(6), 0, 0), 3.5, 0.28, SKIN, mat)
		bulge(b, lower, 0.75, 1.6, 0.38, SKIN, mat)
		local hand = limb(p .. "Hand", Vector3.new(0.5, 0.75, 0.25), SKIN2, mat)
		egg(hand)
		joint(p .. "Wrist", lower, hand, cf(0, -1.75, 0), cf(0, 0.3, 0))
		for f = 0, 3 do
			local finger = seg(b, p .. "Finger", p .. "Finger" .. (f + 1), hand, cf(-0.18 + f * 0.12, -0.3, 0) * ang(rad(5), 0, rad(-8 + f * 5)), 1.2, 0.09, SKIN2, mat)
			seg(b, p .. "FingerTip", p .. "FingerTip" .. (f + 1), finger, cf(0, -0.6, 0) * ang(rad(14), 0, 0), 1.1, 0.08, SKIN2, mat)
		end
	end
	for _, side in { -1, 1 } do
		local p = sideName(side)
		local thigh = seg(b, p .. "Thigh", p .. "Hip", pelvis, cf(side * 0.48, -0.25, 0) * ang(rad(10), 0, rad(side * 3)), 3.2, 0.46, SKIN, mat)
		bulge(b, thigh, 0.4, 2.2, 0.64, SKIN, mat)
		local shin = seg(b, p .. "Shin", p .. "Knee", thigh, cf(0, -1.6, 0) * ang(rad(-18), 0, 0), 3.3, 0.34, SKIN, mat)
		bulge(b, shin, 0.75, 1.5, 0.46, SKIN, mat)
		local foot = limb(p .. "Foot", Vector3.new(0.48, 0.3, 1.5), SKIN2, mat)
		egg(foot)
		joint(p .. "Ankle", shin, foot, cf(0, -1.65, 0) * ang(rad(8), 0, 0), cf(0, 0.1, 0.35))
	end
	return head
end }

---------------------------------------------------------------------------
-- HOLLOW C: the Widow. A tall figure in a long black dress, long black hair, and a
-- white porcelain mask. The mask's jaw drops open when it screams.

Designs.HollowC = { height = 6.0, build = function(b: Builder): BasePart
	local SKIN = rgb(24, 24, 24)
	local CLOTH = rgb(14, 14, 14)
	local HAIR = rgb(6, 6, 6)
	local MASK = rgb(232, 229, 222)
	local BLACK = rgb(0, 0, 0)
	local fabric = Enum.Material.Fabric
	local smooth = Enum.Material.SmoothPlastic
	local limb, joint = b.limb, b.joint

	local pelvis = limb("Pelvis", Vector3.new(1.4, 1.0, 0.95), CLOTH, fabric)
	egg(pelvis)
	joint("Waist", b.root, pelvis, cf(0, 0.2, 0), cf())
	-- a pleated dress: long panels flaring out from the waist, ragged at the hem
	for i = 0, 13 do
		local a = i / 14 * math.pi * 2
		local len = 4.3 + ((i * 5) % 7) * 0.12
		local panel = limb("Dress", Vector3.new(0.85, len, 0.08), CLOTH, fabric)
		joint("DressJoint", pelvis, panel, cf(0, -0.1, 0.05) * ang(0, a, 0) * cf(0, 0, -0.6) * ang(rad(13), 0, 0), cf(0, len / 2, 0))
	end
	blob(b, "Skirt", pelvis, cf(0, -1.0, 0.05), Vector3.new(1.5, 2.2, 1.35), CLOTH, fabric)
	local torso = limb("Torso", Vector3.new(1.6, 3.0, 1.0), CLOTH, fabric)
	egg(torso)
	joint("Spine", pelvis, torso, cf(0, 0.3, 0) * ang(rad(-12), 0, 0), cf(0, -1.35, 0))
	local neck = rise(b, "NeckBone", "NeckBase", torso, cf(0, 1.4, -0.05) * ang(rad(-6), 0, 0), 0.9, 0.34, SKIN, smooth)
	local head = limb("Head", Vector3.new(1.1, 1.4, 1.2), HAIR, smooth)
	egg(head)
	joint("Neck", neck, head, cf(0, 0.45, 0) * ang(rad(14), 0, rad(-20)), cf(0, -0.6, 0.05))
	-- the mask
	local ms = Vector3.new(1.0, 1.05, 0.46)
	local mask = blob(b, "Mask", head, cf(0, 0.14, -0.42), ms, MASK, smooth)
	for _, s in { -1, 1 } do
		blob(b, "EyeHole", mask, cf(s * 0.22, 0.02, -0.19) * ang(0, rad(s * 16), rad(s * 18)), Vector3.new(0.36, 0.17, 0.14), BLACK, smooth)
		blob(b, "Tear", mask, cf(s * 0.25, -0.26, -0.17) * ang(0, rad(s * 18), 0), Vector3.new(0.05, 0.5, 0.06), rgb(20, 20, 20), smooth)
	end
	eye(b, mask, 0.045, Vector3.new(-0.21, 0.02, -0.25), rgb(255, 255, 255), true)
	eye(b, mask, 0.045, Vector3.new(0.21, 0.02, -0.25), rgb(255, 255, 255))
	local crack = limb("Crack", Vector3.new(0.03, 0.5, 0.05), rgb(50, 50, 50), smooth)
	joint("CrackJoint", mask, crack, cf(0.08, 0.3, -0.22) * ang(0, 0, rad(20)), cf())
	local crack2 = limb("Crack", Vector3.new(0.025, 0.28, 0.05), rgb(50, 50, 50), smooth)
	joint("CrackJoint", mask, crack2, cf(0.17, 0.12, -0.23) * ang(0, 0, rad(-35)), cf())
	blob(b, "Gullet", head, cf(0, -0.42, -0.32), Vector3.new(0.62, 0.55, 0.5), BLACK, smooth)
	for i = -2, 2 do
		fang(b, head, cf(i * 0.1, -0.3, -0.5 + math.abs(i) * 0.03), 0.18 - math.abs(i) * 0.02, 0.05, rgb(220, 214, 200))
	end
	local jaw = limb("Jaw", Vector3.new(0.66, 0.42, 0.34), MASK, smooth)
	egg(jaw)
	joint("Jaw", head, jaw, cf(0, -0.3, -0.18) * ang(rad(-2), 0, 0), cf(0, 0.12, 0.2))
	blob(b, "MouthLine", jaw, cf(0, 0.08, -0.16), Vector3.new(0.26, 0.035, 0.05), BLACK, smooth)
	-- hair: a curtain of long black strands down its back and over its shoulders
	blob(b, "Crown", head, cf(0, 0.3, 0.12), Vector3.new(1.22, 1.08, 1.2), HAIR, smooth)
	blob(b, "HairMass", head, cf(0.3, -1.0, 0.42) * ang(rad(4), 0, rad(18)), Vector3.new(1.3, 3.2, 0.5), HAIR, smooth)
	for i = 0, 33 do
		local a = (i / 33 - 0.5) * math.pi * 1.6
		local len = 2.6 + ((i * 5) % 7) * 0.32
		local strand = limb("Hair", Vector3.new(0.12, len, 0.1), HAIR, smooth)
		egg(strand)
		joint("HairJoint", head, strand, cf(math.sin(a) * 0.55, 0.32, 0.1 + math.cos(a) * 0.5) * ang(rad(4), 0, rad(18)) * ang(0, a, 0) * ang(rad(-3), 0, rad(((i * 3) % 5 - 2) * 1.5)), cf(0, len / 2 - 0.2, 0))
	end

	for _, side in { -1, 1 } do
		local p = sideName(side)
		blob(b, p .. "ShoulderMass", torso, cf(side * 0.7, 1.1, 0) * ang(0, 0, rad(side * 30)), Vector3.new(0.85, 0.5, 0.65), CLOTH, fabric)
		local upper = seg(b, p .. "UpperArm", p .. "Shoulder", torso, cf(side * 0.85, 1.1, 0) * ang(rad(14), 0, rad(side * 4)), 3.0, 0.38, CLOTH, fabric)
		local lower = seg(b, p .. "LowerArm", p .. "Elbow", upper, cf(0, -1.5, 0) * ang(rad(12), 0, 0), 3.1, 0.22, SKIN, smooth)
		local hand = limb(p .. "Hand", Vector3.new(0.4, 0.6, 0.2), SKIN, smooth)
		egg(hand)
		joint(p .. "Wrist", lower, hand, cf(0, -1.55, 0), cf(0, 0.26, 0))
		for f = 0, 3 do
			local finger = seg(b, p .. "Finger", p .. "Finger" .. (f + 1), hand, cf(-0.14 + f * 0.095, -0.25, 0) * ang(rad(4), 0, rad(-6 + f * 4)), 1.2, 0.07, SKIN, smooth)
			local tip = seg(b, p .. "FingerTip", p .. "FingerTip" .. (f + 1), finger, cf(0, -0.6, 0) * ang(rad(16), 0, 0), 1.1, 0.06, SKIN, smooth)
			fang(b, tip, cf(0, -0.6, 0), 0.13, 0.045, rgb(200, 196, 186))
		end
	end
	for _, side in { -1, 1 } do
		local p = sideName(side)
		local thigh = seg(b, p .. "Thigh", p .. "Hip", pelvis, cf(side * 0.38, -0.25, 0) * ang(rad(4), 0, 0), 2.8, 0.4, SKIN, smooth)
		local shin = seg(b, p .. "Shin", p .. "Knee", thigh, cf(0, -1.4, 0) * ang(rad(-6), 0, 0), 2.8, 0.28, SKIN, smooth)
		local foot = limb(p .. "Foot", Vector3.new(0.34, 0.22, 1.05), SKIN, smooth)
		egg(foot)
		joint(p .. "Ankle", shin, foot, cf(0, -1.4, 0) * ang(rad(2), 0, 0), cf(0, 0.05, 0.3))
	end
	return head
end }
