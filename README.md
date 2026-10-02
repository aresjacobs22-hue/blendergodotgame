# ACHROMA

A Roblox horror game: **five nights, five maps, five monsters**. Each night has its own
look, its own monster and its own objective. Beat one to unlock the next. Your progress
is saved.

**The game never explains itself.** The menu is a black screen with five lines, NIGHT 1
to NIGHT 5. A night starts with its number on black, and then you're just there. No
objectives on screen, no messages, no tutorials, no "you died" screen. Everything below is
for you, not the player: players find it out (or read it on the game page, see
[Game page description](#game-page-description)).

| Night | Map | Monster | Objective |
|---|---|---|---|
| 1 | **The House**: a black-and-white house inside a concrete maze, with a dining room laid for nobody, a nursery and a bathroom with a full tub | **The Hollow**: starved and black, with a deer skull for a head and arms that drag on the floor. It sees your light and hears you run | Survive from 12 AM until **6 AM** |
| 2 | **The Red Ward**: a hospital in red emergency light, with an operating theatre, a morgue and plastic strip curtains | **The Crawler**: a patient bent over backwards on all fours, four arms too many. Fast, and it **lunges** | Find **4 keys** (each tag shows one digit), unlock the exit, type the code |
| 3 | **The Drowned Tunnels**: flooded brick tunnels with a dead pump station and a pillared cistern. Pitch black, no power | **The Listener**: blind. Its head **splits open** when it hears you | Start **3 generators** (loud!) to turn the lights back on, then ride the lift out |
| 4 | **The Atrium**: a marble hall full of statues, reflecting pools and moonlight through the skylights | **The Statue**: the **Mourner** or the **Saint** (a different one each time). It only moves when **nobody is looking**. Some statues are just statues | Collect **6 photographs** |
| 5 | **The Void**: black glass in near darkness, crystal lamps, and rooms that remember the earlier nights | **The Amalgam**: three heads, six arms, a glowing heart in its ribs. It can smell you through a locker door | Destroy **3 hearts** (it knows each time), then run for the portal |

**Every night is different**:

- **A curse**: every time you start a night it rolls one. Nobody tells you which.
  | Curse | What happens |
  |---|---|
  | **Blackout** | most of the lamps are dead |
  | **Shifting Walls** | walls rise out of the floor and sink back. The map changes while you play (it never traps you) |
  | **Hunted** | every so often it hears your heartbeat and comes straight for you |
  | **Phantoms** | you see it standing down the corridor. It isn't there |
  | **Dead Silence** | it makes no sound at all: no footsteps, no growl, no scream |
  | **Thick Fog** | you can't see more than a few steps |
- **Random events** about once a minute: the **power fails**; a **phone rings** near you
  (answer it: a voice, then a whisper from wherever the monster is, though sometimes the
  voice lies; ignore it and the monster goes to answer it); **every door slams shut**; a
  **locker bangs** by itself; or you hear it **charge at you** when nothing's there.
- **The rage**: when the way out opens (or at 5 AM on night 1) it gets **furious**. The
  lights turn red and it knows where you are for a while.
- **Bottles** lie around the map. Pick up to 3, throw one (**G**) and the monster goes to
  where it smashed. The Listener can't resist.
- **Hold your breath** in a locker (**SPACE**) when it's right outside the door. Run out of
  breath, or forget, and it hears you.
- **Every night sounds different**: its own ambience loop and its own chase music, plus
  map-specific noises (gurneys and intercoms in the ward, dripping pipes in the tunnels,
  a choir in the atrium, heartbeats in the void).

Also in the game:

- **The menu**: NIGHT 1 to NIGHT 5 on black. Nights you haven't reached are barely
  visible; a night you just unlocked surfaces slowly. The small ring in the corner opens
  brightness and volume. Every so often, for a moment, there's a sixth night.
- **What's on screen while you play**: a few faint dots at the top that light up as you
  get further (the hours on night 1, keys, generators, photographs, hearts), five faint
  ticks for your flashlight battery, a mark for each bottle you carry, and a thin line
  for your breath while you hide. Things you can use show a small dot with the key to
  press. That's all.
- **A new random map every time** you play a night.
- **Flashlight** with a battery, **stamina**, **crouch-sneaking**, and **lockers** to hide in.
- **Atmosphere**: flickering lamps, a heartbeat, jumpscares, a clock that chimes the
  hours, short scrawls on the walls that only show under your flashlight, and papers left
  lying around with nothing left on them.
- **The keypad remembers**: on night 2 it faintly shows the digits from the keys you
  picked up, so you never have to read anything.
- **1-6 players**: caught players watch the survivors, and if anyone makes it out, everyone
  unlocks the next night.
- **Every sound is generated by code** (`tools/generate_audio.py`): nothing copyrighted.

## Play it in 3 steps

### 1. Open the game in Roblox Studio

Download **`build/ACHROMA.rbxlx`**. In Roblox Studio go to **File → Open from File…**,
pick it, then press **Play** (F5).

In Studio **all 5 nights are unlocked**, so you can test any of them. In the published game
players start with only Night 1. To change this, set `UnlockAllInStudio = false` in
`Config`.

The game is **silent** until you do step 2.

### 2. Add the sounds (do this, it's way scarier)

Roblox doesn't allow sounds inside a place file, so you upload them once:

1. Upload the 3 files in **`assets/audio/`**:
   - `ACHROMA_SFX.ogg` (every sound effect, packed into one file)
   - `ACHROMA_AMBIENCE.ogg` (each night's ambience and chase music, packed into one file)
   - `ACHROMA_MUSICBOX.ogg` (the menu music box)

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

> **Already uploaded the sounds before?** All three files have changed (new sounds for the
> curses, events and bottles, and the ambience file now holds 10 tracks instead of one), so
> upload all three again and paste the new IDs. The old IDs will play the wrong slices.
>
> If you publish the game under a **group**, upload the audio to that group too, or Roblox
> won't let the game play it.

### 3. Publish (and turn on saving)

1. **File → Publish to Roblox**.
2. In **Game Settings → Places**, set *Max Players* (1 for solo, up to 6 for co-op).
3. In **Game Settings → Security**, turn on **Enable Studio Access to API Services**. Saving
   progress uses DataStores. In a published game it works automatically; that toggle only
   makes it work while you test in Studio.

## Game page description

The game itself never tells anyone the controls, so put them on the Roblox game page.
Something like:

```
Five nights. Don't let it find you.

WASD move · SHIFT run · C crouch · F flashlight · E use / hide
G throw a bottle · SPACE (in a locker) hold your breath
```

### Cover images

`assets/covers/` has the store art, rendered from the real maps and monsters:

- `icon.png` (512×512): the game icon.
- `thumb_title.png` and `thumb_night1.png` … `thumb_night5.png` (1920×1080): thumbnails.

Upload them at [create.roblox.com](https://create.roblox.com) → your experience →
*Configure* → *Places* / *Basic Info* (the icon) and *Thumbnails*. To render them again
(after changing a map or a monster): `LUNE=lune GODOT=godot python3 tools/monster-lab/covers.py`.

## Controls

| | Keyboard | Gamepad | Phone |
|---|---|---|---|
| Move / look | WASD + mouse | sticks | thumbstick + drag |
| Run | Shift (hold) | L3 | RUN button |
| Crouch (silent) | C or Ctrl | B | CROUCH button |
| Flashlight | F | Y | LIGHT button |
| Interact / hide | E (hold for some things) | X | tap the prompt |
| Leave a hiding spot | E | X | LEAVE button |
| Hold your breath (in a locker) | Space (hold) | R2 (hold) | HOLD BREATH button |
| Throw a bottle | G | D-pad up | THROW button |

## Change the game

| Where | What |
|---|---|
| `src/ReplicatedStorage/Shared/Nights.luau` | **each night**: map size, objective, monster tuning, lighting/colors, flashlight |
| `src/ReplicatedStorage/Shared/Config.luau` | player speed, stamina, battery, default monster behavior, round timers |
| `src/ReplicatedStorage/Shared/Monsters.luau` | the five monster bodies |
| `src/ReplicatedStorage/Shared/Curses.luau` | the curse list (names and descriptions) |
| `src/ReplicatedStorage/Shared/SoundIds.luau` | your uploaded audio IDs |
| `src/ReplicatedStorage/Shared/Maze.luau` | the maze generator (hubs, rooms, open halls, item placement) |
| `src/ServerScriptService/Server/Themes.luau` | **each map's look**: materials, lamps, props, wall writing |
| `src/ServerScriptService/Server/Dressing.luau` | furniture and the special rooms (dining room, morgue, cistern, ...) |
| `src/ServerScriptService/Server/Chaos.luau` | what each curse does, the random events, the rage, breath-holding |
| `src/ServerScriptService/Server/Throwables.luau` | the bottles |
| `src/ServerScriptService/Server/Objectives.luau` | survive / keys / generators / photographs / hearts (and their progress dots) |
| `src/ServerScriptService/Server/MonsterAI.luau` | the monsters' brains (sight, hearing, lunges, statue rules, ...) |
| `src/ServerScriptService/Server/RoundManager.luau` | menu → countdown → night → results loop |
| `src/ServerScriptService/Server/Progress.luau` | saving which nights you've unlocked |
| `src/StarterPlayer/StarterPlayerScripts/Client/` | everything on screen: menu, HUD, wordless prompts, flashlight, fear effects, monster animation, jumpscares |
| `tools/generate_audio.py` | synthesizes every sound (`python3 tools/generate_audio.py`, needs numpy + ffmpeg) |
| `tools/monster-lab/` | renders the monsters and the maps to PNGs with Godot, for checking designs without opening Studio |

## For developers (Rojo)

This is a [Rojo](https://rojo.space) project. Tool versions are pinned in `rokit.toml`
(`rokit install`).

```sh
rojo serve                                              # live-sync into Studio with the Rojo plugin
rojo build default.project.json -o build/ACHROMA.rbxlx  # rebuild the place file
./tools/check.sh                                        # type-check + all tests + build
```

`tools/check.sh` runs:

- **luau-lsp** strict type checking against the Roblox API
- `tests/maze.spec.luau`: 120 random maps for each night. Every cell is reachable,
  objectives are spread out, lockers and writing sit on real walls.
- `tests/sim.spec.luau`: the real server code in a mocked engine, covering all 5 maps and
  all 5 objectives. It checks each monster's special behavior: the Hollow hunts down a
  player who stands still, the Crawler lunges, the Listener ignores a silent player but
  follows a sprinting one, the Statue freezes while watched and moves when you look away,
  and the Amalgam smells players hiding nearby. It also covers the chaos: every night rolls
  varied curses, shifting walls never cut off part of the map (and the monster never walks
  through them), each random event works, opening the exit triggers the rage, a thrown
  bottle draws the monster, and gasping in a locker gives you away only when it's close.
- `tests/e2e.spec.luau`: the real server and client together. A fake player plays the whole
  game through the menu: survives night 1 in a locker (holding its breath whenever the
  monster comes past), unlocks and beats nights 2-5 (keys
  and the keypad screen, generators, photographs, hearts), then gets caught on night 1 for
  the jumpscare. At every step it reads everything on screen and fails if any words
  other than "NIGHT 1".."NIGHT 5" show up.

These tests run outside Roblox, so they can't judge rendering, physics or how scary it
feels. Playtest in Studio before you publish.
