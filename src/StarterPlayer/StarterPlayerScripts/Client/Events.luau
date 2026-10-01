--!strict
-- The chaos, from your side of the screen:
--   phone       you picked up; a voice, and then you hear IT from where it is (usually)
--   falseChase  the chase music kicks in and something screams behind you... nothing
--   hunted      (curse) your heartbeat gave you away
--   phantoms    (curse) you see it standing down the corridor. It isn't there.
-- Also throwing bottles: G (or the THROW button) when you're carrying any.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Audio = require(Shared:WaitForChild("Audio"))
local Monsters = require(Shared:WaitForChild("Monsters"))
local Nights = require(Shared:WaitForChild("Nights"))
local Atmosphere = require(script.Parent.Atmosphere)
local ClientState = require(script.Parent.ClientState)
local Hud = require(script.Parent.Hud)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local GameState = ReplicatedStorage:WaitForChild("GameState")
local player = Players.LocalPlayer

local Events = {}

local phantom: Model? = nil
local phantomUntil = 0
local nextPhantom = 0
local throwBound = false

local function currentNight(): Nights.Night
	local n = GameState:GetAttribute("Night")
	return Nights.get(if typeof(n) == "number" then n else 1)
end

local function myRoot(): BasePart?
	local character = player.Character
	return if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

local function onEvent(kind: string, data: unknown)
	if ClientState.roundStatus ~= "alive" then
		return
	end
	if kind == "phone" then
		Audio.play("PhoneVoice", nil, 1.2)
		Hud.glitch(0.4, 0.3)
		-- then a whisper from wherever it is (or wherever the voice wants you to think it is)
		if typeof(data) == "Vector3" then
			task.delay(2.2, function()
				if ClientState.roundStatus == "alive" then
					Audio.playAt("StingerWhisper", data, 2.4, 0.85, 400)
				end
			end)
		end
	elseif kind == "falseChase" then
		Atmosphere.fakeChase(4.5)
		local root = myRoot()
		if root then
			local scream = Monsters.SCREAMS[currentNight().monsterKind] or "MonsterScream"
			Audio.playAt(scream, root.Position - root.CFrame.LookVector * 14 + Vector3.new(0, 3, 0), 1.6, 1, 120)
		end
	elseif kind == "hunted" then
		for i = 0, 2 do
			task.delay(i * 0.55, function()
				Audio.play("Heartbeat", nil, 2.2)
				Hud.pulse(1)
			end)
		end
		Hud.glitch(0.6, 0.4)
	end
end

-- PHANTOMS: a copy of the monster that only you can see, down the corridor in front of you.
local function updatePhantom()
	local now = os.clock()
	local root = myRoot()
	local playing = ClientState.roundStatus == "alive" and root ~= nil and not ClientState.hiding
	local p = phantom
	if p then
		local proot = p.PrimaryPart
		local close = root and proot and (proot.Position - root.Position).Magnitude < 18
		if not playing or now > phantomUntil or close then
			if playing then
				Audio.play("StaticBurst", nil, 0.7)
				Hud.glitch(0.8, 0.3)
			end
			p:Destroy()
			phantom = nil
		end
		return
	end
	if not playing or GameState:GetAttribute("Curse") ~= "phantoms" or now < nextPhantom or not root then
		return
	end
	nextPhantom = now + 18 + math.random() * 20
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local look = Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z)
	if look.Magnitude < 0.1 then
		return
	end
	look = look.Unit
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character :: Instance }
	local origin = root.Position + Vector3.new(0, 1, 0)
	local hit = workspace:Raycast(origin, look * 80, params)
	local dist = if hit then (hit.Position - origin).Magnitude else 80
	if dist < 26 then
		return
	end
	local night = currentNight()
	local variant = if night.monsterKind == "Statue" then Monsters.STATUE_VARIANTS[math.random(1, #Monsters.STATUE_VARIANTS)] else nil
	local rig = Monsters.build(night.monsterKind, { preview = true, variant = variant })
	if night.monsterKind == "Statue" then
		Monsters.applyStatuePose(rig, math.random(1, #Monsters.STATUE_POSES), nil)
	end
	local at = origin + look * (dist * 0.75)
	local pos = Vector3.new(at.X, rig.rootHeight, at.Z)
	rig.model:PivotTo(CFrame.lookAt(pos, Vector3.new(root.Position.X, pos.Y, root.Position.Z)))
	Monsters.solve(rig)
	rig.model.Name = "Phantom"
	rig.model.Parent = workspace
	phantom = rig.model
	phantomUntil = now + 2.5 + math.random() * 3
end

local function setBottles()
	local value = player:GetAttribute("Bottles")
	local n = if typeof(value) == "number" then value else 0
	Hud.setBottles(n)
	if n > 0 and not throwBound then
		throwBound = true
		ContextActionService:BindAction("AchromaThrow", function(_: string, state: Enum.UserInputState, _: InputObject): Enum.ContextActionResult?
			if state == Enum.UserInputState.Begin and ClientState.roundStatus == "alive" and not ClientState.hiding then
				local camera = workspace.CurrentCamera
				if camera then
					Remotes.Throw:FireServer(camera.CFrame.LookVector)
				end
			end
			return Enum.ContextActionResult.Sink
		end, true, Enum.KeyCode.G, Enum.KeyCode.DPadUp)
		ContextActionService:SetTitle("AchromaThrow", "THROW")
	elseif n <= 0 and throwBound then
		throwBound = false
		ContextActionService:UnbindAction("AchromaThrow")
	end
end

function Events.init()
	Remotes.Chaos.OnClientEvent:Connect(onEvent)
	player:GetAttributeChangedSignal("Bottles"):Connect(setBottles)
	setBottles()
	RunService.RenderStepped:Connect(updatePhantom)
end

return Events
