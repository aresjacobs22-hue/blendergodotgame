--!strict
-- Sprinting (with stamina), crouch-walking, head bob, breathing, field of view.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Audio = require(Shared:WaitForChild("Audio"))
local Config = require(Shared:WaitForChild("Config"))
local ClientState = require(script.Parent.ClientState)
local Hud = require(script.Parent.Hud)

local P = Config.Player
local player = Players.LocalPlayer

local Movement = {}

local humanoid: Humanoid? = nil
local stamina = P.StaminaMax
local sprintHeld = false
local exhausted = false
local lastSprint = 0
local bobTime = 0
local crouchOffset = 0
local breath: Sound? = nil

local function onCharacter(character: Model)
	humanoid = character:WaitForChild("Humanoid") :: Humanoid
	stamina = P.StaminaMax
	exhausted = false
	crouchOffset = 0
	ClientState.crouching = false
	if humanoid then
		humanoid.WalkSpeed = P.WalkSpeed
	end
end

local function update(dt: number)
	local h = humanoid
	if not h or not h.Parent or h.Health <= 0 then
		return
	end
	local now = os.clock()
	local camera = workspace.CurrentCamera

	local frozen = ClientState.hiding or ClientState.jumpscaring
	local moving = not frozen and h.MoveDirection.Magnitude > 0.1
	local wantsSprint = sprintHeld and moving and not ClientState.crouching and not exhausted

	if wantsSprint then
		stamina = math.max(0, stamina - P.StaminaDrain * dt)
		lastSprint = now
		if stamina <= 0 then
			exhausted = true
			Audio.play("Gasp", nil, 0.7, 1.15)
		end
	elseif now - lastSprint > P.StaminaRegenDelay then
		stamina = math.min(P.StaminaMax, stamina + P.StaminaRegen * dt)
	end
	if exhausted and stamina > P.StaminaMax * 0.35 then
		exhausted = false
	end
	ClientState.sprinting = wantsSprint
	Hud.setStamina(stamina / P.StaminaMax)

	local speed = P.WalkSpeed
	if ClientState.crouching then
		speed = P.CrouchSpeed
	elseif wantsSprint then
		speed = P.SprintSpeed
	elseif exhausted then
		speed = P.WalkSpeed * 0.75
	end
	h.WalkSpeed = speed

	-- crouch + head bob through the camera offset
	local crouchTarget = if ClientState.crouching and not frozen then -1.9 else 0
	crouchOffset += (crouchTarget - crouchOffset) * math.min(1, dt * 10)
	local bobX, bobY = 0, 0
	if moving then
		bobTime += dt * speed * 0.75
		local amp = if wantsSprint then 0.16 elseif ClientState.crouching then 0.05 else 0.09
		bobX = math.sin(bobTime) * amp
		bobY = math.abs(math.cos(bobTime)) * amp * 1.4
	end
	h.CameraOffset = Vector3.new(bobX, crouchOffset + bobY, 0)

	if camera and not ClientState.jumpscaring then
		-- the lens never quite settles: it breathes, and faster when it's close
		local t = os.clock()
		local breathe = math.sin(t * (0.35 + ClientState.fear * 0.8)) * (1.4 + ClientState.fear * 2)
		local targetFov = P.FieldOfView + (if wantsSprint then 7 else 0) + ClientState.fear * 6 + breathe
		camera.FieldOfView += (targetFov - camera.FieldOfView) * math.min(1, dt * 5)
	end

	-- heavy breathing when winded or terrified
	if breath then
		local need = math.max(0.65 - stamina / P.StaminaMax, ClientState.fear - 0.45, 0)
		local targetVolume = if ClientState.holdingBreath then 0 elseif frozen and ClientState.hiding then need * 0.6 else need * 1.6
		breath.Volume += (targetVolume - breath.Volume) * math.min(1, dt * 2)
		breath.PlaybackSpeed = 1 + need * 0.3
	end
end

function Movement.init()
	ContextActionService:BindAction("AchromaSprint", function(_: string, state: Enum.UserInputState, _: InputObject): Enum.ContextActionResult?
		if state == Enum.UserInputState.Begin then
			sprintHeld = true
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			sprintHeld = false
		end
		return Enum.ContextActionResult.Pass
	end, true, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)
	ContextActionService:SetTitle("AchromaSprint", "RUN")

	ContextActionService:BindAction("AchromaCrouch", function(_: string, state: Enum.UserInputState, _: InputObject): Enum.ContextActionResult?
		if state == Enum.UserInputState.Begin then
			ClientState.crouching = not ClientState.crouching
		end
		return Enum.ContextActionResult.Pass
	end, true, Enum.KeyCode.C, Enum.KeyCode.LeftControl, Enum.KeyCode.ButtonB)
	ContextActionService:SetTitle("AchromaCrouch", "CROUCH")

	breath = Audio.create("BreathLoop", nil, 0)
	if breath then
		breath:Play()
	end

	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	RunService.RenderStepped:Connect(update)
end

return Movement
