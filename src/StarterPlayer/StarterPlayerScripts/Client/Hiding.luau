--!strict
-- While you're inside a locker/wardrobe: darker vignette, a "leave" prompt, and
-- the E key / touch button to get back out.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientState = require(script.Parent.ClientState)
local Hud = require(script.Parent.Hud)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local player = Players.LocalPlayer

local Hiding = {}

local function refresh()
	local hiding = player:GetAttribute("Hiding") == true
	if hiding == ClientState.hiding then
		return
	end
	ClientState.hiding = hiding
	Hud.setHiding(hiding)
	if hiding then
		Hud.message("Hold your breath.")
		ContextActionService:BindAction("AchromaLeave", function(_: string, state: Enum.UserInputState, _: InputObject): Enum.ContextActionResult?
			if state == Enum.UserInputState.Begin then
				Remotes.LeaveHiding:FireServer()
			end
			return Enum.ContextActionResult.Sink
		end, true, Enum.KeyCode.E, Enum.KeyCode.ButtonX)
		ContextActionService:SetTitle("AchromaLeave", "LEAVE")
	else
		ContextActionService:UnbindAction("AchromaLeave")
	end
end

function Hiding.init()
	player:GetAttributeChangedSignal("Hiding"):Connect(refresh)
	refresh()
end

return Hiding
