--!strict
-- General tuning knobs. Each night's map, monster and objective live in Nights.luau.

local Config = {
	Maze = {
		WallThickness = 1,
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

	-- Default monster behaviour. Every night overrides some of these (see Nights.luau).
	Monster = {
		WanderSpeed = 8,
		InvestigateSpeed = 12,
		SearchSpeed = 10,
		ChaseSpeed = 15.5,
		ChaseSpeedPerProgress = 0.55, -- it gets faster with every key/generator/heart/hour
		FrenzyBonus = 2, -- extra speed while it's in a frenzy
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
		HearChaseRange = 0, -- if > 0, hearing someone this close starts a chase (blind hunters)
		AwakenAfter = 75, -- seconds before it wakes on its own
		Apparitions = true, -- shows itself at the end of corridors while dormant
		ApparitionMin = 22,
		ApparitionMax = 45,
		FrenzyTime = 25,
		HuntingInstinct = 45, -- seconds without seeing/hearing anyone before it homes in on you
		LungeRange = 0, -- if > 0, it bursts forward when this close during a chase
		LungeBonus = 0,
		SenseHidden = 0, -- if > 0, it can smell players hiding within this many studs
		Statue = false, -- only moves while nobody is looking at it
		StatueSpeed = 30,
		StatueSpeedPerProgress = 1.5,
		BlinkMin = 14, -- statue nights: everyone "blinks" (lights out) every so often
		BlinkMax = 24,
		BlinkTime = 0.45,
	},

	Round = {
		ResultsTime = 9, -- black screen after a night before the lobby
	},

	Progress = {
		DataStoreName = "AchromaProgress_v1",
		UnlockAll = true, -- every night can be played from the start (progress is still saved)
		UnlockAllInStudio = true, -- with UnlockAll off: in Studio every night is still open, for testing
	},
}

return Config
