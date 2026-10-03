--!strict
-- The five nights: map, vibe, monster and objective for each. This is the file to
-- edit if you want to rebalance a night.

local Config = require(script.Parent.Config)

export type MazeParams = {
	CellSize: number,
	WallHeight: number,
	CeilingHeight: number,
	DoorHeight: number,
	DoorWidth: number?, -- default 5.5
	Width: number,
	Depth: number,
	Hub: string, -- "house" (fixed 5x3 blueprint) or "hall" (one open room)
	HubWidth: number,
	HubDepth: number,
	DeadEndBraid: number,
	ExtraOpenings: number,
	Openness: number, -- fraction of the remaining inner walls knocked down (open halls)
	Rooms: number, -- 2x2 rooms carved into the maze
	RoomDoors: boolean,
	SpotCount: number, -- objective items (keys, generators, photos, hearts)
	BatteryCount: number,
	LockerCount: number,
	LampChance: number,
	LampSpacing: number,
	WritingCount: number,
}

export type Lighting = {
	Ambient: Color3,
	FogColor: Color3,
	FogStart: number,
	FogEnd: number,
	Saturation: number,
	Contrast: number,
	Brightness: number,
	Tint: Color3,
	Bloom: number,
	Exposure: number,
	LampColor: Color3,
	Reverb: string,
}

-- Your flashlight on this night (dark maps get a stronger one).
export type FlashlightSettings = {
	brightness: number,
	range: number, -- studs
	angle: number, -- degrees
}

