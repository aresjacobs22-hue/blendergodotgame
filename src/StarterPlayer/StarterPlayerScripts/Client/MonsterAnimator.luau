--!strict
-- Procedural animation for every monster, run locally on each client. Nothing
-- here walks smoothly: heads snap to new angles, jaws hang, limbs twitch.
--   Hollow    lurching gait, arms drag (or reach for you), unhinged jaw
--   Crawler   eight limbs skittering, upside-down face snapping around
--   Listener  head sways side to side listening; it splits open when it charges
--   Statue    no animation at all: a new pose every time it moves while unseen
--   Amalgam   four legs, front arms reaching, back arms writhing, three heads

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Audio = require(Shared:WaitForChild("Audio"))
local Monsters = require(Shared:WaitForChild("Monsters"))

local MonsterAnimator = {}

type Joint = { motor: Motor6D, base: CFrame }
type Rig = {
	model: Model,
	root: BasePart,
	kind: string,
	joints: { [string]: Joint },
	gait: number,
	twitchAt: { [string]: number },
	headTarget: { [string]: CFrame },
	headCurrent: { [string]: CFrame },
	nextClick: number,
	lastStepSign: number,
	pose: number,
	eyeGlow: PointLight?,
}

local current: Rig? = nil

local function collect(model: Model): Rig?
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end
	local joints: { [string]: Joint } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") and not joints[d.Name] then
			joints[d.Name] = { motor = d, base = d.C0 }
		end
	end
	if not joints.Neck then
		return nil -- still replicating
	end
	local glow = model:FindFirstChild("EyeGlow", true)
	local kind = model:GetAttribute("Kind")
	return {
		model = model,
		root = root,
		kind = if typeof(kind) == "string" then kind else "Hollow",
		joints = joints,
		gait = 0,
		twitchAt = {},
		headTarget = {},
		headCurrent = {},
		nextClick = os.clock() + 3,
		lastStepSign = 1,
		pose = 0,
		eyeGlow = if glow and glow:IsA("PointLight") then glow else nil,
	}
end

local function set(rig: Rig, name: string, offset: CFrame)
	local j = rig.joints[name]
	if j then
		j.motor.C0 = j.base * offset
	end
end

local function rnd(scale: number): number
	return (math.random() - 0.5) * scale
end

-- A head that holds still, then snaps to a new angle.
local function twitchHead(rig: Rig, name: string, dt: number, interval: number, yaw: number, pitch: number, roll: number, snap: number, extra: CFrame?)
	local t = os.clock()
	if t >= (rig.twitchAt[name] or 0) then
		rig.twitchAt[name] = t + interval * (0.3 + math.random())
		rig.headTarget[name] = CFrame.Angles(rnd(pitch), rnd(yaw), rnd(roll))
	end
	local target = rig.headTarget[name] or CFrame.new()
	if extra then
		target = extra * target:Lerp(CFrame.new(), 0.6)
	end
	local cur = rig.headCurrent[name] or CFrame.new()
	cur = cur:Lerp(target, math.min(1, dt * snap))
	rig.headCurrent[name] = cur
	set(rig, name, cur * CFrame.Angles(rnd(0.04), rnd(0.04), rnd(0.04)))
end

local function footstep(rig: Rig, s: number, speed: number, volume: number, pitch: number)
	local sign = if s >= 0 then 1 else -1
	if sign ~= rig.lastStepSign and speed > 2 then
		Audio.playAt("MonsterStep", rig.root.Position - Vector3.new(0, 4, 0), math.clamp(speed / 11, 0.4, 1.5) * volume, pitch + math.random() * 0.2, 110)
	end
	rig.lastStepSign = sign
end

