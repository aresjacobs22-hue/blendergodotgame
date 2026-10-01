--!strict
-- Monster design sandbox: same builder as Monsters.luau, plus organic helpers.
local Designs = {}

export type Builder = {
	limb: (name: string, size: Vector3, color: Color3?, material: Enum.Material?, shape: Enum.PartType?) -> Part,
	joint: (name: string, parent: BasePart, child: BasePart, c0: CFrame, c1: CFrame) -> Motor6D,
	model: Model,
	root: Part,
}

local function rad(deg: number): number
	return math.rad(deg)
end
local rgb = Color3.fromRGB
local ang = CFrame.Angles
local cf = CFrame.new

-- CFrame.lookAt, spelled out (Lune's lookAt disagrees with Roblox's).
local function lookAt(pos: Vector3, target: Vector3): CFrame
	local look = (target - pos).Unit
	local right = look:Cross(Vector3.yAxis)
	if right.Magnitude < 1e-4 then
		right = look:Cross(Vector3.zAxis)
	end
	right = right.Unit
	return CFrame.fromMatrix(pos, right, right:Cross(look), -look)
end

local function egg(p: BasePart)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
end

local function newBuilder(kind: string, rootHeight: number): (Builder, { Motor6D })
	local model = Instance.new("Model")
	model.Name = "Monster"
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1.5)
	root.Transparency = 1
	root.Anchored = true
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
			p.Anchored = true
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
