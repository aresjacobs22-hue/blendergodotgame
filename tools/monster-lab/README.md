# Monster lab

Design sandbox for the five monsters, plus a map previewer. Each design is Luau written against the same
builder as `src/ReplicatedStorage/Shared/Monsters.luau` (parts + Motor6D joints), so a
chosen design can be pasted into the game as-is. `render.sh` builds every design with
real Roblox datatypes under Lune, dumps the parts, and renders them in Godot in each
night's lighting and color grading.

```sh
LUNE=lune GODOT=/path/to/godot tools/monster-lab/render.sh all      # renders + 5 contact sheets in out/sheets/
LUNE=lune GODOT=/path/to/godot tools/monster-lab/render.sh ward CrawlerB
```

| File | |
|---|---|
| `designs/_head.luau` | builder + helpers (ellipsoid limbs, fangs, eyes, aimed joints, spider legs) |
| `designs/<monster>.luau` | variants A, B, C for each monster |
| `dump.luau` | builds designs with Lune and writes every part to JSON |
| `render/render.gd` | Godot renderer (night moods, Roblox material approximations) |
| `post.py`, `sheet.py`, `sheets.py` | night color grading, contact sheets |
| `map_dump.luau` | builds a night's real map (WorldBuilder + Themes) in the test engine and writes parts, lights and the maze to JSON |
| `render/map_render.gd`, `maps.py` | renders each map from above, at the spawn and down a corridor (with and without the monster) |

## Maps

```sh
LUNE=lune GODOT=/path/to/godot python3 tools/monster-lab/maps.py            # all 5 nights
LUNE=lune GODOT=/path/to/godot python3 tools/monster-lab/maps.py 5 --seed 42
```

It writes `out/maps/night<N>_<view>.png`, plus `out/maps/night<N>.png` with every view on
one sheet. The renderer's light falloff is softer than Roblox's to get close to Studio, but
dark maps still come out a little darker than they look in game.

`lobby.py` renders the lobby (`map_dump.luau lobby`): a door mid-countdown, the thing in
the fog, and the circle from above, into `out/lobby/`.

`covers.py` uses the same pipeline for the Roblox art (`assets/covers/`): the Hollow's
skull face to face (icon) and the whole of it down a hallway (1920x1080 thumbnail), put
through `distort.py` (crushed blacks, a warped face and a dragged-out jaw, a stretched
neck and a bending hall, ghosting, a red channel bleed, torn scanlines, drips, pinprick
eyes, film damage).

The renders show the exact geometry. Lighting and materials are only close to what
Roblox Studio shows.

Lune's `CFrame.lookAt` doesn't match Roblox's, so designs use the `lookAt` helper in
`_head.luau`, built on `CFrame.fromMatrix`. It behaves the same in both.
