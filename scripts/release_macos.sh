#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

DMG_PATH="${DMG_PATH:-dist/MDViewer-macos.dmg}"
./scripts/build_release.sh
DMG_PATH="$DMG_PATH" ./scripts/make_dmg.sh
DMG_PATH="$DMG_PATH" ./scripts/notarize_dmg.sh
