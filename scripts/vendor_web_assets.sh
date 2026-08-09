#!/usr/bin/env bash
# Refresh (or verify) MDViewer's vendored web assets from pinned upstream
# releases. Pass --check to fail instead of writing when anything is stale.
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v node >/dev/null 2>&1; then
  echo "node is required to vendor web assets."
  exit 1
fi

if [[ -f vendor/package-lock.json ]]; then
  npm ci --prefix vendor --no-audit --no-fund --legacy-peer-deps
else
  npm install --prefix vendor --no-audit --no-fund --legacy-peer-deps
fi

node scripts/vendor_web_assets.mjs "$@"
