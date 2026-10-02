#!/usr/bin/env python3
"""Renders the lobby (the real one, built by Server/Lobby in the test engine): standing
at the spawn looking at a door mid-countdown, the thing in the fog, and the whole circle
from above.

  LUNE=lune GODOT=godot python3 tools/monster-lab/lobby.py
Writes out/lobby/<view>.png and out/lobby/lobby.png (all three on one sheet).
"""
import json, math, os, subprocess, sys
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import maps  # noqa: E402

OUT = os.path.join(HERE, "out", "lobby")
ORIGIN = (-1200.0, 0.0, 0.0)  # Lobby.ORIGIN


def main():
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, "lobby.json")
    subprocess.run([maps.LUNE, "run", "tools/monster-lab/map_dump.luau", "lobby", "1", path], cwd=maps.ROOT, check=True)
    d = json.load(open(path))
    ox, _, oz = ORIGIN

    # door 1 (the one counting down) stands at 45 degrees, 44 studs out
    a = math.radians(45)
    door = (ox + math.cos(a) * 44, 0, oz + math.sin(a) * 44)
    eye = (ox + math.cos(a) * 6, 5.0, oz + math.sin(a) * 6)
    # the watcher: the Head furthest from the middle
    heads = [p["cf"][:3] for p in d["parts"] if p["name"] == "Head"]
    watcher = max(heads, key=lambda h: (h[0] - ox) ** 2 + (h[2] - oz) ** 2)
    wdir = (watcher[0] - ox, watcher[2] - oz)
    wl = math.hypot(*wdir)
    weye = (ox + wdir[0] / wl * 18, 5.0, oz + wdir[1] / wl * 18)

    views = [
        {"name": "door", "w": 1200, "h": 700, "fov": 62, "pos": list(eye),
         "look": [door[0] - eye[0], 8.5 - eye[1], door[2] - eye[2]], "lamp": 1.5, "exposure": 1.6},
        {"name": "watcher", "w": 1200, "h": 700, "fov": 40, "pos": list(weye),
         "look": [watcher[0] - weye[0], watcher[1] - 4.5 - weye[1], watcher[2] - weye[2]], "lamp": 1.5, "exposure": 1.6},
        {"name": "above", "w": 1200, "h": 700, "fov": 55, "overview": True, "moon": 0.25, "lamp": 1.5,
         "pos": [ox, 95, oz - 95], "look": [0, -95, 95]},
    ]
    for v in views:
        v["out"] = os.path.join(OUT, v["name"] + ".png")
    json.dump([{"json": path, "views": views}], open(os.path.join(OUT, "jobs.json"), "w"))
    cmd = [maps.GODOT, "--rendering-method", "gl_compatibility", "--rendering-driver", "opengl3",
           "--path", os.path.join(HERE, "render"), "-s", "map_render.gd", "--", os.path.join(OUT, "jobs.json")]
    if not os.environ.get("DISPLAY"):
        cmd = ["xvfb-run", "-a", "-s", "-screen 0 1280x720x24"] + cmd
    p = subprocess.run(cmd, capture_output=True, text=True)
    for line in p.stdout.splitlines() + p.stderr.splitlines():
        if "SCRIPT ERROR" in line:
            print(line)

    ims = [maps.grade(Image.open(v["out"]), d["lighting"]) for v in views]
    for v, im in zip(views, ims):
        im.save(v["out"])
    sheet = Image.new("RGB", (1200 + 14 + 600, 700), (12, 12, 12))
    sheet.paste(ims[0], (0, 0))
    sheet.paste(ims[1].resize((600, 350)), (1214, 0))
    sheet.paste(ims[2].resize((600, 350)), (1214, 350))
    sheet.save(os.path.join(OUT, "lobby.png"))
    print("wrote", os.path.relpath(os.path.join(OUT, "lobby.png"), maps.ROOT))


if __name__ == "__main__":
    main()
