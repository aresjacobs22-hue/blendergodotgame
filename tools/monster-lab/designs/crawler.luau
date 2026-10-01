
---------------------------------------------------------------------------
-- CRAWLER A: the Spider. A pale human torso on eight long legs. Its bald head hangs
-- upside down off the front: six eyes at the bottom, a mouth on top.

Designs.CrawlerA = { height = 2.6, build = function(b: Builder): BasePart
	local PALE = rgb(186, 174, 166)
	local PALE2 = rgb(190, 176, 168)
	local DARK = rgb(70, 52, 50)
	local BONE = rgb(236, 228, 214)
	local BLACK = rgb(0, 0, 0)
	local smooth = Enum.Material.Plastic
	local limb, joint = b.limb, b.joint

	local body = limb("Body", Vector3.new(2.1, 1.25, 3.6), PALE, smooth)
	egg(body)
	joint("Waist", b.root, body, cf(0, 0.3, 0) * ang(rad(6), 0, 0), cf())
	for _, s in { -1, 1 } do
		blob(b, "Blade", body, cf(s * 0.5, 0.45, -0.6) * ang(rad(-10), 0, rad(s * 10)), Vector3.new(0.9, 0.4, 1.3), PALE2, smooth)
	end
	for i = 0, 7 do
		ball(b, "Vertebra", body, Vector3.new(0, 0.6 - math.abs(i - 3.5) * 0.03, -1.4 + i * 0.4), 0.3, PALE2, smooth)
	end
	for i = 0, 3 do
		blob(b, "Rib", body, cf(0, 0.05, -0.7 + i * 0.45) * ang(0, 0, 0), Vector3.new(2.2, 0.85, 0.18), PALE2, smooth)
	end
	local abdomen = limb("Abdomen", Vector3.new(2.3, 1.9, 2.8), PALE, smooth)
	egg(abdomen)
	joint("Tail", body, abdomen, cf(0, 0.25, 1.6) * ang(rad(18), 0, 0), cf(0, 0, -1.2))
	for i = 0, 3 do
		blob(b, "Stripe", abdomen, cf(0, 0.55 - i * 0.05, -0.6 + i * 0.5), Vector3.new(1.9 - i * 0.2, 0.9, 0.22), DARK, smooth)
	end

	-- the head, hung upside down: eyes underneath, the mouth on top
	local hs = Vector3.new(1.3, 1.5, 1.35)
	local head = limb("Head", hs, PALE, smooth)
	egg(head)
	joint("Neck", body, head, cf(0, 0.1, -1.95) * ang(rad(-10), 0, 0), cf(0, 0.1, 0.5))
	local eyes = {
		{ -0.24, -0.3, 0.3 }, { 0.24, -0.3, 0.3 },
		{ -0.47, -0.1, 0.16 }, { 0.47, -0.1, 0.16 },
		{ -0.13, -0.58, 0.13 }, { 0.13, -0.58, 0.13 },
	}
	for i, e in eyes do
		local p, frame = onSurface(hs, Vector3.new(e[1], e[2], -0.62))
		local rot = frame - frame.Position
		blob(b, "Socket", head, CFrame.new(p) * rot * cf(0, 0, 0.03), Vector3.new(e[3] * 1.15, e[3] * 1.15, e[3] * 0.7), BLACK, smooth)
		eye(b, head, e[3] * 0.38, p + frame.LookVector * 0.06, rgb(255, 40, 30), i == 1)
	end
	blob(b, "Gullet", head, cf(0, 0.38, -0.42), Vector3.new(0.9, 0.55, 0.55), BLACK, smooth)
	fangRow(b, head, hs, 0.14, 0.34, 8, 0.24, 0.07, true, BONE, 0.04)
	local jaw = limb("Jaw", Vector3.new(0.9, 0.36, 0.85), PALE, smooth)
	egg(jaw)
	joint("Jaw", head, jaw, cf(0, 0.52, 0.05) * ang(rad(22), 0, 0), cf(0, 0, 0.3))
	for i = -3, 3 do
		fang(b, jaw, cf(i * 0.1, -0.12, -0.36 + math.abs(i) * 0.03), 0.22 - math.abs(i) * 0.02, 0.065, BONE)
	end

	-- eight legs, knees arched high above the body
	local zs = { -1.25, -0.45, 0.35, 1.1 }
	local yaws = { 40, 14, -14, -40 }
	for i = 1, 4 do
		for _, side in { -1, 1 } do
			local p = sideName(side) .. i
			local upper, lower, len = archLeg(b, body, p, Vector3.new(side * 0.85, 0.15, zs[i]), side, yaws[i], 2.6, 0.22, 112, 128, PALE, smooth, 0.15)
			lower.Color = PALE2
			ball(b, "KneeKnob", upper, Vector3.new(0, -1.3, 0), 0.26, PALE2, smooth)
			blob(b, "Shin", lower, cf(0, -len * 0.3, 0), Vector3.new(0.12, len * 0.5, 0.12), DARK, smooth)
			fang(b, lower, cf(0, -len / 2 - 0.05, 0), 0.32, 0.08, rgb(20, 12, 12))
		end
	end
	return head
end }

---------------------------------------------------------------------------
-- CRAWLER B: the Patient. Someone in a torn hospital gown, bent over backwards and
-- running on all fours, with four arms too many. Its head hangs upside down at the
-- front, hair dragging on the floor.

