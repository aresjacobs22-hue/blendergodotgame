#!/usr/bin/env python3
"""Store art for the Roblox game page, rendered from the real maps and monsters:

  assets/covers/icon.png           512x512   the Hollow's skull in your flashlight
  assets/covers/thumb_title.png    1920x1080 A C H R O M A, and something at the end of the hall
  assets/covers/thumb_night<N>.png 1920x1080 each night's monster down its own corridor

  LUNE=lune GODOT=godot python3 tools/monster-lab/covers.py [--seed N]

Same pipeline as maps.py (map_dump.luau -> render/map_render.gd), framed like a still
from the game, then graded: the night's colour grade, a vignette, film grain, and the
only words the game uses (NIGHT 1..5, letter-spaced).
"""
import json, os, subprocess, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import maps  # noqa: E402

ROOT = maps.ROOT
WORK = os.path.join(HERE, "out", "covers")
DEST = os.path.join(ROOT, "assets", "covers")
FONT = "/usr/share/fonts/truetype/freefont/FreeSerif.ttf"
PALE = (200, 200, 194)

# how far down the corridor it stands (cells), and how much to open up each night's
# exposure so the thumbnail still reads when it's small on the Roblox page
MONSTER_CELL = {1: 2, 2: 1, 3: 2, 4: 2, 5: 2}
EXPOSURE = {1: 1.7, 2: 1.3, 3: 1.8, 4: 1.0, 5: 2.0}


def spaced(text):
    return "    ".join(" ".join(word) for word in text.split(" "))


def head_of(d, near):
    """The monster's head: the part called Head closest to where we put it."""
    heads = [p for p in d["parts"] if p["name"] == "Head"]
    best = min(heads, key=lambda p: (p["cf"][0] - near[0]) ** 2 + (p["cf"][2] - near[1]) ** 2)
    return best["cf"][:3]


def cell_center(d, c):
    C = d["cellSize"]
    return ((c[0] + 0.5) * C, (c[1] + 0.5) * C)


def finish(path_in, path_out, L, size, title=None, title_y=0.5, title_size=46, vignette=0.6):
    im = maps.grade(Image.open(path_in), L).resize(size, Image.LANCZOS)
    a = np.asarray(im).astype(np.float32) / 255
    h, w = a.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    r = np.sqrt(((xx - w / 2) / (w / 2)) ** 2 + ((yy - h / 2) / (h / 2)) ** 2) / np.sqrt(2)
    a *= (1 - vignette * np.clip(r - 0.25, 0, 1) ** 1.6)[..., None]
    rng = np.random.default_rng(7)
    a += rng.normal(0, 0.022, (h, w))[..., None]
    out = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))
    if title:
        layer = Image.new("RGBA", out.size, (0, 0, 0, 0))
        draw = ImageDraw.Draw(layer)
        font = ImageFont.truetype(FONT, title_size)
        text = spaced(title)
        tw = draw.textlength(text, font=font)
        draw.text(((w - tw) / 2, h * title_y - title_size / 2), text, font=font, fill=PALE + (225,))
        # a faint glow so it sits in the image instead of on top of it
        glow = layer.filter(ImageFilter.GaussianBlur(title_size * 0.25))
        out = Image.alpha_composite(Image.alpha_composite(out.convert("RGBA"), glow), layer).convert("RGB")
    out.save(path_out)
    print("wrote", os.path.relpath(path_out, ROOT))


def main():
    args = sys.argv[1:]
    seed = 4242
    if "--seed" in args:
        seed = int(args[args.index("--seed") + 1])
    os.makedirs(WORK, exist_ok=True)
    os.makedirs(DEST, exist_ok=True)
    jobs, finishing = [], []

    for n in range(1, 6):
        plain = maps.dump(n, seed, os.path.join(WORK, f"night{n}_plain.json"))
        corridor = maps.best_corridor(plain)
        run, dirn = corridor
        dx, dz = maps.DIRS[dirn]
        C = plain["cellSize"]
        first = run[0]
        cam_x, cam_z = cell_center(plain, first)
        cam_x -= dx * C * 0.45
        cam_z -= dz * C * 0.45

        shots = [("night", run[min(MONSTER_CELL[n], len(run) - 1)])]
        if n == 1:
            shots.append(("title", run[-1]))  # far away, at the end of the hall
            shots.append(("icon", run[1]))
        for kind, mcell in shots:
            name = f"{kind}{n}" if kind == "night" else kind
            path = os.path.join(WORK, f"{name}.json")
            # the monster in that cell, turned to face the camera's cell
            subprocess.run([maps.LUNE, "run", "tools/monster-lab/map_dump.luau", str(n), str(seed), path,
                            f"{mcell[0]},{mcell[1]}", f"{first[0]},{first[1]}"], cwd=ROOT, check=True)
            d = json.load(open(path))
            mx, mz = cell_center(d, mcell)
            head = head_of(d, (mx, mz))
            view = {"name": name, "flashlight": True, "lamp": 1.5, "exposure": EXPOSURE[n]}
            if kind == "icon":
                # close, a little below its face, looking up into the skull
                tx, tz = cam_x - head[0], cam_z - head[2]
                dist = (tx * tx + tz * tz) ** 0.5
                ux, uz = tx / dist, tz / dist
                pos = [head[0] + ux * 7.5, head[1] - 1.6, head[2] + uz * 7.5]
                view.update({"w": 1024, "h": 1024, "fov": 34, "pos": pos,
                             "look": [head[0] - pos[0], head[1] + 0.2 - pos[1], head[2] - pos[2]]})
            else:
                pos = [cam_x, 5.0, cam_z]
                aim_y = head[1] * 0.62 if kind == "night" else 4.6
                view.update({"w": 1920, "h": 1080, "fov": 50, "pos": pos,
                             "look": [mx - pos[0], aim_y - pos[1], mz - pos[2]]})
            view["out"] = os.path.join(WORK, f"{name}.png")
            jobs.append({"json": path, "views": [view]})
            finishing.append((kind, n, view["out"], d["lighting"]))

    json.dump(jobs, open(os.path.join(WORK, "jobs.json"), "w"))
    cmd = [maps.GODOT, "--rendering-method", "gl_compatibility", "--rendering-driver", "opengl3",
           "--path", os.path.join(HERE, "render"), "-s", "map_render.gd", "--", os.path.join(WORK, "jobs.json")]
    if not os.environ.get("DISPLAY"):
        cmd = ["xvfb-run", "-a", "-s", "-screen 0 1280x720x24"] + cmd
    p = subprocess.run(cmd, capture_output=True, text=True)
    for line in p.stdout.splitlines() + p.stderr.splitlines():
        if "SCRIPT ERROR" in line or "ERROR" in line:
            print(line)

    for kind, n, src, L in finishing:
        if kind == "night":
            finish(src, os.path.join(DEST, f"thumb_night{n}.png"), L, (1920, 1080), f"NIGHT {n}", 0.88)
        elif kind == "title":
            finish(src, os.path.join(DEST, "thumb_title.png"), L, (1920, 1080), "ACHROMA", 0.24, 110, 0.7)
        else:
            finish(src, os.path.join(DEST, "icon.png"), L, (512, 512), None, vignette=0.75)


if __name__ == "__main__":
    main()
