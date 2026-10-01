--!strict
-- After you're caught (or escape) while others are still inside, watch over a
-- survivor's shoulder. Click / R1 / tap to switch who you follow.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local ClientState = require(script.Parent.ClientState)

local GameState = ReplicatedStorage:WaitForChild("GameState")
local player = Players.LocalPlayer

local Spectate = {}

local target: Player? = nil
local active = false
local smoothed: CFrame? = nil

local function survivors(): { Player }
	local list = {}
	for _, p in Players:GetPlayers() do
		local character = p.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if p ~= player and humanoid and humanoid.Health > 0 and character and character:FindFirstChild("Head") then
			table.insert(list, p)
		end
	end
	return list
end

local function nextTarget()
	local list = survivors()
	if #list == 0 then
		target = nil
		return
	end
	local index = table.find(list, target :: any) or 0
	target = list[index % #list + 1]
	smoothed = nil
end

function Spectate.isActive(): boolean
	return active
end

function Spectate.init()
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if not active or processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch or input.KeyCode == Enum.KeyCode.ButtonR1 then
			nextTarget()
		end
	end)

	RunService:BindToRenderStep("AchromaSpectate", Enum.RenderPriority.Camera.Value + 3, function(dt: number)
		local camera = workspace.CurrentCamera
		local shouldSpectate = ClientState.started
			and not ClientState.jumpscaring
			and player.Character == nil
			and GameState:GetAttribute("Phase") == "Playing"
		if not shouldSpectate then
			active = false
			return
		end

		local list = survivors()
		if not target or not table.find(list, target) then
			target = nil
			nextTarget()
		end
		local t = target
		local character = if t then t.Character else nil
		local head = if character then character:FindFirstChild("Head") :: BasePart? else nil
		if not t or not head then
			active = false
			return
		end
		active = true
		camera.CameraType = Enum.CameraType.Scriptable
		local look = head.CFrame.LookVector
		local flatLook = Vector3.new(look.X, 0, look.Z)
		if flatLook.Magnitude < 0.01 then
			flatLook = Vector3.new(0, 0, -1)
		end
		local goal = CFrame.lookAt(head.Position - flatLook.Unit * 5 + Vector3.new(0, 2.2, 0), head.Position + flatLook.Unit * 10)
		smoothed = if smoothed then smoothed:Lerp(goal, math.min(1, dt * 6)) else goal
		camera.CFrame = smoothed :: CFrame
	end)
end

return Spectate
