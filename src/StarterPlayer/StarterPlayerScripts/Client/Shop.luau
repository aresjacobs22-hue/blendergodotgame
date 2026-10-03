--!strict
-- The Robux shop: a small R$ button in the lobby, or B anywhere. Passes are kept forever;
-- the one-off things only show up during a night, when they can be used. Nothing here
-- exists until its ID is filled in (Config.Shop).

local ContextActionService = game:GetService("ContextActionService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Audio = require(Shared:WaitForChild("Audio"))
local Config = require(Shared:WaitForChild("Config"))
local ClientState = require(script.Parent.ClientState)
local Hud = require(script.Parent.Hud)

local player = Players.LocalPlayer

local Shop = {}

local PALE = Color3.fromRGB(200, 200, 194)
local FONT = Hud.TITLE_FONT

type Item = { key: string, name: string, about: string, pass: boolean }
local ITEMS: { Item } = {
	{ key = "Lantern", name = "LANTERN", about = "a brighter flashlight that reaches further", pass = true },
	{ key = "LongBattery", name = "LONG LIFE BATTERY", about = "your battery lasts twice as long", pass = true },
	{ key = "Lungs", name = "IRON LUNGS", about = "run for longer", pass = true },
	{ key = "Pockets", name = "DEEP POCKETS", about = "carry 5 bottles instead of 3", pass = true },
	{ key = "Revive", name = "REVIVE", about = "get back up after it catches you", pass = false },
	{ key = "Batteries", name = "FRESH BATTERY", about = "a full battery, right now", pass = false },
	{ key = "Bottles", name = "BOTTLES", about = "3 bottles, right now", pass = false },
	{ key = "Adrenaline", name = "ADRENALINE", about = "a minute of running without getting tired", pass = false },
}

local function idOf(item: Item): number
	local list: { [string]: number } = if item.pass then Config.Shop.Passes else Config.Shop.Products
	return list[item.key] or 0
end

local function make<T>(className: string, props: { [string]: any }, parent: Instance?): T
	local inst = Instance.new(className :: any)
	for k, v in props do
		(inst :: any)[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return (inst :: any) :: T
end

function Shop.init()
	local items: { Item } = {}
	for _, item in ITEMS do
		if idOf(item) ~= 0 then
			table.insert(items, item)
		end
	end
	if #items == 0 then
		return
	end

	local gui: ScreenGui = make("ScreenGui", { Name = "AchromaShop", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 30 }, player:WaitForChild("PlayerGui"))
	local button: TextButton = make("TextButton", { Name = "ShopButton", Text = "R$", Font = FONT, TextSize = 22, TextColor3 = PALE, TextTransparency = 0.3, BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 22, 1, -22), Size = UDim2.fromOffset(44, 44), Visible = false }, gui)
	make("UIStroke", { Color = PALE, Thickness = 1, Transparency = 0.7, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, button)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, button)

	local panel: TextButton = make("TextButton", { Name = "Panel", Text = "", AutoButtonColor = false, Modal = true, Visible = false, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(560, 60 + #items * 62), BackgroundColor3 = Color3.fromRGB(8, 8, 8), BackgroundTransparency = 0.04, BorderSizePixel = 0 }, gui)
	make("UIStroke", { Color = PALE, Thickness = 1, Transparency = 0.8 }, panel)
	local close: TextButton = make("TextButton", { Name = "Close", Text = "×", Font = FONT, TextSize = 28, TextColor3 = PALE, TextTransparency = 0.4, BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 6), Size = UDim2.fromOffset(32, 32) }, panel)

	local rows: { { item: Item, row: TextButton, price: TextLabel } } = {}
	local function open(on: boolean)
		panel.Visible = on
		ClientState.shopOpen = on
		if not on then
			return
		end
		Audio.play("MenuHover", nil, 0.4, 0.7)
		-- one-off things only in a night; passes say OWNED once you have them
		local inNight = player:GetAttribute("Where") == "night"
		local y = 44
		for _, r in rows do
			local show = r.item.pass or inNight
			r.row.Visible = show
			if show then
				r.row.Position = UDim2.fromOffset(20, y)
				y += 62
			end
			if r.item.pass and player:GetAttribute("Pass" .. r.item.key) == true then
				r.price.Text = "OWNED"
			end
		end
		panel.Size = UDim2.fromOffset(560, y + 16)
	end

	for _, item in items do
		local id = idOf(item)
		local row: TextButton = make("TextButton", { Name = item.key, Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.fromOffset(520, 56) }, panel)
		local title: TextLabel = make("TextLabel", { Text = Hud.spaced(item.name), Font = FONT, TextSize = 20, TextColor3 = PALE, TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 4), Size = UDim2.fromOffset(400, 26) }, row)
		make("TextLabel", { Text = item.about, Font = FONT, TextSize = 15, TextColor3 = PALE, TextTransparency = 0.5, TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 30), Size = UDim2.fromOffset(400, 20) }, row)
		local price: TextLabel = make("TextLabel", { Text = "R$", Font = FONT, TextSize = 20, TextColor3 = PALE, TextXAlignment = Enum.TextXAlignment.Right, BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 12), Size = UDim2.fromOffset(110, 28) }, row)
		task.spawn(function()
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(id, if item.pass then Enum.InfoType.GamePass else Enum.InfoType.Product)
			end)
			if ok and info and typeof(info.PriceInRobux) == "number" and price.Text ~= "OWNED" then
				price.Text = "R$ " .. tostring(info.PriceInRobux)
			end
		end)
		row.MouseEnter:Connect(function()
			title.TextTransparency = 0
		end)
		row.MouseLeave:Connect(function()
			title.TextTransparency = 0.15
		end)
		row.Activated:Connect(function()
			Audio.play("MenuSelect", nil, 0.6, 0.85)
			if item.pass then
				if player:GetAttribute("Pass" .. item.key) ~= true then
					MarketplaceService:PromptGamePassPurchase(player, id)
				end
			else
				MarketplaceService:PromptProductPurchase(player, id)
			end
		end)
		table.insert(rows, { item = item, row = row, price = price })
		player:GetAttributeChangedSignal("Pass" .. item.key):Connect(function()
			if item.pass and player:GetAttribute("Pass" .. item.key) == true then
				price.Text = "OWNED"
			end
		end)
	end

	button.Activated:Connect(function()
		open(not panel.Visible)
	end)
	close.Activated:Connect(function()
		open(false)
	end)
	ContextActionService:BindAction("AchromaShop", function(_name: string, state: Enum.UserInputState): Enum.ContextActionResult
		if state == Enum.UserInputState.Begin then
			open(not panel.Visible)
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.B)

	-- the R$ button only in the lobby, out of the way of the door screens
	local function refresh()
		button.Visible = player:GetAttribute("Where") == "lobby"
		if panel.Visible then
			open(true)
		end
	end
	player:GetAttributeChangedSignal("Where"):Connect(refresh)
	refresh()
end

return Shop
