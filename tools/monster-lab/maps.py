#!/usr/bin/env python3
"""Renders each night's map: an overview from above, the spawn, and a corridor
(with and without the monster in it). Uses the real map generator via Lune.

  LUNE=lune GODOT=godot python3 tools/monster-lab/maps.py [night ...] [--seed N]
Writes out/maps/night<N>_<view>.png and out/maps/night<N>.png (all views on one sheet).
"""
import json, os, subprocess, sys
from PIL import Image, ImageDraw, ImageFont, ImageEnhance
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(HERE, "out", "maps")
LUNE = os.environ.get("LUNE", "lune")
GODOT = os.environ.get("GODOT", "godot")
PASSABLE = {"open", "door", "doorway", "hole"}
DIRS = {"N": (0, 1), "E": (1, 0), "S": (0, -1), "W": (-1, 0)}
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"


def dump(night, seed, path, monster=None):
    args = [LUNE, "run", "tools/monster-lab/map_dump.luau", str(night), str(seed), path]
    if monster:
        args.append(f"{monster[0]},{monster[1]}")
    subprocess.run(args, cwd=ROOT, check=True)
    return json.load(open(path))


def edge(d, x, z, dirn):
    if dirn == "N":
        k = f"{x},{z},N"
    elif dirn == "E":
        k = f"{x},{z},E"
    elif dirn == "S":
        k = f"{x},{z - 1},N"
    else:
        k = f"{x - 1},{z},E"
    return d["edges"].get(k, "wall")


def is_hub(d, x, z):
    h = d["hub"]
    return h["x0"] <= x < h["x0"] + h["w"] and h["z0"] <= z < h["z0"] + h["d"]


def best_corridor(d):
    C = d["cellSize"]
    lamps = [l["pos"] for l in d["lights"] if l["enabled"]]
    best, best_score = None, -1
    for z in range(d["depth"]):
        for x in range(d["width"]):
            if is_hub(d, x, z):
                continue
            for dirn, (dx, dz) in DIRS.items():
                run = [(x, z)]
                cx, cz = x, z
                while len(run) < 6 and edge(d, cx, cz, dirn) in PASSABLE:
                    cx, cz = cx + dx, cz + dz
                    if not (0 <= cx < d["width"] and 0 <= cz < d["depth"]) or is_hub(d, cx, cz):
                        break
                    run.append((cx, cz))
                if len(run) < 4:
                    continue
                lit = 0
                for (rx, rz) in run:
                    px, pz = (rx + 0.5) * C, (rz + 0.5) * C
                    lit += sum(1 for l in lamps if abs(l[0] - px) < C * 0.7 and abs(l[2] - pz) < C * 0.7)
                score = len(run) + lit * 2.5
                if score > best_score:
                    best, best_score = (run, dirn), score
    return best


def views(d, corridor, night):
    C = d["cellSize"]
    W, D = d["width"] * C, d["depth"] * C
    cx, cz = W / 2, D / 2
    span = max(W, D)
    out = [{"name": "overview", "overview": True, "w": 900, "h": 640, "fov": 50,
            "pos": [cx, span * 1.05, -span * 0.25], "look": [0, -span * 1.05, cz + span * 0.25], "moon": 0.6, "lamp": 1.5}]
    sp = d["spawns"][0]
    out.append({"name": "spawn", "w": 600, "h": 400, "fov": 70, "pos": [sp["pos"][0], sp["pos"][1] + 1.3, sp["pos"][2]],
                "look": sp["look"], "flashlight": True})
    for i, block in enumerate(d.get("rooms", [])):
        xs = [c["x"] for c in block]
        zs = [c["z"] for c in block]
        cx2, cz2 = (min(xs) + 1) * C, (min(zs) + 1) * C
        corner = [min(xs) * C + 1.5, 6.5, min(zs) * C + 1.5]
        out.append({"name": f"room{i + 1}", "w": 600, "h": 400, "fov": 75, "pos": corner,
                    "look": [cx2 - corner[0], -3.5, cz2 - corner[2]], "flashlight": True, "exposure": 2.2, "inspect": True})
    if corridor:
        run, dirn = corridor
        dx, dz = DIRS[dirn]
        x0, z0 = run[0]
        pos = [(x0 + 0.5 - dx * 0.4) * C, 4.8, (z0 + 0.5 - dz * 0.4) * C]
        out.append({"name": "corridor", "w": 600, "h": 400, "fov": 70, "pos": pos, "look": [dx, -0.04, dz], "flashlight": True})
    return out


