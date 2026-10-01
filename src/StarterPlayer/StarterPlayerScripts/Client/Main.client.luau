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
local Events = require(script.Parent.Events)
local Flashlight = require(script.Parent.Flashlight)
local Hiding = require(script.Parent.Hiding)
local Hud = require(script.Parent.Hud)
local Keypad = require(script.Parent.Keypad)
local Menu = require(script.Parent.Menu)
local MonsterAnimator = require(script.Parent.MonsterAnimator)
local Movement = require(script.Parent.Movement)
local Prompts = require(script.Parent.Prompts)
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
Events.init()
Prompts.init()
Menu.init()

-- The game never puts words on screen. What the server narrates (who found a key,
-- what the hour is) only goes to the developer console (F9).
Remotes.Notify.OnClientEvent:Connect(function(text: string, _style: string?)
	print("[ACHROMA] " .. text)
end)

local Audio = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Audio"))
local GameState = ReplicatedStorage:WaitForChild("GameState")

player.CharacterAdded:Connect(function(character: Model)
	ClientState.roundStatus = "alive"
	ClientState.jumpscaring = false
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	camera.CameraSubject = humanoid
	Hud.setHudVisible(true)
	Hud.whiteout(1, 0)
	Hud.fade(0, 0)

	-- black, the night's number, black again, and then you're just... there
	local n = GameState:GetAttribute("Night")
	Audio.play("NightIntro", nil, 0.8)
	Hud.showTitle(string.format("NIGHT %d", if typeof(n) == "number" then n else 1))
	task.delay(3.6, function()
		Hud.hideTitle()
		task.delay(1.4, function()
			if ClientState.roundStatus == "alive" then
				Hud.fade(1, 4)
				Atmosphere.wakeUp()
			end
		end)
	end)
end)

player.CharacterRemoving:Connect(function()
	Hud.setHudVisible(false)
end)
