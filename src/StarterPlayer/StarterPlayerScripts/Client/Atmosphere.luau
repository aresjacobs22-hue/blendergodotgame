--!strict
-- The dread: fear level, heartbeat, camera shake, blur, ambient drone, random
-- sounds behind you, lamps that flicker (and die when *it* walks under them).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Audio = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Audio"))
local ClientState = require(script.Parent.ClientState)
local Hud = require(script.Parent.Hud)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local GameState = ReplicatedStorage:WaitForChild("GameState")
local player = Players.LocalPlayer

local Atmosphere = {}

type Lamp = {
	part: BasePart,
	light: PointLight?,
	base: number,
	baseColor: Color3,
	dropUntil: number,
	nextDrop: number,
	buzz: Sound?,
}

local STINGERS: { { any } } = {
	-- name, weight, min distance, max distance, volume
	{ "StingerCreak", 3, 14, 30, 0.9 },
	{ "StingerBang", 2, 25, 45, 1.0 },
	{ "StingerWhisper", 2, 4, 8, 0.45 },
	{ "StingerScrape", 2, 16, 34, 0.8 },
	{ "StingerDistantScream", 1, 40, 60, 0.8 },
	{ "StingerKnock", 2, 10, 24, 0.9 },
	{ "StingerFootsteps", 2, 10, 20, 0.8 },
	{ "MonsterClicks", 1, 14, 26, 0.7 },
}

local lamps: { [BasePart]: Lamp } = {}
local blur: BlurEffect
local grade: ColorCorrectionEffect
local ambience: Sound? = nil
local heartbeatAt = 0
local nextStinger = 0
local shakeImpulse = 0
local wasChased = false
local wake = 0

local function addLamp(inst: Instance)
	if not inst:IsA("BasePart") or lamps[inst] then
		return
	end
	local light = inst:FindFirstChildOfClass("PointLight")
	local base = inst:GetAttribute("BaseBrightness")
	local lamp: Lamp = {
		part = inst,
		light = light,
		base = if typeof(base) == "number" then base elseif light then light.Brightness else 1,
		baseColor = inst.Color,
		dropUntil = 0,
		nextDrop = os.clock() + math.random() * 10,
		buzz = nil,
	}
	if inst:GetAttribute("Buzz") == true then
		local buzz = Audio.create("LightBuzzLoop", inst, 0.22)
		if buzz then
			buzz.RollOffMinDistance = 4
			buzz.RollOffMaxDistance = 28
			buzz:Play()
			lamp.buzz = buzz
		end
	end
	lamps[inst] = lamp
end

local function updateLamps(monsterPos: Vector3?)
	local now = os.clock()
	for part, lamp in lamps do
		if not part.Parent then
			lamps[part] = nil
			continue
		end
		local light = lamp.light
		if not light then
			continue
		end
		local b = lamp.base
		if now >= lamp.nextDrop then
			lamp.dropUntil = now + 0.03 + math.random() * 0.25
			lamp.nextDrop = now + 2 + math.random() * 12
		end
		if now < lamp.dropUntil then
			b *= 0.12
		end
		if monsterPos then
			local near = (part.Position - monsterPos).Magnitude
			if near < 14 then
				b = if math.random() < 0.9 then 0 else b
			elseif near < 40 then
				local k = 1 - near / 40
				if math.random() < k * 0.6 then
					b *= math.random() * (1 - k)
				end
			end
		end
		light.Brightness = b
		local dark = b < lamp.base * 0.3
		part.Color = if dark then Color3.fromRGB(55, 55, 52) else lamp.baseColor
		if lamp.buzz then
			lamp.buzz.Volume = if dark then 0 else 0.22
		end
	end
end

local function playStinger(origin: BasePart)
	local total = 0
	for _, s in STINGERS do
		total += s[2] :: number
	end
	local pick = math.random() * total
	local chosen = STINGERS[1]
	for _, s in STINGERS do
		pick -= s[2] :: number
		if pick <= 0 then
			chosen = s
			break
		end
	end
	-- usually behind you
	local back = -origin.CFrame.LookVector
	local angle = math.rad(math.random(-75, 75))
	local dir = (CFrame.Angles(0, angle, 0) * Vector3.new(back.X, 0, back.Z)).Unit
	local dist = (chosen[3] :: number) + math.random() * ((chosen[4] :: number) - (chosen[3] :: number))
	local pos = origin.Position + dir * dist + Vector3.new(0, math.random(1, 5), 0)
	Audio.playAt(chosen[1] :: string, pos, chosen[5] :: number, 0.9 + math.random() * 0.2, 140)
end

