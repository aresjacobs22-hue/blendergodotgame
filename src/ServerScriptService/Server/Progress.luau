--!strict
-- Which nights each player has unlocked, saved with DataStores. The value lives on
-- the Player as the "HighestNight" attribute so the menu can read it:
--   1..5 = highest night you may play, 6 = you've beaten all five.
-- DataStores only work in a published game (or with Studio API access turned on);
-- without them progress just lasts for the session.

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Nights = require(ReplicatedStorage.Shared.Nights)

local Progress = {}

local store: DataStore? = nil
pcall(function()
	store = DataStoreService:GetDataStore(Config.Progress.DataStoreName)
end)

local function key(player: Player): string
	return "u" .. player.UserId
end

function Progress.load(player: Player)
	local highest = 1
	local s = store
	if s then
		local ok, value = pcall(function()
			return s:GetAsync(key(player))
		end)
		if ok and typeof(value) == "number" then
			highest = math.clamp(math.floor(value), 1, Nights.count + 1)
		end
	end
	if RunService:IsStudio() and Config.Progress.UnlockAllInStudio then
		highest = math.max(highest, Nights.count)
	end
	player:SetAttribute("HighestNight", highest)
end

function Progress.highest(player: Player): number
	local value = player:GetAttribute("HighestNight")
	return if typeof(value) == "number" then value else 1
end

-- You beat `night`: unlock the next one.
function Progress.beat(player: Player, night: number)
	local unlocked = math.min(night + 1, Nights.count + 1)
	if unlocked <= Progress.highest(player) then
		return
	end
	player:SetAttribute("HighestNight", unlocked)
	local s = store
	if s then
		task.spawn(function()
			pcall(function()
				s:UpdateAsync(key(player), function(old: any)
					return math.max(if typeof(old) == "number" then old else 1, unlocked)
				end)
			end)
		end)
	end
end

return Progress
