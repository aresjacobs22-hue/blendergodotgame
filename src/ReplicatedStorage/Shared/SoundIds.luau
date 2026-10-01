--!strict
-- Paste your uploaded audio asset IDs here (just the number).
--
-- How: in Roblox Studio open View > Asset Manager, click "Bulk Import" and pick the
-- three files in assets/audio/. After they finish uploading, right-click each one >
-- "Copy Asset ID" and paste the number below. See README.md for screenshots-free steps.
--
-- The game runs without these, it's just silent (and a lot less scary).

local SoundIds = {
	SFX = 0, -- ACHROMA_SFX.ogg       (every sound effect, packed into one file)
	Ambience = 0, -- ACHROMA_AMBIENCE.ogg  (60 second background drone)
	MusicBox = 0, -- ACHROMA_MUSICBOX.ogg  (title screen music box)
}

return SoundIds
