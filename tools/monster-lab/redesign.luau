-- The proposed new nights 2-5: which theme each uses (Themes.luau) and the map and
-- lighting settings that go with it. Not in the game yet. map_dump.luau applies these
-- on top of Nights.luau when REDESIGN=1 is set, so redesign.py can render them.
local roblox = require("@lune/roblox")

local function rgb(r: number, g: number, b: number)
	return roblox.Color3.fromRGB(r, g, b)
end

return {
	-- THE RED WARD: a 1950s isolation wing in black and white; red only over some doors
	[2] = {
		theme = "sanatorium",
		maze = {},
		lighting = {
			Ambient = rgb(7, 7, 8),
			FogColor = rgb(4, 4, 5),
			FogStart = 0,
			FogEnd = 90,
			Saturation = -0.85,
			Contrast = 0.25,
			Brightness = 0.01,
			Tint = rgb(255, 255, 255),
			Bloom = 0.7,
			Exposure = 0.15,
			LampColor = rgb(232, 236, 245),
			Reverb = "Hallway",
		},
	},
	-- THE DROWNED TUNNELS: vaulted brick storm drains, moonlight through the grates
	[3] = {
		theme = "drain",
		maze = { WallHeight = 13, CeilingHeight = 13, DoorHeight = 9 },
		lighting = {
			Ambient = rgb(6, 6, 6),
			FogColor = rgb(3, 3, 3),
			FogStart = 10,
			FogEnd = 105,
			Saturation = -1,
			Contrast = 0.2,
			Brightness = 0.01,
			Tint = rgb(255, 255, 255),
			Bloom = 0.6,
			Exposure = 0.25,
			LampColor = rgb(255, 228, 190),
			Reverb = "SewerPipe",
		},
	},
	-- THE ATRIUM: a museum after dark; galleries under skylights, sheets over everything
	[4] = {
		theme = "gallery",
		maze = {
			CellSize = 16,
			WallHeight = 16,
			CeilingHeight = 16,
			DoorHeight = 12,
			DoorWidth = 7.5,
			Width = 11,
			Depth = 11,
			DeadEndBraid = 0.8,
			ExtraOpenings = 8,
			Openness = 0.3,
			Rooms = 2,
			LampChance = 0.85,
			LampSpacing = 2,
		},
		lighting = {
			Ambient = rgb(14, 15, 18),
			FogColor = rgb(5, 6, 8),
			FogStart = 15,
			FogEnd = 150,
			Saturation = -1,
			Contrast = 0.2,
			Brightness = 0.01,
			Tint = rgb(255, 255, 255),
			Bloom = 0.5,
			Exposure = 0.35,
			LampColor = rgb(205, 215, 235),
			Reverb = "ConcertHall",
		},
	},
	-- THE VOID: the house from night 1, coming apart in the dark
	[5] = {
		theme = "unmade",
		maze = { WallHeight = 13, CeilingHeight = 60, DoorHeight = 10 },
		lighting = {
			Ambient = rgb(6, 5, 6),
			FogColor = rgb(2, 2, 2),
			FogStart = 12,
			FogEnd = 110,
			Saturation = -0.85,
			Contrast = 0.25,
			Brightness = 0.01,
			Tint = rgb(255, 255, 255),
			Bloom = 0.6,
			Exposure = 0.2,
			LampColor = rgb(255, 236, 215),
			Reverb = "Cave",
		},
	},
}