local function animateHollow(rig: Rig, dt: number, speed: number, state: string)
	local t = os.clock()
	local chase = state == "Chase" or state == "HuntLocker"
	local kill = state == "Kill"
	local staring = state == "Apparition"
	local stride = math.clamp(speed / 14, 0, 1.2)
	local g = rig.gait
	local s1, s2 = math.sin(g), math.sin(g + math.pi)

	twitchHead(rig, "Neck", dt, if chase then 0.25 elseif staring then 2.5 else 1.1, 1.0, 0.7, if staring then 0.4 else 1.4, if chase then 32 else 18, if staring then CFrame.Angles(0.15, 0, 1.1) else nil)
	local jawOpen = if kill then 1.1 + math.random() * 0.2 elseif chase then 0.55 + math.abs(math.sin(t * 14)) * 0.35 elseif staring then 0.7 else 0.12 + (math.sin(t * 1.7) + 1) * 0.08
	set(rig, "Jaw", CFrame.Angles(-jawOpen, 0, 0))
	local lean = if chase then -0.28 elseif kill then -0.2 else 0
	set(rig, "Spine", CFrame.Angles(lean + math.abs(s1) * 0.06 * stride + math.sin(t * 0.8) * 0.03, s1 * 0.08 * stride, math.sin(t * 0.9) * 0.05))
	set(rig, "Waist", CFrame.new(0, math.abs(math.cos(g)) * 0.25 * stride, 0) * CFrame.Angles(0, -s1 * 0.12 * stride, 0))
	set(rig, "LHip", CFrame.Angles(s1 * 0.75 * stride, 0, 0))
	set(rig, "RHip", CFrame.Angles(s2 * 0.75 * stride, 0, 0))
	set(rig, "LKnee", CFrame.Angles(-math.max(0, math.cos(g)) * 0.9 * stride, 0, 0))
	set(rig, "RKnee", CFrame.Angles(-math.max(0, math.cos(g + math.pi)) * 0.9 * stride, 0, 0))
	set(rig, "LAnkle", CFrame.Angles(s1 * 0.3 * stride, 0, 0))
	set(rig, "RAnkle", CFrame.Angles(s2 * 0.3 * stride, 0, 0))
	local reach = if chase or kill then 1.3 else 0
	set(rig, "LShoulder", CFrame.Angles(reach + s2 * 0.4 * stride + math.sin(t * 1.3) * 0.06 + (if math.random() < 0.02 then rnd(0.6) else 0), 0, -0.12 * reach))
	set(rig, "RShoulder", CFrame.Angles(reach + s1 * 0.4 * stride + math.sin(t * 1.1 + 1) * 0.06 + (if math.random() < 0.02 then rnd(0.6) else 0), 0, 0.12 * reach))
	set(rig, "LElbow", CFrame.Angles(-0.15 - reach * 0.25 + math.sin(t * 2.1) * 0.05, 0, 0))
	set(rig, "RElbow", CFrame.Angles(-0.15 - reach * 0.25 + math.sin(t * 2.3 + 2) * 0.05, 0, 0))
	for i = 1, 4 do
		local curl = (math.sin(t * 6 + i * 1.3) + 1) * 0.15 + (if chase or kill then 0.45 else 0) + rnd(0.05)
		set(rig, "LFinger" .. i, CFrame.Angles(-curl, 0, 0))
		set(rig, "RFinger" .. i, CFrame.Angles(-curl, 0, 0))
	end
	footstep(rig, s1, speed, 1, 0.85)
end

local function animateCrawler(rig: Rig, dt: number, speed: number, state: string)
	local t = os.clock()
	local chase = state == "Chase" or state == "HuntLocker"
	local kill = state == "Kill"
	local stride = math.clamp(speed / 12, 0, 1.4)
	local g = rig.gait * 1.6
	twitchHead(rig, "Neck", dt, if chase then 0.15 else 0.7, 1.2, 0.6, 1.6, 40, nil)
	set(rig, "Jaw", CFrame.Angles(if kill then 1.0 elseif chase then 0.5 + math.abs(math.sin(t * 18)) * 0.4 else 0.15 + math.abs(math.sin(t * 2)) * 0.1, 0, 0))
	set(rig, "Waist", CFrame.new(0, math.abs(math.sin(g * 2)) * 0.15 * stride, 0) * CFrame.Angles(rnd(0.03), math.sin(g) * 0.06 * stride, rnd(0.03)))
	set(rig, "Tail", CFrame.Angles(math.sin(t * 2.4) * 0.04, math.sin(g) * 0.06 * stride, 0))
	-- tetrapod gait: L1 R2 L3 R4 together, the others opposite
	for i = 1, 4 do
		for _, side in { -1, 1 } do
			local name = (if side < 0 then "L" else "R") .. i
			local phase = if (i % 2 == 1) == (side < 0) then 0 else math.pi
			local s = math.sin(g + phase)
			local lift = math.max(0, math.cos(g + phase))
			set(rig, name .. "Hip", CFrame.Angles(0, s * 0.45 * stride, 0) * CFrame.Angles(0, 0, -side * lift * 0.35 * stride + rnd(0.04)))
			set(rig, name .. "Knee", CFrame.Angles(0, 0, side * lift * 0.25 * stride))
		end
	end
	if math.sin(g) * rig.lastStepSign < 0 and speed > 2 then
		Audio.playAt("MonsterClicks", rig.root.Position, 0.6, 1.4 + math.random() * 0.3, 70)
	end
	rig.lastStepSign = if math.sin(g) >= 0 then 1 else -1
end

