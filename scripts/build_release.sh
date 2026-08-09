#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

ENV_FILE="${RELEASE_ENV_FILE:-.release.env}"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  . "$ENV_FILE"
  set +a
fi

PROJECT="MDViewer.xcodeproj"
BUILD_ROOT="${BUILD_ROOT:-release-build}"
DIST_DIR="${DIST_DIR:-dist}"
ALLOW_UNSIGNED="${ALLOW_UNSIGNED:-0}"

xcodegen generate
rm -rf "$BUILD_ROOT" "$DIST_DIR"
mkdir -p "$DIST_DIR"

identity="${CODE_SIGN_IDENTITY:-}"
if [[ "$ALLOW_UNSIGNED" != "1" && -z "$identity" ]]; then
  identity="$(
    security find-identity -v -p codesigning 2>/dev/null \
      | grep 'Developer ID Application' \
      | head -1 \
      | sed 's/.*"\(.*\)"/\1/' \
      || true
  )"
fi
if [[ "$ALLOW_UNSIGNED" != "1" && -z "$identity" ]]; then
  echo "No Developer ID Application signing identity found."
  echo "Set ALLOW_UNSIGNED=1 only for local or CI verification builds."
  exit 1
fi

for edition in Lite Full; do
  scheme="MDViewer-$edition"
  derived_data="$BUILD_ROOT/$edition/DerivedData"
  destination="$DIST_DIR/MDViewer-$edition.app"
  settings=()

  if [[ "$ALLOW_UNSIGNED" == "1" ]]; then
    settings+=(CODE_SIGNING_ALLOWED=NO)
  else
    settings+=(
      CODE_SIGN_STYLE=Manual
      CODE_SIGN_IDENTITY="$identity"
      CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
      ENABLE_HARDENED_RUNTIME=YES
      OTHER_CODE_SIGN_FLAGS="--timestamp"
    )
    if [[ -n "${TEAM_ID:-}" ]]; then
      settings+=(DEVELOPMENT_TEAM="$TEAM_ID")
    fi
  fi

  xcodebuild \
    -project "$PROJECT" \
    -scheme "$scheme" \
    -configuration Release \
    -derivedDataPath "$derived_data" \
    clean build \
    "${settings[@]}"

  built_app="$derived_data/Build/Products/Release/MDViewer.app"
  if [[ ! -d "$built_app" ]]; then
    echo "Build succeeded, but app bundle was not found at $built_app"
    exit 1
  fi
  ditto "$built_app" "$destination"
  if [[ "$ALLOW_UNSIGNED" != "1" ]]; then
    codesign --verify --strict --deep --verbose=2 "$destination"
  fi
done

./scripts/audit_bundles.sh \
  "$DIST_DIR/MDViewer-Lite.app" \
  "$DIST_DIR/MDViewer-Full.app"

echo "Edition app bundles created in $DIST_DIR"
