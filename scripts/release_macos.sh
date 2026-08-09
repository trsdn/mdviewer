#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

./scripts/build_release.sh
for edition in Lite Full; do
  dmg_path="dist/MDViewer-$edition-macos.dmg"
  EDITION="$edition" DMG_PATH="$dmg_path" ./scripts/make_dmg.sh
  DMG_PATH="$dmg_path" ./scripts/notarize_dmg.sh
done

echo "Signed, notarized Lite and Full artifacts are ready in dist/."