local function animateListener(rig: Rig, dt: number, speed: number, state: string)
	local t = os.clock()
	local hunting = state == "Chase" or state == "HuntLocker" or state == "Investigate"
	local kill = state == "Kill"
	local stride = math.clamp(speed / 12, 0, 1.2)
	local g = rig.gait
	local s1, s2 = math.sin(g), math.sin(g + math.pi)
	-- listening: the head sways slowly side to side, then freezes and points when it hears
	local listen = if hunting then CFrame.Angles(0.2, 0, 0) else CFrame.Angles(math.sin(t * 0.7) * 0.15, math.sin(t * 0.45) * 0.5, math.sin(t * 0.6) * 0.5)
	twitchHead(rig, "Neck", dt, if hunting then 0.4 else 2.2, 0.5, 0.3, 0.6, if hunting then 25 else 6, listen)
	set(rig, "NeckA", CFrame.Angles(math.sin(t * 0.5) * 0.08, math.sin(t * 0.4) * 0.15, 0))
	set(rig, "NeckB", CFrame.Angles(math.sin(t * 0.6 + 1) * 0.08, math.sin(t * 0.5 + 1) * 0.15, 0))
	local open = if kill then 0.9 elseif hunting then 0.35 + math.abs(math.sin(t * 9)) * 0.3 else 0.05 + math.abs(math.sin(t * 1.3)) * 0.05
	-- the two halves of its head swing apart
	set(rig, "JawL", CFrame.Angles(0, open, 0))
	set(rig, "JawR", CFrame.Angles(0, -open, 0))
	set(rig, "EarL", CFrame.Angles(0, 0, math.sin(t * 5) * 0.15 + (if math.random() < 0.03 then rnd(0.6) else 0)))
	set(rig, "EarR", CFrame.Angles(0, 0, math.sin(t * 5.3) * 0.15 + (if math.random() < 0.03 then rnd(0.6) else 0)))
	set(rig, "Spine", CFrame.Angles((if hunting then -0.2 else 0) + math.sin(t * 0.8) * 0.04, s1 * 0.06 * stride, 0))
	set(rig, "LHip", CFrame.Angles(s1 * 0.6 * stride, 0, 0))
	set(rig, "RHip", CFrame.Angles(s2 * 0.6 * stride, 0, 0))
	set(rig, "LKnee", CFrame.Angles(-math.max(0, math.cos(g)) * 0.8 * stride, 0, 0))
	set(rig, "RKnee", CFrame.Angles(-math.max(0, math.cos(g + math.pi)) * 0.8 * stride, 0, 0))
	local reach = if hunting or kill then 0.45 else 0
	set(rig, "LShoulder", CFrame.Angles(reach + math.sin(t * 1.1) * 0.08, 0, 0))
	set(rig, "RShoulder", CFrame.Angles(reach + math.sin(t * 1.2 + 2) * 0.08, 0, 0))
	for i = 1, 3 do
		local curl = (math.sin(t * 4 + i) + 1) * 0.2
		set(rig, "LFinger" .. i, CFrame.Angles(-curl, 0, 0))
		set(rig, "RFinger" .. i, CFrame.Angles(-curl, 0, 0))
	end
	footstep(rig, s1, speed, 0.7, 1)
end

