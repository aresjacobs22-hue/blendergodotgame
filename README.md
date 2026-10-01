# ACHROMA

A black-and-white Roblox horror game. You wake up in a grey house. It connects to a maze of
dark corridors, and something tall is walking around in them.

**Find the 4 keys** out in the maze. Each key has a tag with **one number** on it. Bring them
back, unlock the 4 padlocks on the exit door in the hall, type the 4-digit code on the keypad,
and run into the light. Don't let it see you.

- A new random maze every round (the house is always the same)
- A ~10 stud monster with arms that drag on the floor and a jaw that hangs open. It twitches
  instead of walking, and it **sees** you (more easily with your light on) and **hears** you running
- It shows up at the end of your corridor, stares, and vanishes before it fully wakes up
- Hide in lockers and wardrobes. If it **watched you get in**, it pulls you out
- Flashlight with a battery, stamina, crouch-sneaking, flickering lamps, heartbeat, jumpscare
- 1-6 players. Caught players spectate the survivors
- Every sound is generated from code (`tools/generate_audio.py`), so nothing is copyrighted

## Play it in 3 steps

### 1. Open the game in Roblox Studio

Download **`build/ACHROMA.rbxlx`** from this repo. In Roblox Studio go to **File → Open from
File…**, pick it, then press **Play** (F5).

The game works right away, but it's **silent** until you do step 2. In Studio you'll see a
small "Audio IDs not set" reminder in the top-left corner.

### 2. Add the sounds (do this, it's way scarier)

Roblox doesn't allow sounds inside a place file, so you upload them once:

1. Upload the 3 files in **`assets/audio/`**:
   - `ACHROMA_SFX.ogg` (every sound effect, packed into one file)
   - `ACHROMA_AMBIENCE.ogg` (the background drone)
   - `ACHROMA_MUSICBOX.ogg` (the title screen music box)

   Either use **Studio → Asset Manager → Bulk Import** (the Asset Manager is under the
   *View* or *Window* menu, depending on your Studio version), or use
   [create.roblox.com](https://create.roblox.com) → *Creations* → *Development Items* →
   *Audio* → *Upload Asset*. Uploading audio is free. Accounts without ID verification get
   about 10 audio uploads a month, and this only needs 3.
2. Wait a few minutes for Roblox to approve them. Then copy each one's **asset ID** (the
   number in its URL, or right-click → *Copy Asset ID* in the Asset Manager).
3. In Studio's Explorer open **ReplicatedStorage → Shared → SoundIds** and paste the numbers:

   ```lua
   local SoundIds = {
       SFX = 1234567890,       -- ACHROMA_SFX.ogg
       Ambience = 1234567891,  -- ACHROMA_AMBIENCE.ogg
       MusicBox = 1234567892,  -- ACHROMA_MUSICBOX.ogg
   }
   ```

> If you publish the game under a **group**, upload the audio to that group too, or Roblox
> won't let the game play it.

### 3. Publish

**File → Publish to Roblox**. In **Game Settings → Places**, set *Max Players* to 1 for
solo, or up to 6 for co-op.

## Controls

| | Keyboard | Gamepad | Phone |
|---|---|---|---|
| Move / look | WASD + mouse | sticks | thumbstick + drag |
| Run | Shift (hold) | L3 | RUN button |
| Crouch (silent) | C or Ctrl | B | CROUCH button |
| Flashlight | F | Y | LIGHT button |
| Interact / hide | E | X | tap the prompt |
| Leave a hiding spot | E | X | LEAVE button |

## How the monster works (so you can survive it)

- It **wakes up** when someone takes the first key, or after 75 seconds anyway. Before that it
  only *appears*: at the end of a corridor, staring.
- **Sight:** about 60 studs, or 85 if your flashlight is on. Crouch-walking makes you harder to
  spot. Up close it notices you even from behind.
- **Hearing:** running carries about 70 studs through the corridors, walking about 26, and
  crouching makes no sound at all. Shutting doors, taking keys, and typing a **wrong code**
  are all loud.
- **Chasing:** it screams, then runs at you. It gets faster with every key you take. Lose it by
  breaking line of sight, or hide. But if it **saw** you climb into a locker, it comes and pulls
  you out.
- If it hears nothing for too long, it starts **hunting**: it heads straight for where you are.
- When the exit opens it goes into a **frenzy** and knows where everyone is.
- Lamps flicker and die when it's close, your flashlight stutters, and you'll hear clicking.

## Change the game

Everything you'd want to tweak is in **`ReplicatedStorage → Shared → Config`**: maze size, how
many keys, monster speeds, sight and hearing ranges, stamina, battery life, round timers.

| Where | What |
|---|---|
| `src/ReplicatedStorage/Shared/Config.luau` | all the tuning numbers |
| `src/ReplicatedStorage/Shared/SoundIds.luau` | your uploaded audio IDs |
| `src/ReplicatedStorage/Shared/Maze.luau` | maze generator (house layout, key/locker/lamp placement) |
| `src/ServerScriptService/Server/RoundManager.luau` | round loop: countdown → night → results |
| `src/ServerScriptService/Server/WorldBuilder.luau` | builds the house + maze out of Parts |
| `src/ServerScriptService/Server/Interactables.luau` | doors, keys, batteries, lockers, notes, exit, keypad |
| `src/ServerScriptService/Server/MonsterRig.luau` | the monster's body |
| `src/ServerScriptService/Server/MonsterAI.luau` | the monster's brain |
| `src/StarterPlayer/StarterPlayerScripts/Client/` | everything on screen: HUD, menus, flashlight, fear effects, monster animation, jumpscare |
| `tools/generate_audio.py` | synthesizes every sound (`python3 tools/generate_audio.py`, needs numpy + ffmpeg) |

## For developers (Rojo)

This is a [Rojo](https://rojo.space) project. Tool versions are pinned in `rokit.toml`
(`rokit install`).

```sh
rojo serve                                         # live-sync into Studio with the Rojo plugin
rojo build default.project.json -o build/ACHROMA.rbxlx   # rebuild the place file
./tools/check.sh                                   # type-check + all tests + build
```

`tools/check.sh` runs:

- **luau-lsp** strict type checking against the Roblox API
- `tests/maze.spec.luau`: 300 random mazes. Every cell is reachable, keys are spread out,
  lockers sit against real walls.
- `tests/sim.spec.luau`: the real server code in a mocked engine. Covers apparitions, waking
  up, hunting a player down, never walking through walls, the locker pull-out, a hidden
  player surviving, and keys → padlocks → code → exit → escape.
- `tests/e2e.spec.luau`: the real server and client together. A fake player clicks WAKE UP,
  uses the flashlight and sprint, picks up the keys, types the code on the on-screen keypad
  and escapes. The next night they hide, get caught and get jumpscared, and the round loop
  starts over.

These tests run outside Roblox, so they can't catch rendering or physics problems.
Playtest in Studio before you publish.
