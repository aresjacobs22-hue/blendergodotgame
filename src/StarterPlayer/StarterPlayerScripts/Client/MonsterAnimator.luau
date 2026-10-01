--!strict
-- Procedural animation for the monster, run locally on every client: a lurching
-- gait, arms dragging (or reaching for you when it chases), a head that snaps to
-- new angles, a jaw that hangs open, fingers that never stop moving. Also plays its
-- footsteps and clicking.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Audio = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Audio"))

local MonsterAnimator = {}

type Joint = { motor: Motor6D, base: CFrame }
type Rig = {
	model: Model,
	root: BasePart,
	joints: { [string]: Joint },
	gait: number,
	twitchAt: number,
	headTarget: CFrame,
	headCurrent: CFrame,
	nextClick: number,
	lastStepSign: number,
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
	return {
		model = model,
		root = root,
		joints = joints,
		gait = 0,
		twitchAt = 0,
		headTarget = CFrame.new(),
		headCurrent = CFrame.new(),
		nextClick = os.clock() + 3,
		lastStepSign = 1,
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

local function animate(rig: Rig, dt: number)
	local t = os.clock()
	local root = rig.root
	if root.Position.Y < -100 then
		return -- parked out of sight
	end
	local state = rig.model:GetAttribute("State")
	local vel = root.AssemblyLinearVelocity
	local speed = if root.Anchored then 0 else Vector3.new(vel.X, 0, vel.Z).Magnitude
	local chase = state == "Chase" or state == "HuntLocker"
	local kill = state == "Kill"
	local staring = state == "Apparition"

	rig.gait += dt * speed * 0.42
	local stride = math.clamp(speed / 14, 0, 1.2)
	local g = rig.gait
	local s1, s2 = math.sin(g), math.sin(g + math.pi)

	-- head: holds still, then SNAPS to a new angle
	if t >= rig.twitchAt then
		rig.twitchAt = t + (if chase then 0.08 + math.random() * 0.35 elseif staring then 1.5 + math.random() * 2 else 0.25 + math.random() * 1.6)
		rig.headTarget = CFrame.Angles(rnd(0.7), rnd(1.0), rnd(if staring then 0.4 else 1.4))
	end
	local target = rig.headTarget
	if staring then
		target = CFrame.Angles(0.15, 0, 1.1) * rig.headTarget:Lerp(CFrame.new(), 0.7) -- head tilted right over, staring
	end
	rig.headCurrent = rig.headCurrent:Lerp(target, math.min(1, dt * (if chase then 32 else 18)))
	local jitterScale = if chase or kill then 0.09 else 0.035
	set(rig, "Neck", rig.headCurrent * CFrame.Angles(rnd(jitterScale), rnd(jitterScale), rnd(jitterScale)))

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

	-- arms drag and sway; when it chases they reach out in front of it
	local reach = if chase or kill then 1.3 else 0
	local twitchL = if math.random() < 0.02 then rnd(0.6) else 0
	local twitchR = if math.random() < 0.02 then rnd(0.6) else 0
	set(rig, "LShoulder", CFrame.Angles(reach + s2 * 0.4 * stride + math.sin(t * 1.3) * 0.06 + twitchL, 0, -0.12 * reach))
	set(rig, "RShoulder", CFrame.Angles(reach + s1 * 0.4 * stride + math.sin(t * 1.1 + 1) * 0.06 + twitchR, 0, 0.12 * reach))
	set(rig, "LElbow", CFrame.Angles(-0.15 - reach * 0.25 + math.sin(t * 2.1) * 0.05, 0, 0))
	set(rig, "RElbow", CFrame.Angles(-0.15 - reach * 0.25 + math.sin(t * 2.3 + 2) * 0.05, 0, 0))
	for i = 1, 4 do
		local curl = (math.sin(t * 6 + i * 1.3) + 1) * 0.15 + (if chase or kill then 0.45 else 0) + rnd(0.05)
		set(rig, "LFinger" .. i, CFrame.Angles(-curl, 0, 0))
		set(rig, "RFinger" .. i, CFrame.Angles(-curl, 0, 0))
	end

	-- footsteps on every foot-fall
	local sign = if s1 >= 0 then 1 else -1
	if sign ~= rig.lastStepSign and speed > 2 then
		Audio.playAt("MonsterStep", root.Position - Vector3.new(0, 4.6, 0), math.clamp(speed / 11, 0.45, 1.5), 0.85 + math.random() * 0.25, 110)
	end
	rig.lastStepSign = sign

	-- clicking while it hunts
	if t >= rig.nextClick then
		rig.nextClick = t + 4 + math.random() * 7
		if state == "Wander" or state == "Search" or state == "Investigate" or staring then
			local head = rig.model:FindFirstChild("Head")
			if head then
				Audio.play("MonsterClicks", head, 1.1, 0.9 + math.random() * 0.2, 80)
			end
		end
	end

	if rig.eyeGlow then
		rig.eyeGlow.Brightness = (if chase or kill then 2 else 1.2) * (if math.random() < 0.03 then 0.2 else 1)
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