def grade(im, L):
    im = ImageEnhance.Color(im.convert("RGB")).enhance(1 + L["saturation"])
    a = np.asarray(im).astype(np.float32) / 255
    a = a * np.array(L["tint"], np.float32)
    a = a + L["brightness"]
    a = np.clip((a - 0.5) * (1 + L["contrast"] * 0.6) + 0.5, 0, 1)
    return Image.fromarray((a * 255).astype(np.uint8))


def main():
    args = sys.argv[1:]
    seed = 4242
    if "--seed" in args:
        i = args.index("--seed")
        seed = int(args[i + 1])
        del args[i:i + 2]
    nights = [int(a) for a in args] or [1, 2, 3, 4, 5]
    os.makedirs(OUT, exist_ok=True)
    jobs = []
    meta = {}
    for n in nights:
        plain = os.path.join(OUT, f"night{n}_plain.json")
        d = dump(n, seed, plain)
        corridor = best_corridor(d)
        vs = views(d, corridor, n)
        job = {"json": plain, "views": []}
        for v in vs:
            v["out"] = os.path.join(OUT, f"night{n}_{v['name']}.png")
            job["views"].append(v)
        jobs.append(job)
        if corridor:
            run, dirn = corridor
            mcell = run[min(2, len(run) - 1)]
            withm = os.path.join(OUT, f"night{n}_monster.json")
            dump(n, seed, withm, mcell)
            mv = dict([v for v in vs if v["name"] == "corridor"][0])
            mv["name"] = "monster"
            mv["out"] = os.path.join(OUT, f"night{n}_monster.png")
            jobs.append({"json": withm, "views": [mv]})
        meta[n] = d["lighting"]
    json.dump(jobs, open(os.path.join(OUT, "jobs.json"), "w"))
    run = [GODOT, "--rendering-method", "gl_compatibility", "--rendering-driver", "opengl3",
           "--path", os.path.join(HERE, "render"), "-s", "map_render.gd", "--", os.path.join(OUT, "jobs.json")]
    if not os.environ.get("DISPLAY"):
        run = ["xvfb-run", "-a", "-s", "-screen 0 1280x720x24"] + run
    p = subprocess.run(run, capture_output=True, text=True)
    for line in p.stdout.splitlines() + p.stderr.splitlines():
        if "SCRIPT ERROR" in line or line.startswith("saved"):
            print(line)
    for n in nights:
        L = meta[n]
        names = ["overview", "spawn", "corridor", "monster"] + [f"room{i}" for i in range(1, 7)]
        ims = {k: grade(Image.open(os.path.join(OUT, f"night{n}_{k}.png")), L) for k in names if os.path.exists(os.path.join(OUT, f"night{n}_{k}.png"))}
        sheet = Image.new("RGB", (900 + 14 * 3 + 600, 30 + 640 + 14 * 2), (12, 12, 12))
        sheet.paste(ims["overview"], (14, 44))
        y = 44
        for k in ["spawn", "corridor"]:
            if k in ims:
                sheet.paste(ims[k].resize((600, 400)).crop((0, 0, 600, 300)), (900 + 28, y))
                y += 314
        sheet.save(os.path.join(OUT, f"night{n}.png"))
        for k, im in ims.items():
            im.save(os.path.join(OUT, f"night{n}_{k}_graded.png"))
        print("sheet", n)


if __name__ == "__main__":
    main()
