#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

ENV_FILE="${RELEASE_ENV_FILE:-.release.env}"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  . "$ENV_FILE"
  set +a
fi

DMG_PATH="${DMG_PATH:-dist/MDViewer-macos.dmg}"
if [[ ! -f "$DMG_PATH" ]]; then
  echo "DMG not found at $DMG_PATH"
  exit 1
fi

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
  xcrun notarytool submit \
    "$DMG_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_PASSWORD" \
    --wait
else
  echo "Notarization credentials are not configured."
  exit 1
fi

xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
spctl --assess \
  --type open \
  --context context:primary-signature \
  --verbose \
  "$DMG_PATH"
(
  cd "$(dirname "$DMG_PATH")"
  shasum -a 256 "$(basename "$DMG_PATH")" > "$(basename "$DMG_PATH").sha256"
)
