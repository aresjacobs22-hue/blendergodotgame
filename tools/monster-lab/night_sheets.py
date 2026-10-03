#!/usr/bin/env python3
"""Renders nights 2-5 with the real map generator and puts each one on a single sheet
(a big shot down a corridor, the map from above, a room, where you wake up, and the
monster in the corridor):

  LUNE=lune GODOT=godot python3 tools/monster-lab/night_sheets.py [night ...] [--seed N]
Writes out/nights/night<N>_<view>.png and out/nights/night<N>.png (the sheet).
"""
import json, math, os, subprocess, sys
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import maps  # noqa: E402

OUT = os.path.join(HERE, "out", "nights")
SERIF = os.environ.get("SHEET_FONT", "/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf")

TITLES = {
    2: ("NIGHT 2", "THE RED WARD", "A 1950s isolation wing. White tile, a black and white floor, iron beds. The only colour is the red lamp over some of the doors."),
    3: ("NIGHT 3", "THE DROWNED TUNNELS", "Vaulted brick storm drains under the city. Black water, dead lamps, and the moon coming down through the grates."),
    4: ("NIGHT 4", "THE ATRIUM", "A museum after dark. Galleries under skylights, faceless portraits, and dust sheets over everything that might be a statue."),
    5: ("NIGHT 5", "THE VOID", "The house from night 1, coming apart. The walls stop short, the floor has holes, and there's nothing above you at all."),
}

# which room each sheet shows (1-based index into the map's rooms)
ROOM = {2: 3, 3: 2, 4: 1, 5: 1}


def dump(n, seed, path, monster=None, face=None):
    args = [maps.LUNE, "run", "tools/monster-lab/map_dump.luau", str(n), str(seed), path]
    if monster:
        args.append(f"{monster[0]},{monster[1]}")
        if face:
            args.append(f"{face[0]},{face[1]}")
    subprocess.run(args, cwd=maps.ROOT, check=True)
    return json.load(open(path))


BLOCKERS = {"Plinth", "Bench", "Sheet", "StatueBase", "Shoulders", "BedFrame", "Seat", "LoneDoor", "ChairSeat"}


