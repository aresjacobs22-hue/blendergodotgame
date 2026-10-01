#!/usr/bin/env bash
# Type-checks the Luau code, runs every test, and rebuilds build/ACHROMA.rbxlx.
# Needs rojo, lune and luau-lsp on PATH (`rokit install`). The Roblox type
# definitions are downloaded once into .cache/.
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p .cache build
DEFS=.cache/globalTypes.d.luau
if [ ! -f "$DEFS" ]; then
	curl -sSL -o "$DEFS" https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau
fi

echo "== type check"
rojo sourcemap default.project.json -o sourcemap.json
out=$(luau-lsp analyze --sourcemap=sourcemap.json --definitions=@roblox="$DEFS" --platform=roblox src 2>&1 | grep -v '^\[' || true)
if [ -n "$out" ]; then
	echo "$out"
	exit 1
fi
echo "clean"

echo "== maze tests"
lune run tests/maze.spec.luau | tail -1
echo "== simulation tests"
lune run tests/sim.spec.luau | tail -1
echo "== end-to-end tests"
lune run tests/e2e.spec.luau | tail -1

echo "== build"
rojo build default.project.json -o build/ACHROMA.rbxlx
