--!strict
-- Plays slices of the two sound atlases (ACHROMA_SFX: every effect; ACHROMA_AMBIENCE:
-- each night's background loop and chase music) using Sound.PlaybackRegion, plus the
-- menu's music box. Works on server and client: sounds the server plays are heard by
-- everyone, sounds a client plays are local.

local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")

local SoundAtlas = require(script.Parent.SoundAtlas)
local SoundIds = require(script.Parent.SoundIds)

local Audio = {}

local warned = false

local function warnOnce()
	if not warned then
		warned = true
		warn("[ACHROMA] Sound IDs are not set, so the game is silent. Upload assets/audio/*.ogg and paste the IDs into ReplicatedStorage.Shared.SoundIds (see README).")
	end
end

-- Every sound goes through this group so the menu's volume setting affects them.
function Audio.group(): SoundGroup?
	local group = SoundService:FindFirstChild("AchromaMaster")
	return if group and group:IsA("SoundGroup") then group else nil
end

function Audio.isConfigured(): boolean
	return SoundIds.SFX > 0
end

function Audio.duration(name: string): number
	local region = SoundAtlas[name]
	return if region then region.duration else 0
end

-- Creates (but does not play) a Sound for an atlas entry.
function Audio.create(name: string, parent: Instance?, volume: number?, speed: number?): Sound?
	local region = SoundAtlas[name]
	if not region then
		warn("[ACHROMA] unknown sound " .. name)
		return nil
	end
	if SoundIds.SFX <= 0 then
		warnOnce()
		return nil
	end
	local id = if region.file == "Ambience" then SoundIds.Ambience else SoundIds.SFX
	if id <= 0 then
		warnOnce()
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = "rbxassetid://" .. id
	sound.PlaybackRegionsEnabled = true
	sound.PlaybackRegion = NumberRange.new(region.start, region.start + region.duration)
	if region.looped then
		sound.Looped = true
		sound.LoopRegion = NumberRange.new(region.start, region.start + region.duration)
	end
	sound.Volume = volume or 0.6
	sound.PlaybackSpeed = speed or 1
	sound.SoundGroup = Audio.group()
	sound.Parent = parent or SoundService
	return sound
end

-- Fire-and-forget. With a parent part/attachment the sound is 3D, otherwise 2D.
function Audio.play(name: string, parent: Instance?, volume: number?, speed: number?, maxDistance: number?): Sound?
	local sound = Audio.create(name, parent, volume, speed)
	if not sound then
		return nil
	end
	if maxDistance then
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = math.min(10, maxDistance * 0.15)
		sound.RollOffMaxDistance = maxDistance
	end
	sound:Play()
	Debris:AddItem(sound, Audio.duration(name) / (speed or 1) + 0.5)
	return sound
end

-- 3D sound at a world position (uses a throwaway attachment on Terrain).
function Audio.playAt(name: string, position: Vector3, volume: number?, speed: number?, maxDistance: number?): Sound?
	if not Audio.isConfigured() then
		warnOnce()
		return nil
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "SoundEmitter"
	attachment.Position = position
	attachment.Parent = workspace.Terrain
	local sound = Audio.play(name, attachment, volume, speed, maxDistance or 120)
	Debris:AddItem(attachment, Audio.duration(name) / (speed or 1) + 0.6)
	return sound
end

-- The menu's music box (a full-length looping track).
function Audio.track(which: string, parent: Instance?, volume: number?): Sound?
	local id = if which == "MusicBox" then SoundIds.MusicBox else 0
	if id <= 0 then
		warnOnce()
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = which
	sound.SoundId = "rbxassetid://" .. id
	sound.Looped = true
	sound.Volume = volume or 0.5
	sound.SoundGroup = Audio.group()
	sound.Parent = parent or SoundService
	return sound
end

return Audio
