--!strict
-- The dread: fear level, heartbeat, camera shake, blur, the ambient drone, random
-- sounds behind you, lamps that flicker (and die when *it* walks under them), and
-- each map's own touches: spinning alarm lights, dripping water, floating rocks,
-- eyes in the walls, beating hearts, the hour bell.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Audio = require(Shared:WaitForChild("Audio"))
local Nights = require(Shared:WaitForChild("Nights"))
local ClientState = require(script.Parent.ClientState)
local Hud = require(script.Parent.Hud)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local GameState = ReplicatedStorage:WaitForChild("GameState")
local player = Players.LocalPlayer

local Atmosphere = {}

type Lamp = {
	part: BasePart,
	light: Light?,
	base: number,
	litColor: Color3,
	dropUntil: number,
	nextDrop: number,
	buzz: Sound?,
	pulse: boolean,
}

type Floater = { part: BasePart, base: CFrame, phase: number, spin: number }

-- name, weight, min distance, max distance, volume
local STINGERS: { { any } } = {
	{ "StingerCreak", 3, 14, 30, 0.9 },
	{ "StingerBang", 2, 25, 45, 1.0 },
	{ "StingerWhisper", 2, 4, 8, 0.45 },
	{ "StingerScrape", 2, 16, 34, 0.8 },
	{ "StingerDistantScream", 1, 40, 60, 0.8 },
	{ "StingerKnock", 2, 10, 24, 0.9 },
	{ "StingerFootsteps", 2, 10, 20, 0.8 },
	{ "MonsterClicks", 1, 14, 26, 0.7 },
}

local NIGHT_STINGERS: { [string]: { { any } } } = {
	ward = { { "AlarmBeep", 4, 20, 40, 0.8 }, { "StingerFootsteps", 2, 8, 16, 0.8 } },
	sewer = { { "Drip", 4, 4, 12, 0.8 }, { "StingerScrape", 3, 14, 30, 0.9 } },
	atrium = { { "StatueGrind", 2, 30, 60, 0.7 }, { "StingerWhisper", 2, 4, 8, 0.4 } },
	void = { { "StingerWhisper", 4, 3, 8, 0.6 }, { "HeartPulseLoop", 2, 20, 40, 0.6 }, { "AmalgamRoar", 1, 60, 90, 0.5 } },
}

local lamps: { [BasePart]: Lamp } = {}
local beacons: { [BasePart]: boolean } = {}
local floaters: { [BasePart]: Floater } = {}
local wallEyes: { [BasePart]: number } = {}
local hearts: { [BasePart]: Vector3 } = {}
local drips: { [BasePart]: boolean } = {}
local blur: BlurEffect
local grade: ColorCorrectionEffect
local ambience: Sound? = nil
local heartbeatAt = 0
local nextStinger = 0
local nextDrip = 0
local nextLook = 0
local shakeImpulse = 0
local wasChased = false
local wake = 0

local function currentNight(): Nights.Night
	local n = GameState:GetAttribute("Night")
	return Nights.get(if typeof(n) == "number" then n else 1)
end

