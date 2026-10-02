#!/usr/bin/env python3
"""The cover for the Roblox game page: the Hollow's skull, face to face, in the dark of
its own hallway, then put through distort.py until it's wrong.

  assets/covers/cover.png   1024x1024
  assets/covers/icon.png     512x512 (the size Roblox wants for the game icon)

  LUNE=lune GODOT=godot python3 tools/monster-lab/covers.py [--seed N]

The base render uses the same pipeline as maps.py (map_dump.luau -> render/map_render.gd)
with the real night 1 map and monster.
"""
import json, os, subprocess, sys
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import maps  # noqa: E402
from distort import distort  # noqa: E402

ROOT = maps.ROOT
WORK = os.path.join(HERE, "out", "covers")
DEST = os.path.join(ROOT, "assets", "covers")


def clear_corridor(d):
    """The longest straight, well-lit run of plain corridor (no hub, no rooms)."""
    rooms = {(c["x"], c["z"]) for block in d.get("rooms", []) for c in block}
    C = d["cellSize"]
    lamps = [l["pos"] for l in d["lights"] if l["enabled"]]
    best, best_score = None, -1
    for z in range(d["depth"]):
        for x in range(d["width"]):
            for dirn, (dx, dz) in maps.DIRS.items():
                run = [(x, z)]
                cx, cz = x, z
                while len(run) < 6 and maps.edge(d, cx, cz, dirn) in maps.PASSABLE:
                    cx, cz = cx + dx, cz + dz
                    if not (0 <= cx < d["width"] and 0 <= cz < d["depth"]):
                        break
                    run.append((cx, cz))
                if len(run) < 4 or any(maps.is_hub(d, rx, rz) or (rx, rz) in rooms for rx, rz in run):
                    continue
                lit = sum(1 for rx, rz in run for l in lamps
                          if abs(l[0] - (rx + 0.5) * C) < C * 0.7 and abs(l[2] - (rz + 0.5) * C) < C * 0.7)
                score = len(run) + lit * 2.5
                if score > best_score:
                    best, best_score = (run, dirn), score
    return best or maps.best_corridor(d)


def main():
    args = sys.argv[1:]
    seed = int(args[args.index("--seed") + 1]) if "--seed" in args else 4242
    os.makedirs(WORK, exist_ok=True)
    os.makedirs(DEST, exist_ok=True)

    # the Hollow one cell down a hallway, turned to face where you stand
    plain = maps.dump(1, seed, os.path.join(WORK, "plain.json"))
    run, dirn = clear_corridor(plain)
    dx, dz = maps.DIRS[dirn]
    C = plain["cellSize"]
    you, it = run[0], run[1]
    path = os.path.join(WORK, "skull.json")
    subprocess.run([maps.LUNE, "run", "tools/monster-lab/map_dump.luau", "1", str(seed), path,
                    f"{it[0]},{it[1]}", f"{you[0]},{you[1]}"], cwd=ROOT, check=True)
    d = json.load(open(path))
    mx, mz = (it[0] + 0.5) * C, (it[1] + 0.5) * C
    heads = [p["cf"][:3] for p in d["parts"] if p["name"] == "Head"]
    head = min(heads, key=lambda h: (h[0] - mx) ** 2 + (h[2] - mz) ** 2)

    # face to face with the skull, eight and a half studs away, the hall behind it
    cam_x, cam_z = (you[0] + 0.5 - dx * 0.45) * C, (you[1] + 0.5 - dz * 0.45) * C
    tx, tz = cam_x - head[0], cam_z - head[2]
    dist = (tx * tx + tz * tz) ** 0.5
    pos = [head[0] + tx / dist * 8.5, head[1] - 0.5, head[2] + tz / dist * 8.5]
    raw = os.path.join(WORK, "skull.png")
    view = {"name": "skull", "out": raw, "w": 1024, "h": 1024, "fov": 30, "flashlight": True,
            "lamp": 1.5, "exposure": 0.75, "pos": pos,
            "look": [head[0] - pos[0], head[1] - 0.35 - pos[1], head[2] - pos[2]]}
    json.dump([{"json": path, "views": [view]}], open(os.path.join(WORK, "jobs.json"), "w"))
    cmd = [maps.GODOT, "--rendering-method", "gl_compatibility", "--rendering-driver", "opengl3",
           "--path", os.path.join(HERE, "render"), "-s", "map_render.gd", "--", os.path.join(WORK, "jobs.json")]
    if not os.environ.get("DISPLAY"):
        cmd = ["xvfb-run", "-a", "-s", "-screen 0 1280x720x24"] + cmd
    p = subprocess.run(cmd, capture_output=True, text=True)
    for line in p.stdout.splitlines() + p.stderr.splitlines():
        if "SCRIPT ERROR" in line:
            print(line)

    cover = distort(raw, 1024)
    cover.save(os.path.join(DEST, "cover.png"))
    cover.resize((512, 512), Image.LANCZOS).save(os.path.join(DEST, "icon.png"))
    print("wrote assets/covers/cover.png, assets/covers/icon.png")


if __name__ == "__main__":
    main()
