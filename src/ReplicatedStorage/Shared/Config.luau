--!strict
-- Every tuning knob in the game. Change a number, press Play.

local Config = {
	Maze = {
		CellSize = 12, -- studs per maze cell (corridors are CellSize - WallThickness wide)
		WallHeight = 13,
		WallThickness = 1,
		Width = 13, -- cells
		Depth = 13,
		HouseWidth = 5, -- the house blueprint is fixed at 5 x 3 cells
		HouseDepth = 3,
		DeadEndBraid = 0.35, -- chance to knock through a dead end (more loops = more ways to escape)
		ExtraOpenings = 6,
		KeyCount = 4,
		BatteryCount = 5,
		MazeLockerCount = 9,
		WritingCount = 12,
	},

	Player = {
		WalkSpeed = 10,
		SprintSpeed = 18,
		CrouchSpeed = 5,
		StaminaMax = 100,
		StaminaDrain = 16, -- per second while sprinting
		StaminaRegen = 12,
		StaminaRegenDelay = 1.2,
		BatteryDrain = 0.45, -- percent per second while the flashlight is on
		BatteryPickup = 45,
		FieldOfView = 70,
	},

	Monster = {
		WanderSpeed = 8,
		InvestigateSpeed = 12,
		SearchSpeed = 10,
		ChaseSpeed = 15.5,
		ChaseSpeedPerKey = 0.55, -- it gets faster with every key you take
		FrenzyBonus = 2, -- extra speed once the exit is open
		SightRange = 60,
		SightRangeFlashlight = 85, -- your light gives you away
		SneakSightMultiplier = 0.65, -- crouch-walking makes you harder to spot
		ViewDot = 0.3, -- field of view (dot product), ~145 degrees
		CloseSense = 14, -- it always notices you this close, even from behind
		CatchDistance = 4.5,
		LoseSightTime = 2.2,
		SearchTime = 10,
		HearSprint = 72, -- path distance (studs) a sprinting player can be heard from
		HearWalk = 26,
		AwakenAfter = 75, -- seconds; it also wakes the moment the first key is taken
		ApparitionMin = 22,
		ApparitionMax = 45,
		FrenzyTime = 25,
		HuntingInstinct = 45, -- seconds without seeing/hearing anyone before it homes in on you
	},

	Round = {
		FirstIntermission = 3,
		Intermission = 12,
		ResultsTime = 7,
	},
}

return Config
