--!strict
-- While you're inside a locker/wardrobe: darker vignette, a "leave" prompt, the E key /
-- touch button to get back out, and holding your breath when it comes close: hold
-- SPACE (R2 / the HOLD BREATH button) while it's right outside. Let go too long, or run
-- out of breath, and it hears you.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Audio = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Audio"))
local ClientState = require(script.Parent.ClientState)
local Hud = require(script.Parent.Hud)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local player = Players.LocalPlayer

local Hiding = {}

local NEAR = 10 -- studs: right outside the door, close enough to hear you breathe
local HOLD_FOR = 10 -- seconds of breath
local GRACE = 1.3 -- seconds you can forget to hold it while it's close

local breath = 1
local holding = false
local exposed = 0
local gaveAway = false

local function monsterNear(): boolean
	local monster = workspace:FindFirstChild("Monster")
	local root = if monster then monster:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	local character = player.Character
	local me = if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	if not monster or not root or not me or root.Position.Y < -100 then
		return false
	end
	local state = monster:GetAttribute("State")
	if state == "Dormant" or state == "Apparition" or state == "Kill" or monster:GetAttribute("Kind") == "Statue" then
		return false
	end
	return (root.Position - me.Position).Magnitude < NEAR
end

local function giveAway()
	gaveAway = true
	holding = false
	ClientState.holdingBreath = false
	Audio.play("Gasp", nil, 1.3)
	Hud.glitch(0.6, 0.4)
	Remotes.Breath:FireServer()
end

local function update(dt: number)
	if not ClientState.hiding then
		Hud.setBreath(false, 1, false)
		return
	end
	local near = monsterNear()
	if holding then
		breath -= dt / HOLD_FOR
		if breath <= 0 then
			breath = 0
			if near and not gaveAway then
				giveAway()
			elseif not near then
				-- it already left: gasp all you like
				holding = false
				ClientState.holdingBreath = false
				Audio.play("Gasp", nil, 0.9)
			end
		end
	else
		breath = math.min(1, breath + dt / 3)
	end
	if near and not holding and not gaveAway then
		exposed += dt
		if exposed > GRACE then
			giveAway()
		end
	elseif holding or not near then
		exposed = math.max(0, exposed - dt * 2)
	end
	local show = (near and not gaveAway) or breath < 1
	Hud.setBreath(show, breath, near and not holding)
end

local function setHolding(on: boolean)
	if on and not holding and breath > 0.05 and not gaveAway then
		Audio.play("BreathHold", nil, 0.8)
	end
	holding = on and breath > 0 and not gaveAway
	ClientState.holdingBreath = holding
end

local function refresh()
	local hiding = player:GetAttribute("Hiding") == true
	if hiding == ClientState.hiding then
		return
	end
	ClientState.hiding = hiding
	Hud.setHiding(hiding)
	breath, exposed, gaveAway = 1, 0, false
	setHolding(false)
	if hiding then
		ContextActionService:BindAction("AchromaLeave", function(_: string, state: Enum.UserInputState, _: InputObject): Enum.ContextActionResult?
			if state == Enum.UserInputState.Begin then
				Remotes.LeaveHiding:FireServer()
			end
			return Enum.ContextActionResult.Sink
		end, true, Enum.KeyCode.E, Enum.KeyCode.ButtonX)
		ContextActionService:SetTitle("AchromaLeave", "LEAVE")
		ContextActionService:BindAction("AchromaBreath", function(_: string, state: Enum.UserInputState, _: InputObject): Enum.ContextActionResult?
			if state == Enum.UserInputState.Begin then
				setHolding(true)
			elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
				setHolding(false)
			end
			return Enum.ContextActionResult.Sink
		end, true, Enum.KeyCode.Space, Enum.KeyCode.ButtonR2)
		ContextActionService:SetTitle("AchromaBreath", "HOLD BREATH")
	else
		ContextActionService:UnbindAction("AchromaLeave")
		ContextActionService:UnbindAction("AchromaBreath")
	end
end

function Hiding.init()
	player:GetAttributeChangedSignal("Hiding"):Connect(refresh)
	refresh()
	RunService.RenderStepped:Connect(update)
end

return Hiding