local function shake()
	if ClientState.jumpscaring then
		return
	end
	local camera = workspace.CurrentCamera
	if not camera or camera.CameraType == Enum.CameraType.Scriptable then
		return
	end
	local amount = ClientState.fear ^ 2 * 0.004 + shakeImpulse * 0.02 + (if ClientState.chased then 0.004 else 0)
	if amount > 0.0002 then
		local t = os.clock()
		camera.CFrame *= CFrame.Angles(
			math.noise(t * 9, 0.3) * amount * 2,
			math.noise(t * 9, 4.1) * amount * 2,
			math.noise(t * 7, 8.7) * amount * 3
		)
	end
end

local function update(dt: number)
	local t = os.clock()
	local character = player.Character
	local myRoot = if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	local monster = workspace:FindFirstChild("Monster")
	local monsterRoot = if monster then monster:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	local playing = ClientState.roundStatus == "alive" and myRoot ~= nil

	local raw = 0
	local dist = math.huge
	local chased = false
	local monsterPos: Vector3? = nil
	if monster and monsterRoot and monsterRoot.Position.Y > -100 then
		monsterPos = monsterRoot.Position
		local state = monster:GetAttribute("State")
		if myRoot and playing then
			dist = (monsterRoot.Position - myRoot.Position).Magnitude
			if state ~= "Dormant" then
				raw = math.clamp(1 - (dist - 10) / 75, 0, 1)
			end
			chased = (state == "Chase" or state == "HuntLocker" or state == "Kill") and monster:GetAttribute("TargetUserId") == player.UserId
			if chased then
				raw = math.max(raw, 0.8)
			end
		end
	end

	local fear = ClientState.fear
	fear += (raw - fear) * math.min(1, dt * (if raw > fear then 2.5 else 0.45))
	ClientState.fear = fear
	ClientState.monsterDistance = dist
	ClientState.chased = chased
	ClientState.interference = math.clamp(1 - (dist - 8) / 34, 0, 1)
	Hud.setFear(fear)

	if chased and not wasChased then
		shakeImpulse = 1
		Hud.glitch(0.9, 0.5)
		Hud.flash(0.2, 0.3)
	end
	wasChased = chased
	shakeImpulse = math.max(0, shakeImpulse - dt * 1.5)

	wake = math.max(0, wake - dt * 0.35)
	blur.Size = fear ^ 2 * 4 + (if chased then (math.sin(t * 9) + 1) * 1.5 else 0) + wake * 18
	grade.Contrast = fear * 0.25
	grade.Brightness = -fear * 0.06 + (if math.random() < 0.02 then -0.03 else 0) - wake * 0.1

	if playing and fear > 0.15 and t >= heartbeatAt then
		heartbeatAt = t + (1.15 - fear * 0.8)
		Audio.play("Heartbeat", nil, 0.25 + fear * 1.1)
		Hud.pulse(fear)
	end

	if ambience then
		local target = if playing then 0.75 else 0
		ambience.Volume += (target - ambience.Volume) * math.min(1, dt * 0.8)
	end

	if playing and myRoot and t >= nextStinger then
		nextStinger = t + 16 + math.random() * 26
		playStinger(myRoot)
	end

	updateLamps(monsterPos)
end

function Atmosphere.wakeUp()
	wake = 1
	nextStinger = os.clock() + 20
end

function Atmosphere.init()
	local camera = workspace.CurrentCamera
	blur = Instance.new("BlurEffect")
	blur.Size = 0
	blur.Parent = camera
	grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "Fear"
	grade.Parent = camera

	ambience = Audio.track("Ambience", nil, 0)
	if ambience then
		ambience:Play()
	end

	for _, inst in CollectionService:GetTagged("FlickerLight") do
		addLamp(inst)
	end
	CollectionService:GetInstanceAddedSignal("FlickerLight"):Connect(addLamp)

	Remotes.Apparition.OnClientEvent:Connect(function(position: Vector3)
		local character = player.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
		if not root or (root.Position - position).Magnitude > 140 then
			return
		end
		Audio.playAt("StaticBurst", position, 1.3, 1, 140)
		Hud.glitch(0.8, 0.35)
		local now = os.clock()
		for part, lamp in lamps do
			if part.Parent and (part.Position - position).Magnitude < 45 then
				lamp.dropUntil = now + 0.6 + math.random() * 0.4
			end
		end
	end)

	GameState:GetAttributeChangedSignal("MonsterAwake"):Connect(function()
		if GameState:GetAttribute("MonsterAwake") == true and ClientState.roundStatus == "alive" then
			Audio.play("StingerDistantScream", nil, 1.1, 0.8)
			Hud.message("Somewhere in the halls, something wakes up.", "danger")
			shakeImpulse = 0.7
		end
	end)

	RunService.RenderStepped:Connect(update)
	RunService:BindToRenderStep("AchromaShake", Enum.RenderPriority.Camera.Value + 2, shake)

	-- keep effects attached if the camera object is ever replaced
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		local cam = workspace.CurrentCamera
		if cam then
			blur.Parent = cam
			grade.Parent = cam
		end
	end)
end

return Atmosphere
