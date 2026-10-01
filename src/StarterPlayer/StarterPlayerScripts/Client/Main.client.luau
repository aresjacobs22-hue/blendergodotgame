--!strict
-- ACHROMA client entry point: hides Roblox's default UI and starts every controller.

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Atmosphere = require(script.Parent.Atmosphere)
local ClientState = require(script.Parent.ClientState)
local Endings = require(script.Parent.Endings)
local Flashlight = require(script.Parent.Flashlight)
local Hiding = require(script.Parent.Hiding)
local Hud = require(script.Parent.Hud)
local Keypad = require(script.Parent.Keypad)
local Menu = require(script.Parent.Menu)
local MonsterAnimator = require(script.Parent.MonsterAnimator)
local Movement = require(script.Parent.Movement)
local Spectate = require(script.Parent.Spectate)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local player = Players.LocalPlayer

for _, coreGui in { Enum.CoreGuiType.Backpack, Enum.CoreGuiType.Health, Enum.CoreGuiType.EmotesMenu, Enum.CoreGuiType.PlayerList } do
	StarterGui:SetCoreGuiEnabled(coreGui, false)
end
task.spawn(function()
	-- resetting your character would be a free escape from the monster
	for _ = 1, 20 do
		if pcall(function()
			StarterGui:SetCore("ResetButtonCallback", false)
		end) then
			break
		end
		task.wait(0.5)
	end
end)

Hud.init()
Movement.init()
Flashlight.init()
Atmosphere.init()
MonsterAnimator.init()
Endings.init()
Hiding.init()
Keypad.init()
Spectate.init()
Menu.init()

Remotes.Notify.OnClientEvent:Connect(function(text: string, style: string?)
	Hud.message(text, style)
end)

local wakeLines = {
	"You wake up. Everything is grey.",
	"You wake up again. The house is quieter this time.",
	"Same bed. Same grey. Same night.",
}
local nights = 0

player.CharacterAdded:Connect(function(character: Model)
	nights += 1
	ClientState.roundStatus = "alive"
	ClientState.jumpscaring = false
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	camera.CameraSubject = humanoid
	Hud.setHudVisible(true)
	Hud.whiteout(1, 0)
	Hud.fade(0, 0)
	Hud.fade(1, 3)
	Atmosphere.wakeUp()
	task.delay(1.5, function()
		Hud.message(wakeLines[math.min(nights, #wakeLines)])
	end)
end)

player.CharacterRemoving:Connect(function()
	Hud.setHudVisible(false)
end)
