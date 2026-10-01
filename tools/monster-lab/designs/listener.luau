
---------------------------------------------------------------------------
-- Shared bits for the Listener: wet skin, glowing spots.

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

---------------------------------------------------------------------------
-- LISTENER A: the Drowned. Pale and swollen from the water, empty black holes for eyes,
-- gills on its neck, and a lower jaw split in two that hangs open down to its chest.

Designs.ListenerA = { height = 5.3, build = function(b: Builder): BasePart
	local SKIN = rgb(150, 158, 148)
	local SKIN2 = rgb(122, 132, 122)
	local BRUISE = rgb(70, 78, 84)
	local BONE = rgb(222, 222, 204)
	local GLOW = rgb(120, 255, 190)
	local BLACK = rgb(0, 0, 0)
	local mat = Enum.Material.SmoothPlastic
	local limb, joint = b.limb, b.joint

	local pelvis = limb("Pelvis", Vector3.new(1.7, 1.2, 1.15), SKIN, mat)
	egg(pelvis)
	wet(pelvis)
	joint("Waist", b.root, pelvis, cf(0, 0.2, 0), cf())
	local torso = limb("Torso", Vector3.new(2.3, 3.0, 1.5), SKIN, mat)
	egg(torso)
	wet(torso)
	joint("Spine", pelvis, torso, cf(0, 0.35, 0) * ang(rad(-35), 0, 0), cf(0, -1.35, 0))
	blob(b, "Belly", torso, cf(0, -0.9, -0.2), Vector3.new(1.9, 1.7, 1.3), SKIN, mat)
	for i = 0, 3 do
		blob(b, "Bruise", torso, cf((i % 2 - 0.5) * 0.9, 0.8 - i * 0.5, 0.45 + (i % 2) * 0.1), Vector3.new(0.7, 0.5, 0.7), BRUISE, mat)
	end
	glowSpots(b, torso, 1.1, -0.8, 6, 0.72, GLOW)
	local glow = Instance.new("PointLight")
	glow.Name = "EyeGlow"
	glow.Color = GLOW
	glow.Range = 8
	glow.Brightness = 0.7
	glow.Parent = torso

	local n1 = riseTo(b, "NeckA", "NeckA", torso, Vector3.new(0, 1.4, -0.2), Vector3.new(0, 0.75, -0.65), 0.8, 0.62, SKIN, mat)
	local n2 = riseTo(b, "NeckB", "NeckB", n1, Vector3.new(0, 0.4, 0), Vector3.new(0, 0.3, -1), 0.7, 0.58, SKIN, mat)
	local hs = Vector3.new(1.2, 1.4, 1.3)
	local head = limb("Head", hs, SKIN, mat)
	egg(head)
	wet(head)
	joint("Neck", n2, head, faceTo(n2, Vector3.new(0, 0.55, -0.1), Vector3.new(0, -0.35, -1)) , cf(0, -0.35, 0.1))
	-- no eyes: two deep holes
	for _, s in { -1, 1 } do
		local p, frame = onSurface(hs, Vector3.new(s * 0.26, 0.2, -0.6))
		blob(b, "Socket", head, CFrame.new(p) * (frame - frame.Position) * cf(0, 0, 0.02) * ang(0, 0, rad(s * -12)), Vector3.new(0.36, 0.42, 0.3), BLACK, mat)
		blob(b, "Brow", head, CFrame.new(p) * (frame - frame.Position) * cf(0, 0.24, 0.0), Vector3.new(0.42, 0.14, 0.2), SKIN2, mat)
		-- gills
		for g = 0, 2 do
			local gill = limb(if g == 1 then "Ear" .. sideName(s) else "Gill", Vector3.new(0.06, 0.55, 0.35), SKIN2, mat)
			egg(gill)
			joint(if g == 1 then "Ear" .. sideName(s) else "GillJoint", head, gill, cf(s * 0.55, -0.2 - g * 0.18, 0.15 + g * 0.08) * ang(0, rad(s * 20), rad(s * 15)), cf(0, 0.2, 0))
		end
	end
	blob(b, "Nose", head, cf(0, -0.05, -0.62), Vector3.new(0.12, 0.2, 0.12), BLACK, mat)
	blob(b, "Gullet", head, cf(0, -0.48, -0.32), Vector3.new(0.85, 0.75, 0.6), BLACK, mat)
	fangRow(b, head, hs, -0.3, 0.32, 9, 0.22, 0.055, false, BONE, 0.05)
	-- the lower jaw is split down the middle; both halves hang open
	for _, side in { -1, 1 } do
		local p = sideName(side)
		local half = limb("Jaw" .. p, Vector3.new(0.42, 0.32, 1.25), SKIN, mat)
		egg(half)
		wet(half)
		joint("Jaw" .. p, head, half, cf(side * 0.28, -0.5, 0.2) * ang(rad(-48), rad(side * 12), 0), cf(0, 0, 0.55))
		for t = 0, 4 do
			fang(b, half, cf(-side * 0.04, 0.14, -0.5 + t * 0.15) * ang(0, 0, math.pi - side * rad(10)), 0.18 - t * 0.015, 0.05, BONE)
		end
	end
	local tongue = limb("Tongue", Vector3.new(0.3, 0.12, 1.3), rgb(70, 40, 46), mat)
	egg(tongue)
	joint("TongueJoint", head, tongue, cf(0, -0.65, -0.2) * ang(rad(-55), 0, 0) * cf(0, 0, -0.45), cf())

	-- long swollen arms hanging forward, fingers dragging
	for _, side in { -1, 1 } do
		local p = sideName(side)
		blob(b, p .. "ShoulderMass", torso, cf(side * 0.95, 1.05, 0) * ang(0, 0, rad(side * 30)), Vector3.new(1.0, 0.7, 0.9), SKIN, mat)
		local upper = segTo(b, p .. "UpperArm", p .. "Shoulder", torso, Vector3.new(side * 1.1, 1.05, 0), Vector3.new(side * 0.2, -1, -0.35), 2.7, 0.55, SKIN, mat)
		local lower = segTo(b, p .. "LowerArm", p .. "Elbow", upper, Vector3.new(0, -1.35, 0), Vector3.new(side * 0.05, -1, -0.3), 2.8, 0.42, SKIN, mat)
		blob(b, "Bruise", lower, cf(0, 0.4, 0.12), Vector3.new(0.38, 0.9, 0.3), BRUISE, mat)
		local hand = limb(p .. "Hand", Vector3.new(0.55, 0.7, 0.25), SKIN2, mat)
		egg(hand)
		joint(p .. "Wrist", lower, hand, cf(0, -1.4, 0), cf(0, 0.3, 0))
		for f = 0, 2 do
			local finger = seg(b, p .. "Finger", p .. "Finger" .. (f + 1), hand, cf(-0.15 + f * 0.15, -0.3, 0) * ang(rad(-15), 0, rad(-10 + f * 10)), 1.5, 0.1, SKIN2, mat)
			fang(b, finger, cf(0, -0.75, 0), 0.14, 0.07, rgb(40, 40, 36))
		end
	end
	for _, side in { -1, 1 } do
		local p = sideName(side)
		local thigh = segTo(b, p .. "Thigh", p .. "Hip", pelvis, Vector3.new(side * 0.5, -0.25, 0), Vector3.new(side * 0.12, -1, -0.35), 2.5, 0.68, SKIN, mat)
		local shin = segTo(b, p .. "Shin", p .. "Knee", thigh, Vector3.new(0, -1.25, 0), Vector3.new(0, -1, 0.3), 2.6, 0.48, SKIN, mat)
		local foot = limb(p .. "Foot", Vector3.new(0.6, 0.32, 1.5), SKIN2, mat)
		egg(foot)
		joint(p .. "Ankle", shin, foot, faceTo(shin, Vector3.new(0, -1.3, 0), Vector3.new(0, 0, -1)), cf(0, 0.12, 0.4))
	end
	return head
end }

