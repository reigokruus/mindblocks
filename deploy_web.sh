#!/usr/bin/env bash
# Exports the Web build and uploads it to itch.io with butler.
# One-time setup: install butler and run `butler login` (see README).
set -euo pipefail
cd "$(dirname "$0")"

TARGET="rkr8/mindblocks:html5"
VERSION="$(git describe --tags --always --dirty)"

rm -rf build/web
mkdir -p build/web
godot --headless --path . --export-release "Web" build/web/index.html
if [ ! -s build/web/index.html ] || [ ! -s build/web/index.wasm ]; then
	echo "Web export failed: build/web is incomplete." >&2
	exit 1
fi

butler push build/web "$TARGET" --userversion "$VERSION"
echo "Uploaded $VERSION. Play it at https://rkr8.itch.io/mindblocks"
