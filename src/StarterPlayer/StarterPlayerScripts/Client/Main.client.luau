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
Menu.init()

Remotes.Notify.OnClientEvent:Connect(function(text: string, style: string?)
	Hud.message(text, style)
end)

local Nights = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Nights"))
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
	Hud.fade(1, 3)
	Atmosphere.wakeUp()

	-- the night's title card, then its opening lines
	local n = GameState:GetAttribute("Night")
	local night = Nights.get(if typeof(n) == "number" then n else 1)
	Audio.play("NightIntro", nil, 1)
	Hud.setBigColor(night.accent)
	Hud.showBig(string.format("NIGHT %d", night.index), night.name .. "\n" .. night.objectiveText)
	-- then the curse it rolled this time
	local curseName = GameState:GetAttribute("CurseName")
	local curseText = GameState:GetAttribute("CurseText")
	local hasCurse = typeof(curseName) == "string" and curseName ~= "" and GameState:GetAttribute("Curse") ~= ""
	task.delay(4.2, function()
		Hud.hideBig()
		task.delay(0.9, function()
			if hasCurse and ClientState.roundStatus == "alive" then
				Audio.play("CurseSting", nil, 1.1)
				Hud.setBigColor(Color3.fromRGB(200, 60, 50))
				Hud.showBig("CURSE: " .. tostring(curseName), tostring(curseText))
			else
				Hud.setBigColor(Color3.fromRGB(205, 205, 200))
			end
		end)
		local delayLines = if hasCurse then 4.6 else 0
		task.delay(delayLines, function()
			if hasCurse then
				Hud.hideBig()
				task.delay(0.9, function()
					Hud.setBigColor(Color3.fromRGB(205, 205, 200))
				end)
			end
			for i, line in night.intro do
				task.delay((i - 1) * 2.5, function()
					if ClientState.roundStatus == "alive" then
						Hud.message(line)
					end
				end)
			end
		end)
	end)
end)

player.CharacterRemoving:Connect(function()
	Hud.setHudVisible(false)
end)