local function addLamp(inst: Instance)
	if not inst:IsA("BasePart") or lamps[inst] then
		return
	end
	local light = inst:FindFirstChildWhichIsA("Light")
	local base = inst:GetAttribute("BaseBrightness")
	local onColor = inst:GetAttribute("OnColor")
	local lamp: Lamp = {
		part = inst,
		light = light,
		base = if typeof(base) == "number" then base elseif light then light.Brightness else 1,
		litColor = if typeof(onColor) == "Color3" then onColor else inst.Color,
		dropUntil = 0,
		nextDrop = os.clock() + math.random() * 10,
		buzz = nil,
		pulse = inst:GetAttribute("Pulse") == true,
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
	local beat = math.abs(math.sin(now * 2.2)) ^ 6 -- void lamps pulse like a heartbeat
	for part, lamp in lamps do
		if not part.Parent then
			lamps[part] = nil
			continue
		end
		local light = lamp.light
		if not light then
			continue
		end
		if not light.Enabled then
			-- no power
			if lamp.buzz then
				lamp.buzz.Volume = 0
			end
			continue
		end
		local b = lamp.base
		if lamp.pulse then
			b *= 0.55 + beat * 0.9
		end
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
		if GameState:GetAttribute("Blink") == true then
			b = 0
		end
		light.Brightness = b
		local dark = b < lamp.base * 0.3
		part.Color = if dark then lamp.litColor:Lerp(Color3.new(0, 0, 0), 0.75) else lamp.litColor
		if lamp.buzz then
			lamp.buzz.Volume = if dark then 0 else 0.22
		end
	end
end

local function updateProps(dt: number, myRoot: BasePart?)
	local t = os.clock()
	for part in beacons do
		if part.Parent then
			part.CFrame *= CFrame.Angles(0, dt * 4.5, 0)
		else
			beacons[part] = nil
		end
	end
	for part, f in floaters do
		if part.Parent then
			part.CFrame = f.base * CFrame.new(0, math.sin(t * 0.6 + f.phase) * 1.2, 0) * CFrame.Angles(0, t * f.spin, 0)
		else
			floaters[part] = nil
		end
	end
	for part, openAt in wallEyes do
		if not part.Parent then
			wallEyes[part] = nil
		elseif t >= openAt then
			part.Transparency = 0
			if math.random() < dt * 0.4 then
				part.Transparency = 1 -- blink
				wallEyes[part] = t + 0.15
			end
		end
	end
	local beat = math.abs(math.sin(t * 2.2)) ^ 6
	for part, size in hearts do
		if part.Parent then
			part.Size = size * (1 + beat * 0.12)
		else
			hearts[part] = nil
		end
	end
	if myRoot and t >= nextDrip then
		nextDrip = t + 0.8 + math.random() * 2.5
		for part in drips do
			if not part.Parent then
				drips[part] = nil
			elseif (part.Position - myRoot.Position).Magnitude < 40 and math.random() < 0.3 then
				Audio.playAt("Drip", part.Position, 0.6, 0.8 + math.random() * 0.5, 50)
				break
			end
		end
	end
end

local function playStinger(origin: BasePart)
	local list = table.clone(STINGERS)
	local extras = NIGHT_STINGERS[currentNight().id]
	if extras then
		for _, extra in extras do
			table.insert(list, extra)
		end
	end
	local total = 0
	for _, s in list do
		total += s[2] :: number
	end
	local pick = math.random() * total
	local chosen = list[1]
	for _, s in list do
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
		camera.CFrame *= CFrame.Angles(math.noise(t * 9, 0.3) * amount * 2, math.noise(t * 9, 4.1) * amount * 2, math.noise(t * 7, 8.7) * amount * 3)
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
			chased = (state == "Chase" or state == "HuntLocker" or state == "Kill" or state == "Stalk") and monster:GetAttribute("TargetUserId") == player.UserId
			if chased and state ~= "Stalk" then
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
	grade.Brightness = ClientState.brightness - fear * 0.06 + (if math.random() < 0.02 then -0.03 else 0) - wake * 0.1

	if playing and fear > 0.15 and t >= heartbeatAt then
		heartbeatAt = t + (1.15 - fear * 0.8)
		Audio.play("Heartbeat", nil, 0.25 + fear * 1.1)
		Hud.pulse(fear)
	end

	if ambience then
		local target = if playing then 0.75 else 0
		ambience.Volume += (target - ambience.Volume) * math.min(1, dt * 0.8)
		ambience.PlaybackSpeed = currentNight().ambiencePitch
	end

	if playing and myRoot and t >= nextStinger then
		nextStinger = t + 16 + math.random() * 26
		playStinger(myRoot)
	end

	-- tell the server where we're looking (the Statue can't move while watched)
	if playing and t >= nextLook then
		nextLook = t + 0.1
		local camera = workspace.CurrentCamera
		if camera then
			Remotes.Look:FireServer(camera.CFrame.LookVector)
		end
	end

	updateLamps(monsterPos)
	updateProps(dt, if playing then myRoot else nil)
end

function Atmosphere.wakeUp()
	wake = 1
	nextStinger = os.clock() + 20
end

local function watchTag(tag: string, add: (BasePart) -> ())
	for _, inst in CollectionService:GetTagged(tag) do
		if inst:IsA("BasePart") then
			add(inst)
		end
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst: Instance)
		if inst:IsA("BasePart") then
			add(inst)
		end
	end)
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

	watchTag("FlickerLight", addLamp)
	watchTag("Beacon", function(p: BasePart)
		beacons[p] = true
	end)
	watchTag("Float", function(p: BasePart)
		floaters[p] = { part = p, base = p.CFrame, phase = math.random() * 6, spin = (math.random() - 0.5) * 0.4 }
	end)
	watchTag("WallEye", function(p: BasePart)
		wallEyes[p] = 0
	end)
	watchTag("Heart", function(p: BasePart)
		hearts[p] = p.Size
	end)
	watchTag("Drip", function(p: BasePart)
		drips[p] = true
	end)

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
			local night = currentNight()
			if night.monsterKind ~= "Statue" then
				Audio.play("StingerDistantScream", nil, 1.1, 0.8)
			end
			Hud.message(if night.monsterKind == "Statue" then "One of the statues has moved." else "Somewhere out there, something wakes up.", "danger")
			shakeImpulse = 0.7
		end
	end)

	GameState:GetAttributeChangedSignal("Hour"):Connect(function()
		local hour = GameState:GetAttribute("Hour")
		if typeof(hour) == "number" and hour > 0 and ClientState.roundStatus == "alive" then
			Audio.play("ClockChime", nil, if hour >= 6 then 1.4 else 0.9, if hour == 3 then 0.8 else 1)
		end
	end)

	GameState:GetAttributeChangedSignal("Blink"):Connect(function()
		if GameState:GetAttribute("Blink") == true and ClientState.roundStatus == "alive" then
			Audio.play("Blink", nil, 0.8)
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
