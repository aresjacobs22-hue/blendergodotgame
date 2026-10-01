--!strict
-- Every time a night starts it rolls one curse that bends the rules. You find out
-- which one on the title card (and it stays on your HUD).

export type Curse = { id: string, name: string, text: string }

local Curses = {}

Curses.list = {
	{ id = "blackout", name = "BLACKOUT", text = "Most of the lights are dead." },
	{ id = "shifting", name = "SHIFTING WALLS", text = "The walls move. The map changes while you play." },
	{ id = "hunted", name = "HUNTED", text = "Every so often it hears your heartbeat." },
	{ id = "phantoms", name = "PHANTOMS", text = "You'll see it where it isn't." },
	{ id = "silent", name = "DEAD SILENCE", text = "It makes no sound. None at all." },
	{ id = "fog", name = "THICK FOG", text = "You can't see more than a few steps." },
} :: { Curse }

function Curses.get(id: string?): Curse?
	for _, c in Curses.list do
		if c.id == id then
			return c
		end
	end
	return nil
end

-- Curses that make sense for this monster (the Statue already knows where you are).
function Curses.allowed(monsterKind: string): { Curse }
	local out = {}
	for _, c in Curses.list do
		if not (monsterKind == "Statue" and c.id == "hunted") then
			table.insert(out, c)
		end
	end
	return out
end

function Curses.roll(monsterKind: string, random: Random): Curse
	local options = Curses.allowed(monsterKind)
	return options[random:NextInteger(1, #options)]
end

return Curses
