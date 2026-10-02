--!strict
-- The exit keypad screen: type the four digits from the key tags and press OK.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Audio = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Audio"))
local ClientState = require(script.Parent.ClientState)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local GameState = ReplicatedStorage:WaitForChild("GameState")
local player = Players.LocalPlayer

local Keypad = {}

local gui: ScreenGui
local display: TextLabel
local code = ""
local isOpen = false
local openedAt: Vector3? = nil

local DIGIT_KEYS: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.Zero] = "0",
	[Enum.KeyCode.One] = "1",
	[Enum.KeyCode.Two] = "2",
	[Enum.KeyCode.Three] = "3",
	[Enum.KeyCode.Four] = "4",
	[Enum.KeyCode.Five] = "5",
	[Enum.KeyCode.Six] = "6",
	[Enum.KeyCode.Seven] = "7",
	[Enum.KeyCode.Eight] = "8",
	[Enum.KeyCode.Nine] = "9",
	[Enum.KeyCode.KeypadZero] = "0",
	[Enum.KeyCode.KeypadOne] = "1",
	[Enum.KeyCode.KeypadTwo] = "2",
	[Enum.KeyCode.KeypadThree] = "3",
	[Enum.KeyCode.KeypadFour] = "4",
	[Enum.KeyCode.KeypadFive] = "5",
	[Enum.KeyCode.KeypadSix] = "6",
	[Enum.KeyCode.KeypadSeven] = "7",
	[Enum.KeyCode.KeypadEight] = "8",
	[Enum.KeyCode.KeypadNine] = "9",
}

-- Digits you've typed, and faintly behind them the ones the keys you found had on
-- their tags (the keypad remembers, so you don't have to read anything).
local function refresh()
	local mask = GameState:GetAttribute("CodeMask")
	local known = if typeof(mask) == "string" then mask else ""
	local shown = {}
	for i = 1, 4 do
		local hint = string.sub(known, i, i)
		if i <= #code then
			shown[i] = string.sub(code, i, i)
		elseif hint ~= "" and hint ~= "_" then
			shown[i] = '<font transparency="0.7">' .. hint .. "</font>"
		else
			shown[i] = '<font transparency="0.7">_</font>'
		end
	end
	display.Text = table.concat(shown, " ")
end

local function close()
	isOpen = false
	ClientState.keypadOpen = false
	gui.Enabled = false
end

local function rootPosition(): Vector3?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	return if root then root.Position else nil
end

local function open()
	code = ""
	refresh()
	isOpen = true
	ClientState.keypadOpen = true
	openedAt = rootPosition()
	gui.Enabled = true
end

local function press(key: string)
	if not isOpen then
		return
	end
	if key == "CLR" then
		code = ""
		Audio.play("KeypadBeep", nil, 0.5, 0.8)
	elseif key == "OK" then
		if #code == 4 then
			Audio.play("KeypadBeep", nil, 0.6, 1.2)
			Remotes.SubmitCode:FireServer(code)
			close()
			return
		end
		Audio.play("KeypadError", nil, 0.4)
	elseif #code < 4 then
		code ..= key
		Audio.play("KeypadBeep", nil, 0.55, 1 + #code * 0.04)
	end
	refresh()
end

function Keypad.init()
	gui = Instance.new("ScreenGui")
	gui.Name = "AchromaKeypad"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 15
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Modal = true frees the mouse from first-person lock while this is open
	local panel = Instance.new("TextButton")
	panel.Name = "Panel"
	panel.Modal = true
	panel.AutoButtonColor = false
	panel.Text = ""
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(300, 430)
	panel.BackgroundColor3 = Color3.fromRGB(28, 28, 30)
	panel.BorderSizePixel = 0
	panel.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(90, 90, 90)
	stroke.Thickness = 2
	stroke.Parent = panel
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 6)
	c.Parent = panel

	display = Instance.new("TextLabel")
	display.Position = UDim2.fromOffset(20, 20)
	display.Size = UDim2.new(1, -40, 0, 64)
	display.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
	display.BorderSizePixel = 0
	display.Font = Enum.Font.Code
	display.TextSize = 40
	display.TextColor3 = Color3.fromRGB(220, 220, 220)
	display.RichText = true
	display.Parent = panel

	local keys = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "CLR", "0", "OK" }
	for i, key in keys do
		local col = (i - 1) % 3
		local row = math.floor((i - 1) / 3)
		local b = Instance.new("TextButton")
		b.Name = "Key" .. key
		b.Position = UDim2.fromOffset(20 + col * 90, 100 + row * 78)
		b.Size = UDim2.fromOffset(80, 68)
		b.BackgroundColor3 = Color3.fromRGB(52, 52, 54)
		b.AutoButtonColor = true
		b.BorderSizePixel = 0
		b.Font = Enum.Font.Code
		b.TextSize = if #key > 1 then 22 else 32
		b.TextColor3 = Color3.fromRGB(225, 225, 225)
		b.Text = key
		b.Parent = panel
		local bc = Instance.new("UICorner")
		bc.CornerRadius = UDim.new(0, 4)
		bc.Parent = b
		b.Activated:Connect(function()
			press(key)
		end)
	end

	local closeButton = Instance.new("TextButton")
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -6, 0, -34)
	closeButton.Size = UDim2.fromOffset(28, 28)
	closeButton.BackgroundTransparency = 1
	closeButton.Font = Enum.Font.SpecialElite
	closeButton.TextSize = 26
	closeButton.TextColor3 = Color3.fromRGB(170, 170, 170)
	closeButton.Text = "×"
	closeButton.Parent = panel
	closeButton.Activated:Connect(close)

	Remotes.OpenKeypad.OnClientEvent:Connect(open)

	UserInputService.InputBegan:Connect(function(input: InputObject, _processed: boolean)
		if not isOpen then
			return
		end
		local digit = DIGIT_KEYS[input.KeyCode]
		if digit then
			press(digit)
		elseif input.KeyCode == Enum.KeyCode.Backspace then
			code = string.sub(code, 1, math.max(0, #code - 1))
			refresh()
		elseif input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.KeypadEnter then
			press("OK")
		elseif input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
			close()
		end
	end)

	-- close it if you get dragged away, die, or walk off
	RunService.Heartbeat:Connect(function()
		if not isOpen then
			return
		end
		local pos = rootPosition()
		if not pos or ClientState.jumpscaring or ClientState.hiding or (openedAt and (pos - openedAt).Magnitude > 10) then
			close()
		end
	end)
end

return Keypad