Designs.CrawlerB = { height = 3.0, build = function(b: Builder): BasePart
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
end }

---------------------------------------------------------------------------
-- CRAWLER C: the Hands. A long pale body that walks on eight human arms. Where a face
-- should be there's a round mouth ringed with teeth.

Designs.CrawlerC = { height = 2.3, build = function(b: Builder): BasePart
	local SKIN = rgb(194, 180, 172)
	local SKIN2 = rgb(178, 162, 154)
	local DARK = rgb(90, 50, 50)
	local BONE = rgb(238, 230, 214)
	local BLACK = rgb(0, 0, 0)
	local smooth = Enum.Material.Plastic
	local limb, joint = b.limb, b.joint

	local body = limb("Body", Vector3.new(1.9, 1.35, 3.0), SKIN, smooth)
	egg(body)
	joint("Waist", b.root, body, cf(0, 0.35, -0.6), cf())
	local abdomen = limb("Abdomen", Vector3.new(1.75, 1.25, 2.8), SKIN, smooth)
	egg(abdomen)
	joint("Tail", body, abdomen, cf(0, -0.05, 1.3) * ang(rad(4), 0, 0), cf(0, 0, -1.15))
	local tailEnd = limb("TailEnd", Vector3.new(1.3, 0.95, 2.4), SKIN, smooth)
	egg(tailEnd)
	joint("TailEndJoint", abdomen, tailEnd, cf(0, -0.05, 1.2) * ang(rad(6), 0, 0), cf(0, 0, -0.9))
	local tip = limb("TailTip", Vector3.new(0.7, 0.55, 1.6), SKIN2, smooth)
	egg(tip)
	joint("TailTipJoint", tailEnd, tip, cf(0, -0.05, 1.0) * ang(rad(10), 0, 0), cf(0, 0, -0.55))
	for _, part in { body, abdomen, tailEnd } do
		for i = 0, 2 do
			ball(b, "Vertebra", part, Vector3.new(0, part.Size.Y * 0.45, -0.7 + i * 0.7), 0.3, SKIN2, smooth)
		end
	end

	-- the face is a mouth
	local hs = Vector3.new(1.55, 1.45, 1.3)
	local head = limb("Head", hs, SKIN, smooth)
	egg(head)
	joint("Neck", body, head, cf(0, 0.15, -1.55) * ang(rad(-6), 0, 0), cf(0, 0, 0.35))
	blob(b, "Lip", head, cf(0, -0.05, -0.5), Vector3.new(1.15, 1.08, 0.4), DARK, smooth)
	blob(b, "Gullet", head, cf(0, -0.05, -0.56), Vector3.new(0.9, 0.84, 0.36), BLACK, smooth)
	for ring = 0, 1 do
		local n = if ring == 0 then 14 else 9
		local r = if ring == 0 then 0.42 else 0.26
		for i = 0, n - 1 do
			local a = i / n * math.pi * 2 + ring * 0.3
			-- teeth around the rim, pointing in towards the throat
			fang(b, head, cf(math.cos(a) * r, -0.05 + math.sin(a) * r, -0.66 + ring * 0.06) * ang(0, 0, a - math.pi / 2) * ang(rad(-25), 0, 0), 0.17 - ring * 0.04, 0.06, BONE)
		end
	end
	local eyes = { { -0.42, 0.5 }, { 0.42, 0.5 }, { -0.2, 0.6 }, { 0.2, 0.6 } }
	for i, e in eyes do
		local p = onSurface(hs, Vector3.new(e[1], e[2], -0.45))
		eye(b, head, if i <= 2 then 0.13 else 0.09, p, rgb(255, 246, 236), i == 1)
	end

	-- eight arms for legs: elbows up, hands flat on the floor
	local legs = {
		{ part = body, z = -0.8, yaw = 34 },
		{ part = body, z = 0.6, yaw = 12 },
		{ part = abdomen, z = 0.0, yaw = -8 },
		{ part = tailEnd, z = 0.0, yaw = -28 },
	}
	for i, l in legs do
		for _, side in { -1, 1 } do
			local p = sideName(side) .. i
			local upper, lower, len = archLeg(b, l.part, p, Vector3.new(side * (l.part.Size.X / 2 - 0.15), 0, l.z), side, l.yaw, 1.7, 0.36, 104, 78, SKIN, smooth, 0.28)
			bulge(b, upper, 0.2, 1.1, 0.55, SKIN, smooth)
			ball(b, "Elbow", upper, Vector3.new(0, -0.8, 0), 0.36, SKIN2, smooth)
			local hand = limb("Hand", Vector3.new(0.7, 0.22, 0.85), SKIN2, smooth)
			egg(hand)
			local handAt = lower.CFrame * cf(0, -len / 2, 0)
			local flat = CFrame.new(handAt.Position + Vector3.new(0, 0.12 - handAt.Position.Y, 0)) * ang(0, side * rad(l.yaw) + side * rad(25), 0)
			joint("HandJoint", lower, hand, lower.CFrame:Inverse() * flat, cf())
			for f = 0, 3 do
				local finger = limb("Finger", Vector3.new(0.11, 0.11, 0.85), SKIN2, smooth)
				egg(finger)
				joint("FingerJoint", hand, finger, cf(-0.24 + f * 0.16, -0.03, -0.3) * ang(0, rad(36 - f * 24), 0) * cf(0, 0, -0.4), cf())
			end
		end
	end
	return head
end }
