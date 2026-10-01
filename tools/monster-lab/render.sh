#!/usr/bin/env bash
# Renders monster designs to PNGs: builds each rig with real Roblox datatypes (Lune),
# then renders it in Godot in the night's lighting.
#
#   tools/monster-lab/render.sh <mood> <Design> [<Design>...]
#   tools/monster-lab/render.sh all          # every design + the five contact sheets
#
#   mood: house | ward | sewer | atrium | void
#   Design: e.g. HollowA, CrawlerB, StatueC@4 (statue pose 4), StatueA! (decoy)
#
# Needs lune, python3 (Pillow, numpy) and Godot 4.3+. On a headless machine it runs
# Godot under xvfb-run with the OpenGL renderer. Set LUNE / GODOT to override paths.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
LUNE="${LUNE:-lune}"
GODOT="${GODOT:-godot}"
OUT="$HERE/out"
mkdir -p "$OUT/json" "$OUT/png" "$OUT/sheets"

cat "$HERE"/designs/_head.luau "$HERE"/designs/hollow.luau "$HERE"/designs/crawler.luau \
	"$HERE"/designs/listener.luau "$HERE"/designs/statue.luau "$HERE"/designs/amalgam.luau \
	"$HERE"/designs/_tail.luau > "$OUT/designs.luau"

render() {
	local mood=$1
	shift
	"$LUNE" run "$HERE/dump.luau" "$OUT/designs.luau" "$OUT/json" "$@"
	python3 - "$OUT" "$mood" "$@" <<'PY'
import json, sys
out, mood, kinds = sys.argv[1], sys.argv[2], sys.argv[3:]
jobs = [{"json": f"{out}/json/{k}.json", "mood": mood, "shots": [
    {"out": f"{out}/png/{k}_front.png", "view": "front", "w": 620, "h": 820},
    {"out": f"{out}/png/{k}_side.png", "view": "side", "w": 300, "h": 400},
    {"out": f"{out}/png/{k}_head.png", "view": "head", "w": 300, "h": 400}]} for k in kinds]
json.dump(jobs, open(f"{out}/jobs.json", "w"))
PY
	local run=("$GODOT" --rendering-method gl_compatibility --rendering-driver opengl3 --path "$HERE/render" -s render.gd -- "$OUT/jobs.json")
	if [ -z "${DISPLAY:-}" ] && command -v xvfb-run > /dev/null; then
		run=(xvfb-run -a -s "-screen 0 1280x720x24" "${run[@]}")
	fi
	"${run[@]}" 2>&1 | grep -E "^saved|SCRIPT ERROR" || true
}

if [ "${1:-}" = "all" ]; then
	render house HollowA HollowB HollowC
	render ward CrawlerA CrawlerB CrawlerC
	render sewer ListenerA ListenerB ListenerC
	render atrium StatueA@4 StatueB@4 StatueC@4 StatueA@2 StatueB@2 StatueC@2
	render void AmalgamA AmalgamB AmalgamC
	python3 "$HERE/sheets.py" "$OUT"
else
	render "$@"
fi
