#!/usr/bin/env python3
"""Art for the Roblox game page, put through distort.py until it's wrong:

  assets/covers/cover.png      1024x1024 the Hollow's skull, face to face, in the dark
  assets/covers/icon.png        512x512  the same, at the size Roblox wants for the icon
  assets/covers/thumbnail.png  1920x1080 the whole of it, too tall, at the end of a black
                                         hallway (the experience page thumbnail)

  LUNE=lune GODOT=godot python3 tools/monster-lab/covers.py [--seed N]

The base render uses the same pipeline as maps.py (map_dump.luau -> render/map_render.gd)
with the real night 1 map and monster.
"""
import json, math, os, subprocess, sys
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


def project(p, cam, look, fov, w, h):
    """Where a world point lands in the picture (fractions of width/height). The camera
    is Godot's: vertical field of view, Y up."""
    f = [look[i] / math.sqrt(sum(v * v for v in look)) for i in range(3)]
    right = [-f[2], 0.0, f[0]]  # forward x up
    rn = math.sqrt(sum(v * v for v in right))
    right = [v / rn for v in right]
    up = [right[1] * f[2] - right[2] * f[1], right[2] * f[0] - right[0] * f[2], right[0] * f[1] - right[1] * f[0]]
    v = [p[i] - cam[i] for i in range(3)]
    x, y, z = (sum(v[i] * right[i] for i in range(3)), sum(v[i] * up[i] for i in range(3)), sum(v[i] * f[i] for i in range(3)))
    t = math.tan(math.radians(fov) / 2)
    return 0.5 + x / (z * t * (w / h)) / 2, 0.5 - y / (z * t) / 2


def render(jobs):
    json.dump(jobs, open(os.path.join(WORK, "jobs.json"), "w"))
    cmd = [maps.GODOT, "--rendering-method", "gl_compatibility", "--rendering-driver", "opengl3",
           "--path", os.path.join(HERE, "render"), "-s", "map_render.gd", "--", os.path.join(WORK, "jobs.json")]
    if not os.environ.get("DISPLAY"):
        cmd = ["xvfb-run", "-a", "-s", "-screen 0 1280x720x24"] + cmd
    p = subprocess.run(cmd, capture_output=True, text=True)
    for line in p.stdout.splitlines() + p.stderr.splitlines():
        if "SCRIPT ERROR" in line:
            print(line)


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
    jobs = [{"json": path, "views": [view]}]

    # the thumbnail: two cells further down the same hall, all of it, facing you
    far = run[min(2, len(run) - 1)]
    tpath = os.path.join(WORK, "hall.json")
    subprocess.run([maps.LUNE, "run", "tools/monster-lab/map_dump.luau", "1", str(seed), tpath,
                    f"{far[0]},{far[1]}", f"{you[0]},{you[1]}"], cwd=ROOT, check=True)
    td = json.load(open(tpath))
    fx_, fz_ = (far[0] + 0.5) * C, (far[1] + 0.5) * C
    theads = [p["cf"][:3] for p in td["parts"] if p["name"] == "Head"]
    thead = min(theads, key=lambda h: (h[0] - fx_) ** 2 + (h[2] - fz_) ** 2)
    eyes = sorted((p["cf"][:3] for p in td["parts"] if p["name"] == "Eye"),
                  key=lambda e: (e[0] - thead[0]) ** 2 + (e[1] - thead[1]) ** 2 + (e[2] - thead[2]) ** 2)[:2]
    tcam = [cam_x, 5.0, cam_z]
    tlook = [fx_ - cam_x, 6.2 - 5.0, fz_ - cam_z]
    traw = os.path.join(WORK, "hall.png")
    jobs.append({"json": tpath, "views": [{"name": "hall", "out": traw, "w": 1920, "h": 1080, "fov": 42,
                                            "flashlight": True, "lamp": 1.5, "exposure": 0.9,
                                            "pos": tcam, "look": tlook}]})
    render(jobs)

    cover = distort(raw, 1024)
    cover.save(os.path.join(DEST, "cover.png"))
    cover.resize((512, 512), Image.LANCZOS).save(os.path.join(DEST, "icon.png"))

    # the thumbnail: the same treatment, plus a neck that's too long and a hall that bends
    # in around it, and almost everything below the skull lost in the dark
    hx, hy = project(thead, tcam, tlook, 42, 1920, 1080)
    (e1x, e1y), (e2x, e2y) = (project(e, tcam, tlook, 42, 1920, 1080) for e in eyes)
    distort(traw, (1920, 1080),
            focus=(hx, hy + 0.14),
            eyes=[(e1x, e1y, 2.4), (e2x, e2y, 1.9)],
            twist=0.12, twist_radius=0.35,
            jaw={"start": hy + 0.03, "length": 0.1, "width": 0.012, "amount": 0.045},
            neck={"shoulders": hy + 0.08, "head": hy, "amount": 0.08, "width": 0.05},
            barrel=0.35, light=0.42, drips_from=0.62).save(os.path.join(DEST, "thumbnail.png"))
    print("wrote assets/covers/cover.png, icon.png, thumbnail.png")


if __name__ == "__main__":
    main()