local function animateStatue(rig: Rig)
	local pose = rig.model:GetAttribute("Pose")
	local index = if typeof(pose) == "number" then pose else 1
	if index ~= rig.pose then
		rig.pose = index
		local offsets = Monsters.STATUE_POSES[(index - 1) % #Monsters.STATUE_POSES + 1]
		for name, j in rig.joints do
			local offset = offsets[name]
			j.motor.C0 = if offset then j.base * offset else j.base
		end
	end
end

local function animateAmalgam(rig: Rig, dt: number, speed: number, state: string)
	local t = os.clock()
	local chase = state == "Chase" or state == "HuntLocker"
	local kill = state == "Kill"
	local stride = math.clamp(speed / 14, 0, 1.2)
	local g = rig.gait
	local s1, s2 = math.sin(g), math.sin(g + math.pi)
	twitchHead(rig, "Neck", dt, if chase then 0.3 else 1.2, 0.8, 0.5, 1.0, 22, nil)
	twitchHead(rig, "NeckL", dt, 0.5, 1.2, 0.8, 1.4, 30, nil)
	twitchHead(rig, "NeckR", dt, 0.45, 1.2, 0.8, 1.4, 30, nil)
	local jaw = if kill then 1.1 elseif chase then 0.6 + math.abs(math.sin(t * 12)) * 0.3 else 0.2 + math.abs(math.sin(t * 1.4)) * 0.15
	set(rig, "Jaw", CFrame.Angles(-jaw, 0, 0))
	set(rig, "JawL2", CFrame.Angles(-(0.3 + math.abs(math.sin(t * 3.1)) * 0.5), 0, 0))
	set(rig, "JawR2", CFrame.Angles(-(0.3 + math.abs(math.sin(t * 2.7 + 1)) * 0.5), 0, 0))
	set(rig, "Spine", CFrame.Angles((if chase then -0.2 else 0) + math.sin(t * 1.1) * 0.05, s1 * 0.05 * stride, math.sin(t * 0.7) * 0.04))
	set(rig, "Waist", CFrame.new(0, math.abs(math.cos(g)) * 0.3 * stride, 0))
	for _, suffix in { "", "2" } do
		local a, b = if suffix == "" then s1 else s2, if suffix == "" then s2 else s1
		set(rig, "LHip" .. suffix, CFrame.Angles(a * 0.6 * stride, 0, 0))
		set(rig, "RHip" .. suffix, CFrame.Angles(b * 0.6 * stride, 0, 0))
		set(rig, "LKnee" .. suffix, CFrame.Angles(-math.max(0, a) * 0.8 * stride, 0, 0))
		set(rig, "RKnee" .. suffix, CFrame.Angles(-math.max(0, b) * 0.8 * stride, 0, 0))
	end
	local reach = if chase or kill then 1.2 else 0
	set(rig, "LShoulder", CFrame.Angles(reach + s2 * 0.35 * stride + math.sin(t * 1.4) * 0.07, 0, -0.1 * reach))
	set(rig, "RShoulder", CFrame.Angles(reach + s1 * 0.35 * stride + math.sin(t * 1.2 + 1) * 0.07, 0, 0.1 * reach))
	for i = 1, 4 do
		local curl = (math.sin(t * 6 + i * 1.3) + 1) * 0.15 + (if chase or kill then 0.45 else 0)
		set(rig, "LFinger" .. i, CFrame.Angles(-curl, 0, 0))
		set(rig, "RFinger" .. i, CFrame.Angles(-curl, 0, 0))
		-- back arms never stop moving
		local speedUp = if chase then 2.2 else 1
		set(rig, "BackArm" .. i, CFrame.Angles(math.sin(t * 1.7 * speedUp + i) * 0.35, math.sin(t * 1.3 * speedUp + i * 2) * 0.3, 0))
		set(rig, "BackElbow" .. i, CFrame.Angles(0, 0, math.sin(t * 2.3 * speedUp + i * 1.7) * 0.4))
	end
	if rig.eyeGlow then
		rig.eyeGlow.Brightness = 1.2 + math.abs(math.sin(t * (if chase then 6 else 2))) * 1.6
	end
	footstep(rig, s1, speed, 1.4, 0.6)
end

local function animate(rig: Rig, dt: number)
	local root = rig.root
	if root.Position.Y < -100 then
		return -- parked out of sight
	end
	local stateAttr = rig.model:GetAttribute("State")
	local state = if typeof(stateAttr) == "string" then stateAttr else "Wander"
	local vel = root.AssemblyLinearVelocity
	local speed = if root.Anchored then 0 else Vector3.new(vel.X, 0, vel.Z).Magnitude
	rig.gait += dt * speed * 0.42

	if rig.kind == "Statue" then
		animateStatue(rig)
		return
	elseif rig.kind == "Crawler" then
		animateCrawler(rig, dt, speed, state)
	elseif rig.kind == "Listener" then
		animateListener(rig, dt, speed, state)
	elseif rig.kind == "Amalgam" then
		animateAmalgam(rig, dt, speed, state)
	else
		animateHollow(rig, dt, speed, state)
	end

	-- clicking while it hunts
	local t = os.clock()
	if t >= rig.nextClick then
		rig.nextClick = t + 4 + math.random() * 7
		if (rig.kind == "Hollow" or rig.kind == "Listener") and (state == "Wander" or state == "Search" or state == "Investigate" or state == "Apparition") then
			local head = rig.model:FindFirstChild("Head")
			if head then
				Audio.play("MonsterClicks", head, 1.1, 0.9 + math.random() * 0.2, 80)
			end
		end
	end
	if rig.eyeGlow and rig.kind ~= "Amalgam" then
		local chase = state == "Chase" or state == "Kill"
		rig.eyeGlow.Brightness = (if chase then 2 else 1.2) * (if math.random() < 0.03 then 0.2 else 1)
	end
end

function MonsterAnimator.init()
	RunService.RenderStepped:Connect(function(dt: number)
		local model = workspace:FindFirstChild("Monster")
		if not model or not model:IsA("Model") then
			current = nil
			return
		end
		if not current or current.model ~= model then
			current = collect(model)
		end
		if current then
			animate(current, dt)
		end
	end)
end

return MonsterAnimator
