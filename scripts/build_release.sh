#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

ENV_FILE="${RELEASE_ENV_FILE:-.release.env}"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  . "$ENV_FILE"
  set +a
fi

APP_BUNDLE_NAME="MDViewer"
PROJECT="MDViewer.xcodeproj"
SCHEME="MDViewer"
BUILD_ROOT="${BUILD_ROOT:-release-build}"
DERIVED_DATA="$BUILD_ROOT/DerivedData"
DIST_DIR="${DIST_DIR:-dist}"
DIST_APP="$DIST_DIR/$APP_BUNDLE_NAME.app"

if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate
fi

identity="${CODE_SIGN_IDENTITY:-}"
if [[ -z "$identity" ]]; then
  identity="$(
    security find-identity -v -p codesigning 2>/dev/null \
      | grep 'Developer ID Application' \
      | head -1 \
      | sed 's/.*"\(.*\)"/\1/' \
      || true
  )"
fi
if [[ -z "$identity" ]]; then
  echo "No Developer ID Application signing identity found."
  exit 1
fi

rm -rf "$BUILD_ROOT" "$DIST_DIR"
mkdir -p "$DIST_DIR"

settings=(
  CODE_SIGN_STYLE=Manual
  CODE_SIGN_IDENTITY="$identity"
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
  ENABLE_HARDENED_RUNTIME=YES
  OTHER_CODE_SIGN_FLAGS="--timestamp"
)
if [[ -n "${TEAM_ID:-}" ]]; then
  settings+=(DEVELOPMENT_TEAM="$TEAM_ID")
fi

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  clean build \
  "${settings[@]}"

built_app="$DERIVED_DATA/Build/Products/Release/$APP_BUNDLE_NAME.app"
if [[ ! -d "$built_app" ]]; then
  echo "Build succeeded, but app bundle was not found at $built_app"
  exit 1
fi

ditto "$built_app" "$DIST_APP"
codesign --verify --strict --deep --verbose=2 "$DIST_APP"
echo "App bundle created: $DIST_APP"
