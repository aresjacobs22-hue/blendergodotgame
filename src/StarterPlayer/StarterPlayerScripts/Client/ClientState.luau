--!strict
-- Small shared blackboard so client controllers can read each other's state
-- without requiring each other.

local ClientState = {
	started = false, -- picked a night on the menu
	roundStatus = "none", -- "none" | "alive" | "caught" | "escaped"
	fear = 0, -- 0..1, how close / how angry the monster is
	monsterDistance = math.huge,
	chased = false, -- the monster is chasing *you*
	hiding = false,
	holdingBreath = false, -- hiding and holding your breath while it's close
	jumpscaring = false,
	keypadOpen = false, -- the night 2 keypad screen is up
	flashlightOn = false,
	interference = 0, -- 0..1, makes your flashlight stutter
	sprinting = false,
	crouching = false,
	brightness = 0, -- settings: added to the screen brightness
}

return ClientState
