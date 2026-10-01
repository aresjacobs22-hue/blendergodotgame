--!strict
-- How a night ends for you: the jumpscare when it catches you, or the white-out
-- when you make it through the exit.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Audio = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Audio"))
local ClientState = require(script.Parent.ClientState)
local Hud = require(script.Parent.Hud)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local Endings = {}

local changed = Instance.new("BindableEvent")
Endings.Changed = changed.Event -- fires when a sequence finishes

local DEATH_LINES = {
	"It was standing behind you the whole time.",
	"You should have stayed quiet.",
	"It saw your light.",
	"Nobody heard you scream.",
	"The grey takes another one.",
}

local function jumpscare(monster: Model)
	ClientState.jumpscaring = true
	ClientState.roundStatus = "caught"
	local camera = workspace.CurrentCamera
	local head = monster:FindFirstChild("Head") :: BasePart?

	Hud.setHudVisible(false)
	Hud.setHint("")
	Hud.flash(1, 0.12)
	Audio.play("Jumpscare", nil, 2.6)
	camera.CameraType = Enum.CameraType.Scriptable

	local start = os.clock()
	RunService:BindToRenderStep("AchromaJumpscare", Enum.RenderPriority.Last.Value, function()
		local e = os.clock() - start
		if head and head.Parent then
			local hp = head.Position
			local face = head.CFrame.LookVector
			local dist = 4.4 - math.min(1, e / 0.15) * 2.9 -- it lunges into your face
			local shake = math.max(0.15, 1 - e / 1.6)
			camera.CFrame = CFrame.lookAt(hp + face * dist - Vector3.new(0, 0.3, 0), hp)
				* CFrame.Angles((math.random() - 0.5) * 0.12 * shake, (math.random() - 0.5) * 0.12 * shake, (math.random() - 0.5) * 0.35 * shake)
			camera.FieldOfView = 62 - math.min(e, 0.4) * 30
		end
		Hud.glitch(0.9, 0.1)
		if e > 1.7 then
			RunService:UnbindFromRenderStep("AchromaJumpscare")
			Hud.fade(0, 0)
			Hud.showBig("IT FOUND YOU", DEATH_LINES[math.random(1, #DEATH_LINES)])
			task.delay(3, function()
				Hud.hideBig()
				camera.FieldOfView = 70
				camera.CameraType = Enum.CameraType.Custom
				ClientState.jumpscaring = false
				Hud.fade(1, 1.2)
				changed:Fire()
			end)
		end
	end)
end

local function escaped()
	ClientState.roundStatus = "escaped"
	ClientState.jumpscaring = true -- freezes input-driven effects for the sequence
	Hud.setHudVisible(false)
	Audio.play("Escape", nil, 1.2)
	Hud.whiteout(0, 2.5)
	task.delay(2, function()
		Hud.setBigColor(Color3.fromRGB(25, 25, 25))
		Hud.showBig("YOU ESCAPED", "For a second, you could swear you saw color again.")
	end)
	task.delay(6.5, function()
		Hud.hideBig(true)
		Hud.setBigColor(Color3.fromRGB(205, 205, 200))
		Hud.whiteout(1, 1.5)
		ClientState.jumpscaring = false
		changed:Fire()
	end)
end

function Endings.init()
	Remotes.Jumpscare.OnClientEvent:Connect(function(monster: Model)
		jumpscare(monster)
	end)
	Remotes.Escaped.OnClientEvent:Connect(escaped)
end

return Endings
