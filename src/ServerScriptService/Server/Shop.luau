--!strict
-- Robux purchases (the IDs are in Config.Shop; anything at 0 is switched off).
--   Passes: owned forever. Owning one sets "Pass<Name>" on the Player, which the
--     flashlight, stamina and bottle code read.
--   Products: used up straight away. Revive / Batteries / Bottles / Adrenaline only
--     work while you're in a night; bought anywhere else, Roblox keeps the receipt and
--     hands it back to us next time (we say NotProcessedYet), so nobody pays for nothing.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Remotes = ReplicatedStorage.Remotes
local PASSES: { [string]: number } = Config.Shop.Passes :: any
local PRODUCTS: { [string]: number } = Config.Shop.Products :: any

export type Hooks = {
	revive: (player: Player) -> boolean, -- get a caught player back up; false if there's no night to go back to
	isAlive: (player: Player) -> boolean,
}

local Shop = {}

local function anyId(list: { [string]: number }): boolean
	for _, id in list do
		if id ~= 0 then
			return true
		end
	end
	return false
end

function Shop.enabled(): boolean
	return anyId(PASSES) or anyId(PRODUCTS)
end

function Shop.canRevive(): boolean
	return PRODUCTS.Revive ~= 0
end

local function checkPasses(player: Player)
	for name, id in PASSES do
		if id ~= 0 then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, id)
			end)
			if ok and owns then
				player:SetAttribute("Pass" .. name, true)
			end
		end
	end
end

function Shop.start(hooks: Hooks)
	if not Shop.enabled() then
		return
	end
	Players.PlayerAdded:Connect(checkPasses)
	for _, player in Players:GetPlayers() do
		task.spawn(checkPasses, player)
	end
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, bought: boolean)
		if not bought then
			return
		end
		for name, id in PASSES do
			if id == passId then
				player:SetAttribute("Pass" .. name, true)
			end
		end
	end)

	local grant: { [string]: (Player) -> boolean } = {
		Revive = hooks.revive,
		Batteries = function(player: Player): boolean
			if not hooks.isAlive(player) then
				return false
			end
			Remotes.Battery:FireClient(player, 100)
			return true
		end,
		Bottles = function(player: Player): boolean
			if not hooks.isAlive(player) then
				return false
			end
			local have = player:GetAttribute("Bottles")
			local cap = if player:GetAttribute("PassPockets") == true then 5 else 3
			player:SetAttribute("Bottles", math.min(cap, (if typeof(have) == "number" then have else 0) + 3))
			return true
		end,
		Adrenaline = function(player: Player): boolean
			if not hooks.isAlive(player) then
				return false
			end
			player:SetAttribute("Adrenaline", workspace:GetServerTimeNow() + Config.Shop.AdrenalineTime)
			return true
		end,
	}
	MarketplaceService.ProcessReceipt = function(receipt: { [string]: any }): Enum.ProductPurchaseDecision
		local player = Players:GetPlayerByUserId(receipt.PlayerId)
		if not player then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		for name, id in PRODUCTS do
			if id ~= 0 and id == receipt.ProductId then
				local fn = grant[name]
				local ok, done = pcall(fn, player)
				if ok and done then
					return Enum.ProductPurchaseDecision.PurchaseGranted
				end
				return Enum.ProductPurchaseDecision.NotProcessedYet
			end
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
end

return Shop