export type Night = {
	index: number,
	id: string,
	name: string,
	objective: string, -- "survive" | "keys" | "power" | "collect" | "hearts"
	goal: string, -- what you have to do, in red at the door and before the night starts
	objectiveCount: number,
	surviveSeconds: number?, -- survive nights: real seconds from 12 AM to 6 AM
	theme: string,
	monsterKind: string,
	monster: { [string]: any }, -- overrides for Config.Monster
	maze: MazeParams,
	lighting: Lighting,
	flashlight: FlashlightSettings?, -- defaults to NightsModule.DEFAULT_FLASHLIGHT
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local Nights: { Night } = {
	{
		index = 1,
		id = "house",
		name = "THE HOUSE",
		objective = "survive",
		goal = "SURVIVE UNTIL 6 AM",
		objectiveCount = 6,
		surviveSeconds = 300,
		theme = "house",
		monsterKind = "Hollow",
		monster = {
			ChaseSpeed = 14.5,
			ChaseSpeedPerProgress = 0.45,
			AwakenAfter = 45,
		},
		maze = {
			CellSize = 12,
			WallHeight = 13,
			CeilingHeight = 13,
			DoorHeight = 10,
			Width = 11,
			Depth = 11,
			Hub = "house",
			HubWidth = 5,
			HubDepth = 3,
			DeadEndBraid = 0.35,
			ExtraOpenings = 5,
			Openness = 0,
			Rooms = 3,
			RoomDoors = true,
			SpotCount = 0,
			BatteryCount = 4,
			LockerCount = 7,
			LampChance = 0.6,
			LampSpacing = 3,
			WritingCount = 10,
		},
		lighting = {
			Ambient = rgb(5, 5, 5),
			FogColor = rgb(3, 3, 3),
			FogStart = 5,
			FogEnd = 95,
			Saturation = -1,
			Contrast = 0.22,
			Brightness = 0.01,
			Tint = rgb(255, 255, 255),
			Bloom = 0.7,
			Exposure = 0.15,
			LampColor = rgb(255, 240, 220),
			Reverb = "StoneCorridor",
		},
	},
	{
		index = 2,
		id = "ward",
		name = "THE RED WARD",
		objective = "keys",
		goal = "FIND THE FOUR KEYS AND ESCAPE",
		objectiveCount = 4,
		theme = "sanatorium",
		monsterKind = "Crawler",
		monster = {
			WanderSpeed = 10,
			InvestigateSpeed = 14,
			SearchSpeed = 12,
			ChaseSpeed = 16.5,
			ChaseSpeedPerProgress = 0.4,
			SightRange = 52,
			SightRangeFlashlight = 70,
			ViewDot = 0.45,
			LoseSightTime = 1.6,
			LungeRange = 16,
			LungeBonus = 9,
			AwakenAfter = 60,
		},
		maze = {
			CellSize = 12,
			WallHeight = 12,
			CeilingHeight = 12,
			DoorHeight = 9.5,
			Width = 13,
			Depth = 13,
			Hub = "hall",
			HubWidth = 3,
			HubDepth = 2,
			DeadEndBraid = 0.4,
			ExtraOpenings = 6,
			Openness = 0,
			Rooms = 6,
			RoomDoors = true,
			SpotCount = 4,
			BatteryCount = 4,
			LockerCount = 8,
			LampChance = 0.7,
			LampSpacing = 3,
			WritingCount = 12,
		},
		lighting = {
			Ambient = rgb(7, 7, 8),
			FogColor = rgb(4, 4, 5),
			FogStart = 0,
			FogEnd = 90,
			Saturation = -0.85, -- almost black and white: only the red door lamps show
			Contrast = 0.25,
			Brightness = 0.01,
			Tint = rgb(255, 255, 255),
			Bloom = 0.7,
			Exposure = 0.15,
			LampColor = rgb(232, 236, 245),
			Reverb = "Hallway",
		},
	},
	{
		index = 3,
		id = "sewer",
		name = "THE DROWNED TUNNELS",
		objective = "power",
		goal = "START THE THREE GENERATORS AND ESCAPE",
		objectiveCount = 3,
		theme = "drain",
		monsterKind = "Listener",
		monster = {
			WanderSpeed = 7,
			InvestigateSpeed = 15,
			SearchSpeed = 9,
			ChaseSpeed = 16,
			ChaseSpeedPerProgress = 0.5,
			SightRange = 0,
			SightRangeFlashlight = 0,
			CloseSense = 5,
			HearWalk = 40,
			HearSprint = 120,
			HearChaseRange = 30,
			LoseSightTime = 3,
			SearchTime = 14,
			AwakenAfter = 40,
			Apparitions = false,
		},
		maze = {
			CellSize = 13,
			WallHeight = 13,
			CeilingHeight = 13,
			DoorHeight = 9,
			Width = 13,
			Depth = 13,
			Hub = "hall",
			HubWidth = 3,
			HubDepth = 2,
			DeadEndBraid = 0.3,
			ExtraOpenings = 4,
			Openness = 0,
			Rooms = 2,
			RoomDoors = false,
			SpotCount = 3,
			BatteryCount = 7,
			LockerCount = 8,
			LampChance = 0.75,
			LampSpacing = 3,
			WritingCount = 10,
		},
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
		flashlight = { brightness = 5, range = 72, angle = 54 },
	},
	{
		index = 4,
		id = "atrium",
		name = "THE ATRIUM",
		objective = "collect",
		goal = "FIND THE SIX PHOTOGRAPHS",
		objectiveCount = 6,
		theme = "gallery",
		monsterKind = "Statue",
		monster = {
			Statue = true,
			StatueSpeed = 28,
			StatueSpeedPerProgress = 1.6,
			CatchDistance = 4.5,
			AwakenAfter = 12,
			Apparitions = false,
		},
		maze = {
			CellSize = 16,
			WallHeight = 16,
			CeilingHeight = 16,
			DoorHeight = 12,
			DoorWidth = 7.5, -- wide gallery doorways
			Width = 11,
			Depth = 11,
			Hub = "hall",
			HubWidth = 3,
			HubDepth = 2,
			DeadEndBraid = 0.8,
			ExtraOpenings = 8,
			Openness = 0.3,
			Rooms = 2,
			RoomDoors = false,
			SpotCount = 6,
			BatteryCount = 2,
			LockerCount = 0,
			LampChance = 0.85,
			LampSpacing = 2,
			WritingCount = 8,
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
	{
		index = 5,
		id = "void",
		name = "THE VOID",
		objective = "hearts",
		goal = "DESTROY THE THREE HEARTS AND ESCAPE",
		objectiveCount = 3,
		theme = "unmade",
		monsterKind = "Amalgam",
		monster = {
			WanderSpeed = 9,
			InvestigateSpeed = 13,
			SearchSpeed = 11,
			ChaseSpeed = 16,
			ChaseSpeedPerProgress = 0.7,
			SightRange = 70,
			SightRangeFlashlight = 95,
			HearWalk = 30,
			HearSprint = 85,
			SenseHidden = 12,
			FrenzyBonus = 2.5,
			AwakenAfter = 30,
			HuntingInstinct = 35,
		},
		maze = {
			CellSize = 13,
			WallHeight = 13,
			CeilingHeight = 60,
			DoorHeight = 10,
			Width = 13,
			Depth = 13,
			Hub = "hall",
			HubWidth = 3,
			HubDepth = 3,
			DeadEndBraid = 0.5,
			ExtraOpenings = 10,
			Openness = 0.08,
			Rooms = 3,
			RoomDoors = false,
			SpotCount = 3,
			BatteryCount = 5,
			LockerCount = 6,
			LampChance = 0.45,
			LampSpacing = 3,
			WritingCount = 12,
		},
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
		flashlight = { brightness = 5, range = 72, angle = 54 },
	},
}

local NightsModule = {}
NightsModule.list = Nights
NightsModule.count = #Nights
NightsModule.DEFAULT_FLASHLIGHT = { brightness = 2.6, range = 48, angle = 46 } :: FlashlightSettings

function NightsModule.get(index: number): Night
	return Nights[math.clamp(math.floor(index), 1, #Nights)]
end

function NightsModule.flashlight(night: Night): FlashlightSettings
	return night.flashlight or NightsModule.DEFAULT_FLASHLIGHT
end

-- Config.Monster defaults with this night's overrides on top.
function NightsModule.monsterParams(night: Night): { [string]: any }
	local params: { [string]: any } = table.clone(Config.Monster) :: any
	for k, v in night.monster do
		params[k] = v
	end
	return params
end

return NightsModule