def hero_corridor(d):
    """The best long, straight run of open corridor (no doors, no rooms) with lamps in it,
    and nothing standing right in front of the camera."""
    C = d["cellSize"]
    rooms = {(c["x"], c["z"]) for block in d.get("rooms", []) for c in block}
    lamps = [l["pos"] for l in d["lights"] if l["enabled"] or l["kind"] == "PointLight"]
    cell = lambda p: (int(p[0] // C), int(p[2] // C))
    blocked = {cell(p["cf"]) for p in d["parts"] if p["name"] in BLOCKERS}
    grates = {cell(p["cf"]) for p in d["parts"] if p["name"] in ("GrateSky", "Skylight")}
    best, best_score = None, -1
    for z in range(d["depth"]):
        for x in range(d["width"]):
            for dirn, (dx, dz) in maps.DIRS.items():
                run = [(x, z)]
                cx, cz = x, z
                while len(run) < 6 and maps.edge(d, cx, cz, dirn) == "open":
                    cx, cz = cx + dx, cz + dz
                    if not (0 <= cx < d["width"] and 0 <= cz < d["depth"]):
                        break
                    run.append((cx, cz))
                if len(run) < 4 or any(maps.is_hub(d, rx, rz) or (rx, rz) in rooms for rx, rz in run):
                    continue
                if run[0] in blocked or run[1] in blocked:
                    continue
                lit = sum(1 for rx, rz in run[1:] for l in lamps
                          if abs(l[0] - (rx + 0.5) * C) < C * 0.8 and abs(l[2] - (rz + 0.5) * C) < C * 0.8)
                score = len(run) + min(lit, 3) * 2 + min(sum(1 for c in run[1:4] if c in grates), 2) * 1.5
                if score > best_score:
                    best, best_score = (run, dirn), score
    return best or maps.best_corridor(d)


def gallery_end(d):
    """Night 4: the end of a gallery, where a bench faces one big painting behind a rope."""
    C = d["cellSize"]
    cell = lambda p: (int(p[0] // C), int(p[2] // C))
    benches = {cell(p["cf"]) for p in d["parts"] if p["name"] == "Bench"}
    lit = [l["pos"] for l in d["lights"] if l["enabled"]]
    best, best_score = None, -1
    for z in range(d["depth"]):
        for x in range(d["width"]):
            if maps.is_hub(d, x, z) or (x, z) not in benches:
                continue
            ways = [k for k in maps.DIRS if maps.edge(d, x, z, k) in maps.PASSABLE]
            if len(ways) != 1:
                continue
            dx, dz = maps.DIRS[ways[0]]
            nx, nz = x + dx, z + dz
            score = sum(1 for l in lit if abs(l[0] - (x + 0.5) * C) < C and abs(l[2] - (z + 0.5) * C) < C)
            score += sum(1 for l in lit if abs(l[0] - (nx + 0.5) * C) < C * 0.6 and abs(l[2] - (nz + 0.5) * C) < C * 0.6)
            if score > best_score:
                best, best_score = (x, z, dx, dz), score
    if not best:
        return None
    x, z, dx, dz = best
    pos = [(x + 0.5 + dx * 1.05) * C, 5.6, (z + 0.5 + dz * 1.05) * C]
    target = [(x + 0.5 - dx * 0.5) * C, 6.6, (z + 0.5 - dz * 0.5) * C]
    return {"name": "hero", "w": 1280, "h": 720, "fov": 62, "pos": pos, "flashlight": True,
            "look": [target[i] - pos[i] for i in range(3)]}


def corridor_views(d, run, dirn, w, h, name):
    C = d["cellSize"]
    dx, dz = maps.DIRS[dirn]
    x0, z0 = run[0]
    # a little off the middle of the corridor, so one wall runs away from you
    side = 0.12
    pos = [(x0 + 0.5 - dx * 0.4 + dz * side) * C, 5.0, (z0 + 0.5 - dz * 0.4 - dx * side) * C]
    return {"name": name, "w": w, "h": h, "fov": 66, "pos": pos, "look": [dx - dz * 0.05, -0.04, dz + dx * 0.05], "flashlight": True}


def room_view(d, block, w, h, name):
    """The room with its ceiling lifted off, from above one corner (the cistern: from
    inside, at eye level, since from above it's just water and the tops of columns)."""
    C = d["cellSize"]
    xs = [c["x"] for c in block]
    zs = [c["z"] for c in block]
    cx, cz = (min(xs) + 1) * C, (min(zs) + 1) * C
    if d["night"] == 3:
        # standing on the plank walkway, looking down it between two rows of columns
        pos = [min(xs) * C + 1.6, 5.4, cz + C * 0.33]
        return {"name": name, "w": w, "h": h, "fov": 74, "pos": pos, "flashlight": True, "exposure": 1.6, "inspect": True,
                "look": [1, -0.12, 0.06]}
    steep = d["night"] == 2  # the ward's beds stand against the walls: look straight down on them
    off, up = (C * 0.75, C * 2.9) if steep else (C * 1.35, C * 1.75)
    pos = [cx - off, up, cz - off]
    return {"name": name, "w": w, "h": h, "fov": 60, "pos": pos, "overview": True, "moon": 0.75, "lamp": 2.0,
            "look": [cx - pos[0], 1.5 - pos[1], cz - pos[2]]}


def main():
    args = sys.argv[1:]
    seed = 4242
    if "--seed" in args:
        i = args.index("--seed")
        seed = int(args[i + 1])
        del args[i:i + 2]
    nights = [int(a) for a in args] or [2, 3, 4, 5]
    os.makedirs(OUT, exist_ok=True)
    jobs, meta = [], {}
    for n in nights:
        plain = os.path.join(OUT, f"night{n}_plain.json")
        d = dump(n, seed, plain)
        C = d["cellSize"]
        span = max(d["width"], d["depth"]) * C
        cx, cz = d["width"] * C / 2, d["depth"] * C / 2
        corridor = hero_corridor(d)
        views = [{"name": "overview", "overview": True, "w": 900, "h": 600, "fov": 50,
                  "pos": [cx, span * 1.05, -span * 0.25], "look": [0, -span * 1.05, cz + span * 0.25], "moon": 0.6, "lamp": 1.5}]
        sp = d["spawns"][0]
        views.append({"name": "spawn", "w": 900, "h": 506, "fov": 72, "pos": [sp["pos"][0], sp["pos"][1] + 1.3, sp["pos"][2]],
                      "look": sp["look"], "flashlight": True})
        rooms = d.get("rooms", [])
        if rooms:
            block = rooms[min(ROOM.get(n, 1), len(rooms)) - 1]
            views.append(room_view(d, block, 900, 506, "room"))
        hero = gallery_end(d) if n == 4 else None
        if hero:
            views.append(hero)
        elif corridor:
            run, dirn = corridor
            views.append(corridor_views(d, run, dirn, 1280, 720, "hero"))
        for v in views:
            v["out"] = os.path.join(OUT, f"night{n}_{v['name']}.png")
        jobs.append({"json": plain, "views": views})
        if n == 3 and corridor:
            # the same tunnel once the generators are running
            lit = json.load(open(plain))
            for l in lit["lights"]:
                l["enabled"] = True
            for p in lit["parts"]:
                if p["name"] == "Bulb" and p["material"] == "Neon" and p["color"][0] < 0.3:
                    p["color"] = [1.0, 0.925, 0.784]
            litpath = os.path.join(OUT, f"night{n}_lit.json")
            json.dump(lit, open(litpath, "w"))
            run, dirn = corridor
            lv = corridor_views(d, run, dirn, 900, 506, "lit")
            lv["flashlight"] = False
            lv["out"] = os.path.join(OUT, f"night{n}_lit.png")
            jobs.append({"json": litpath, "views": [lv]})
        if corridor:
            run, dirn = corridor
            mcell = run[min(2, len(run) - 1)]
            withm = os.path.join(OUT, f"night{n}_monster.json")
            dump(n, seed, withm, mcell, run[0])
            mv = corridor_views(d, run, dirn, 900, 506, "monster")
            mv["out"] = os.path.join(OUT, f"night{n}_monster.png")
            jobs.append({"json": withm, "views": [mv]})
        meta[n] = d["lighting"]
    json.dump(jobs, open(os.path.join(OUT, "jobs.json"), "w"))
    cmd = [maps.GODOT, "--rendering-method", "gl_compatibility", "--rendering-driver", "opengl3",
           "--path", os.path.join(HERE, "render"), "-s", "map_render.gd", "--", os.path.join(OUT, "jobs.json")]
    if not os.environ.get("DISPLAY"):
        cmd = ["xvfb-run", "-a", "-s", "-screen 0 1280x720x24"] + cmd
    p = subprocess.run(cmd, capture_output=True, text=True)
    for line in p.stdout.splitlines() + p.stderr.splitlines():
        if "SCRIPT ERROR" in line:
            print(line)
    for n in nights:
        sheet(n, meta[n])


def sheet(n, L):
    def load(k):
        path = os.path.join(OUT, f"night{n}_{k}.png")
        if not os.path.exists(path):
            return None
        im = maps.grade(Image.open(path), L)
        im.save(os.path.join(OUT, f"night{n}_{k}_graded.png"))
        return im

    W, H = 1920, 1240
    bg = (10, 10, 10)
    out = Image.new("RGB", (W, H), bg)
    draw = ImageDraw.Draw(out)
    big = ImageFont.truetype(SERIF, 40)
    small = ImageFont.truetype(SERIF, 19)
    tiny = ImageFont.truetype(SERIF, 16)
    num, name, blurb = TITLES[n]
    draw.text((28, 22), f"{num}   ·   {name}", font=big, fill=(225, 225, 220))
    draw.text((30, 78), blurb, font=small, fill=(150, 150, 146))

    def put(im, box, caption):
        x, y, w, h = box
        if im is None:
            return
        out.paste(im.resize((w, h), Image.LANCZOS), (x, y))
        draw.text((x + 2, y + h + 6), caption, font=tiny, fill=(120, 120, 116))

    top = 120
    put(load("hero"), (20, top, 1280, 720), "the end of a gallery" if n == 4 else "the corridors")
    put(load("overview"), (1320, top, 580, 387), "from above")
    put(load("room"), (1320, top + 420, 580, 326), {2: "a ward", 3: "the cistern", 4: "the rotunda", 5: "a room it remembers"}.get(n, "a room"))
    row = top + 720 + 44
    if n == 3:
        put(load("lit"), (20, row, 620, 349), "once the generators are running")
    else:
        put(load("spawn"), (20, row, 620, 349), "where you wake up")
    put(load("monster"), (660, row, 620, 349), "and it's in here with you")
    out.save(os.path.join(OUT, f"night{n}.png"))
    print("sheet", n)


if __name__ == "__main__":
    main()