---------------------------------------------------------------------------
-- LISTENER B: the Lure. Tall, thin and dark, a blind fish-like head with an underbite
-- full of needle teeth, and a glowing bulb dangling in front of it. You see the light first.

Designs.ListenerB = { height = 5.6, build = function(b: Builder): BasePart
	local SKIN = rgb(34, 40, 38)
	local SKIN2 = rgb(52, 60, 56)
	local BONE = rgb(226, 228, 210)
	local GLOW = rgb(150, 255, 205)
	local BLACK = rgb(0, 0, 0)
	local mat = Enum.Material.SmoothPlastic
	local limb, joint = b.limb, b.joint

	local pelvis = limb("Pelvis", Vector3.new(1.4, 1.0, 0.9), SKIN, mat)
	egg(pelvis)
	wet(pelvis)
	joint("Waist", b.root, pelvis, cf(0, 0.2, 0), cf())
	local torso = limb("Torso", Vector3.new(1.7, 3.2, 1.0), SKIN, mat)
	egg(torso)
	wet(torso)
	joint("Spine", pelvis, torso, cf(0, 0.3, 0) * ang(rad(-25), 0, 0), cf(0, -1.45, 0))
	for i = 0, 4 do
		blob(b, "Rib", torso, cf(0, 0.9 - i * 0.38, -0.32), Vector3.new(1.6 - i * 0.12, 0.13, 0.55), SKIN2, mat)
	end
	for i = 0, 5 do
		ball(b, "Vertebra", torso, Vector3.new(0, 1.3 - i * 0.45, 0.42), 0.26, SKIN2, mat)
	end
	glowSpots(b, torso, 1.0, -1.0, 4, 0.47, GLOW)

	local n1 = riseTo(b, "NeckA", "NeckA", torso, Vector3.new(0, 1.5, -0.05), Vector3.new(0, 0.6, -0.8), 0.9, 0.42, SKIN, mat)
	local n2 = riseTo(b, "NeckB", "NeckB", n1, Vector3.new(0, 0.45, 0), Vector3.new(0, 0.1, -1), 0.8, 0.4, SKIN, mat)
	local hs = Vector3.new(1.7, 1.05, 1.9)
	local head = limb("Head", hs, SKIN2, mat)
	egg(head)
	wet(head)
	joint("Neck", n2, head, faceTo(n2, Vector3.new(0, 0.45, -0.1), Vector3.new(0, -0.2, -1)), cf(0, -0.05, 0.6))
	blob(b, "Gullet", head, cf(0, -0.32, -0.4), Vector3.new(1.2, 0.55, 1.05), BLACK, mat)
	fangRow(b, head, hs, -0.22, 0.66, 13, 0.42, 0.06, false, BONE, 0.05)
	-- the lower jaw is split in two halves that swing apart
	for _, side in { -1, 1 } do
		local p = sideName(side)
		local half = limb("Jaw" .. p, Vector3.new(0.9, 0.45, 2.15), SKIN2, mat)
		egg(half)
		wet(half)
		joint("Jaw" .. p, head, half, cf(side * 0.38, -0.5, 0.35) * ang(rad(-16), 0, 0), cf(0, 0, 0.85))
		for t = 0, 6 do
			fang(b, half, cf(side * 0.1 - side * t * 0.02, 0.14, -0.95 + t * 0.18) * ang(0, 0, math.pi + side * rad(12)), 0.46 - t * 0.045, 0.065, BONE)
		end
		local fin = limb("Ear" .. p, Vector3.new(0.07, 1.3, 1.1), SKIN2, mat)
		egg(fin)
		fin.Transparency = 0.15
		joint("Ear" .. p, head, fin, cf(side * 0.72, 0.0, 0.45) * ang(rad(-30), 0, side * rad(-65)), cf(0, -0.5, 0))
	end
	-- the lure: a stalk curling out of its forehead, a glowing bulb on the end
	local stalk: BasePart = head
	local at = cf(0, 0.48, -0.25) * ang(rad(-5), 0, 0)
	for i = 1, 6 do
		stalk = rise(b, "Stalk", "Lure" .. i, stalk, at, 0.5, 0.1 - i * 0.008, SKIN2, mat)
		at = cf(0, 0.25, 0) * ang(rad(-27), 0, 0)
	end
	local bulb = b.limb("Lure", Vector3.new(0.42, 0.42, 0.42), GLOW, Enum.Material.Neon, Enum.PartType.Ball)
	bulb.CastShadow = false
	joint("LureJoint", stalk, bulb, cf(0, 0.38, 0), cf())
	local light = Instance.new("PointLight")
	light.Name = "EyeGlow"
	light.Color = GLOW
	light.Range = 14
	light.Brightness = 1.6
	light.Parent = bulb

	for _, side in { -1, 1 } do
		local p = sideName(side)
		local upper = segTo(b, p .. "UpperArm", p .. "Shoulder", torso, Vector3.new(side * 0.95, 1.2, 0), Vector3.new(side * 0.35, -1, -0.2), 2.6, 0.32, SKIN, mat)
		local lower = segTo(b, p .. "LowerArm", p .. "Elbow", upper, Vector3.new(0, -1.3, 0), Vector3.new(side * 0.05, -1, -0.45), 2.8, 0.26, SKIN, mat)
		local hand = limb(p .. "Hand", Vector3.new(0.45, 0.6, 0.22), SKIN2, mat)
		egg(hand)
		joint(p .. "Wrist", lower, hand, cf(0, -1.4, 0), cf(0, 0.25, 0))
		for f = 0, 2 do
			local finger = seg(b, p .. "Finger", p .. "Finger" .. (f + 1), hand, cf(-0.13 + f * 0.13, -0.25, 0) * ang(rad(-10), 0, rad(-12 + f * 12)), 1.6, 0.08, SKIN2, mat)
			fang(b, finger, cf(0, -0.8, 0), 0.14, 0.06, BONE)
		end
	end
	for _, side in { -1, 1 } do
		local p = sideName(side)
		local thigh = segTo(b, p .. "Thigh", p .. "Hip", pelvis, Vector3.new(side * 0.45, -0.25, 0), Vector3.new(side * 0.1, -1, -0.35), 2.8, 0.46, SKIN, mat)
		bulge(b, thigh, 0.4, 1.8, 0.6, SKIN, mat)
		local shin = segTo(b, p .. "Shin", p .. "Knee", thigh, Vector3.new(0, -1.4, 0), Vector3.new(0, -1, 0.25), 2.8, 0.34, SKIN, mat)
		local foot = limb(p .. "Foot", Vector3.new(0.5, 0.28, 1.5), SKIN2, mat)
		egg(foot)
		joint(p .. "Ankle", shin, foot, faceTo(shin, Vector3.new(0, -1.4, 0), Vector3.new(0, 0, -1)), cf(0, 0.1, 0.45))
	end
	return head
end }

---------------------------------------------------------------------------
-- LISTENER C: the Split. A starved thing with its hands up by its long, blind head.
-- The whole head is two halves: when it hears you, it splits open down the middle.

Designs.ListenerC = { height = 5.2, build = function(b: Builder): BasePart
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
end }
