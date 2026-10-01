# Monster lab

Design sandbox for the five monsters. Each design is Luau written against the same
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

The renders show the exact geometry. Lighting and materials are only close to what
Roblox Studio shows.

Lune's `CFrame.lookAt` doesn't match Roblox's, so designs use the `lookAt` helper in
`_head.luau`, built on `CFrame.fromMatrix`. It behaves the same in both.
