--!strict
-- Interaction prompts without words: when you're close enough to use something, a small
-- pale dot appears on it with the key to press. Holding fills a ring around it. Tap it
-- on a phone.

local ProximityPromptService = game:GetService("ProximityPromptService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local Prompts = {}

local PALE = Color3.fromRGB(215, 215, 208)

type Shown = { gui: BillboardGui, ring: UIStroke, fill: Frame, holdStart: number? }
local shown: { [ProximityPrompt]: Shown } = {}

local function keyFor(prompt: ProximityPrompt, input: Enum.ProximityPromptInputType): string
	if input == Enum.ProximityPromptInputType.Gamepad then
		return string.gsub(prompt.GamepadKeyCode.Name, "^Button", "")
	elseif input == Enum.ProximityPromptInputType.Touch then
		return ""
	end
	return prompt.KeyboardKeyCode.Name
end

local function show(prompt: ProximityPrompt, input: Enum.ProximityPromptInputType)
	local gui = Instance.new("BillboardGui")
	gui.Name = "AchromaPrompt"
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(34, 34)
	gui.LightInfluence = 0
	gui.Adornee = prompt.Parent :: Instance
	gui.Active = true

	local dot = Instance.new("TextButton")
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromOffset(22, 22)
	dot.BackgroundColor3 = Color3.new(0, 0, 0)
	dot.BackgroundTransparency = 0.55
	dot.AutoButtonColor = false
	dot.Font = Enum.Font.Garamond
	dot.TextSize = 15
	dot.TextColor3 = PALE
	dot.TextTransparency = 0.25
	dot.Text = keyFor(prompt, input)
	dot.Parent = gui
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = dot
	local ring = Instance.new("UIStroke")
	ring.Color = PALE
	ring.Thickness = 1
	ring.Transparency = 0.55
	ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ring.Parent = dot

	-- fills from the centre while you hold
	local fill = Instance.new("Frame")
	fill.AnchorPoint = Vector2.new(0.5, 0.5)
	fill.Position = UDim2.fromScale(0.5, 0.5)
	fill.Size = UDim2.fromScale(0, 0)
	fill.BackgroundColor3 = PALE
	fill.BackgroundTransparency = 0.6
	fill.BorderSizePixel = 0
	fill.ZIndex = 0
	fill.Parent = dot
	local fillRound = Instance.new("UICorner")
	fillRound.CornerRadius = UDim.new(0.5, 0)
	fillRound.Parent = fill

	-- touch: press and hold the dot itself
	dot.InputBegan:Connect(function(io: InputObject)
		if io.UserInputType == Enum.UserInputType.Touch or io.UserInputType == Enum.UserInputType.MouseButton1 then
			prompt:InputHoldBegin()
		end
	end)
	dot.InputEnded:Connect(function(io: InputObject)
		if io.UserInputType == Enum.UserInputType.Touch or io.UserInputType == Enum.UserInputType.MouseButton1 then
			prompt:InputHoldEnd()
		end
	end)

	gui.Parent = player:WaitForChild("PlayerGui")
	shown[prompt] = { gui = gui, ring = ring, fill = fill, holdStart = nil }
end

local function hide(prompt: ProximityPrompt)
	local s = shown[prompt]
	if s then
		s.gui:Destroy()
		shown[prompt] = nil
	end
end

function Prompts.init()
	ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt, input: Enum.ProximityPromptInputType)
		if prompt.Style == Enum.ProximityPromptStyle.Custom then
			show(prompt, input)
		end
	end)
	ProximityPromptService.PromptHidden:Connect(hide)
	ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt: ProximityPrompt)
		local s = shown[prompt]
		if s then
			s.holdStart = os.clock()
		end
	end)
	ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt: ProximityPrompt)
		local s = shown[prompt]
		if s then
			s.holdStart = nil
			s.fill.Size = UDim2.fromScale(0, 0)
		end
	end)
	RunService.RenderStepped:Connect(function()
		for prompt, s in shown do
			if not prompt.Parent or not prompt.Enabled then
				hide(prompt)
			else
				local start = s.holdStart
				if start and prompt.HoldDuration > 0 then
					local k = math.clamp((os.clock() - start) / prompt.HoldDuration, 0, 1)
					s.fill.Size = UDim2.fromScale(k, k)
				end
				-- the dot breathes very slightly so it reads as "something's here"
				s.ring.Transparency = 0.5 + 0.15 * math.sin(os.clock() * 3)
			end
		end
	end)
end

return Prompts
