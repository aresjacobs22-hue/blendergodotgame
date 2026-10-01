--!strict
-- Your flashlight: a shadow-casting spotlight that lags slightly behind your view,
-- drains its battery, stutters when the monster is near, and gives you away.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Audio = require(Shared:WaitForChild("Audio"))
local Config = require(Shared:WaitForChild("Config"))
local ClientState = require(script.Parent.ClientState)
local Hud = require(script.Parent.Hud)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local player = Players.LocalPlayer

local Flashlight = {}

local BRIGHTNESS = 2.6

local holder: Part
local beam: SpotLight
local spill: SpotLight
local battery = 100
local on = false
local sway: CFrame? = nil
local dropUntil = 0
local hinted = false

local function setOn(value: boolean)
	if value and battery <= 0 then
		Audio.play("FlashlightClick", nil, 0.5, 0.8)
		Hud.message("The battery is dead.")
		return
	end
	if value == on then
		return
	end
	on = value
	ClientState.flashlightOn = value
	Audio.play("FlashlightClick", nil, 0.7)
	Remotes.Flashlight:FireServer(value)
end

local function alive(): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function update(dt: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	if holder.Parent ~= camera then
		holder.Parent = camera
	end
	local target = camera.CFrame * CFrame.new(0.45, -0.5, -0.4)
	local current = if sway then sway:Lerp(target, math.min(1, dt * 14)) else target
	sway = current
	holder.CFrame = CFrame.new(target.Position) * current.Rotation

	if on and (not alive() or ClientState.hiding or ClientState.jumpscaring) then
		setOn(false)
	end
	if on then
		battery = math.max(0, battery - Config.Player.BatteryDrain * dt)
		if battery <= 0 then
			setOn(false)
			Hud.message("Your flashlight flickers... and dies.")
		end
	end
	Hud.setBattery(battery / 100)

	-- stutter when the battery is low or the monster is close
	local now = os.clock()
	local instability = ClientState.interference
	if battery < 20 then
		instability = math.max(instability, (20 - battery) / 20 * 0.7)
	end
	if instability > 0 and math.random() < instability * 0.12 then
		dropUntil = now + 0.03 + math.random() * 0.14
	end
	local brightness = if now < dropUntil then BRIGHTNESS * 0.06 else BRIGHTNESS
	beam.Enabled = on
	spill.Enabled = on
	beam.Brightness = brightness
	spill.Brightness = brightness * 0.22

	-- the server puts a copy of your light on your head for other players; hide ours
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	local shared = head and head:FindFirstChild("SharedFlashlight")
	if shared and shared:IsA("SpotLight") then
		shared.Enabled = false
	end
end

function Flashlight.init()
	holder = Instance.new("Part")
	holder.Name = "AchromaFlashlight"
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.Transparency = 1
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.CastShadow = false

	beam = Instance.new("SpotLight")
	beam.Face = Enum.NormalId.Front
	beam.Angle = 46
	beam.Range = 48
	beam.Brightness = BRIGHTNESS
	beam.Shadows = true
	beam.Color = Color3.fromRGB(255, 248, 235)
	beam.Enabled = false
	beam.Parent = holder

	spill = Instance.new("SpotLight")
	spill.Face = Enum.NormalId.Front
	spill.Angle = 110
	spill.Range = 16
	spill.Brightness = BRIGHTNESS * 0.22
	spill.Shadows = false
	spill.Enabled = false
	spill.Parent = holder

	ContextActionService:BindAction("AchromaFlashlight", function(_: string, state: Enum.UserInputState, _: InputObject): Enum.ContextActionResult?
		if state == Enum.UserInputState.Begin and alive() and not ClientState.hiding then
			setOn(not on)
		end
		return Enum.ContextActionResult.Pass
	end, true, Enum.KeyCode.F, Enum.KeyCode.ButtonY)
	ContextActionService:SetTitle("AchromaFlashlight", "LIGHT")

	Remotes.Battery.OnClientEvent:Connect(function(amount: number)
		battery = math.min(100, battery + amount)
		Audio.play("Battery", nil, 0.8)
		Hud.message("You found a battery.")
	end)

	player.CharacterAdded:Connect(function()
		battery = 100
		on = false
		ClientState.flashlightOn = false
		if not hinted then
			hinted = true
			task.delay(6, function()
				Hud.message("Press F to use your flashlight.  Shift to run, C to crouch.")
			end)
		end
	end)

	RunService:BindToRenderStep("AchromaFlashlight", Enum.RenderPriority.Camera.Value + 1, update)
end

return Flashlight
