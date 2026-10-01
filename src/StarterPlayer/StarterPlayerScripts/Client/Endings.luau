--!strict
-- How a night ends for you: the jumpscare when it catches you, or the white-out
-- when you make it through the exit.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

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

local KIND_LINES: { [string]: { string } } = {
	Hollow = { "It was standing behind you the whole time.", "It saw your light.", "The grey takes another one." },
	Crawler = { "It was under the bed the whole time.", "You never looked down.", "Visiting hours are over." },
	Listener = { "It heard every step.", "You should have stayed quiet." },
	Statue = { "You blinked.", "You looked away. Just for a second.", "It was never a statue." },
	Amalgam = { "It is all of them. Now it's you too.", "There is no morning here." },
}

-- how close the camera ends up to each monster's head (their faces stick out more or less)
local FACE_DISTANCE: { [string]: number } = { Hollow = 2.8, Crawler = 2.0, Listener = 2.9, Statue = 1.7, Amalgam = 2.6 }

local function jumpscare(monster: Model)
	local kind = monster:GetAttribute("Kind")
	local lines = if typeof(kind) == "string" and KIND_LINES[kind] then KIND_LINES[kind] else DEATH_LINES
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
			local near = if typeof(kind) == "string" and FACE_DISTANCE[kind] then FACE_DISTANCE[kind] else 1.6
			local dist = near + 3 - math.min(1, e / 0.15) * 3 -- it lunges into your face
			local shake = math.max(0.15, 1 - e / 1.6)
			camera.CFrame = CFrame.lookAt(hp + face * dist - Vector3.new(0, 0.3, 0), hp)
				* CFrame.Angles((math.random() - 0.5) * 0.12 * shake, (math.random() - 0.5) * 0.12 * shake, (math.random() - 0.5) * 0.35 * shake)
			camera.FieldOfView = 62 - math.min(e, 0.4) * 30
		end
		Hud.glitch(0.9, 0.1)
		if e > 1.7 then
			RunService:UnbindFromRenderStep("AchromaJumpscare")
			Hud.fade(0, 0)
			Hud.showBig("IT FOUND YOU", lines[math.random(1, #lines)])
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

local ENDINGS: { [string]: { title: string, sub: string } } = {
	escaped = { title = "YOU ESCAPED", sub = "For a second, you could swear you saw color again." },
	survived = { title = "6:00 AM", sub = "The sun comes up. It's still grey. But you're still here." },
	collected = { title = "YOU FOUND THEM ALL", sub = "The last photograph shows a door that wasn't there before. You're already through it." },
	final = { title = "THE COLOR IS BACK", sub = "You woke up. For real this time.\n\nACHROMA  ·  thank you for playing" },
}

local function escaped(kind: string?)
	local ending = ENDINGS[kind or "escaped"] or ENDINGS.escaped
	ClientState.roundStatus = "escaped"
	ClientState.jumpscaring = true -- freezes input-driven effects for the sequence
	Hud.setHudVisible(false)
	Audio.play(if kind == "survived" then "ClockChime" else "Escape", nil, 1.2)
	Hud.whiteout(0, if kind == "final" then 5 else 2.5)
	if kind == "final" then
		-- the color actually comes back
		local grade = Lighting:FindFirstChild("Monochrome")
		if grade and grade:IsA("ColorCorrectionEffect") then
			TweenService:Create(grade, TweenInfo.new(6, Enum.EasingStyle.Sine), { Saturation = 0.45, TintColor = Color3.new(1, 1, 1), Contrast = 0.1 }):Play()
		end
	end
	task.delay(2, function()
		Hud.setBigColor(Color3.fromRGB(25, 25, 25))
		Hud.showBig(ending.title, ending.sub)
	end)
	task.delay(if kind == "final" then 9 else 6.5, function()
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
	Remotes.Escaped.OnClientEvent:Connect(function(kind: string?)
		escaped(kind)
	end)
end

return Endings
