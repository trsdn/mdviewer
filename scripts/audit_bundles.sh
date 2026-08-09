#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

lite_app="${1:-dist/MDViewer-Lite.app}"
full_app="${2:-dist/MDViewer-Full.app}"

fail() {
  echo "Bundle audit failed: $*" >&2
  exit 1
}

[[ -d "$lite_app" ]] || fail "Lite app not found at $lite_app"
[[ -d "$full_app" ]] || fail "Full app not found at $full_app"

lite_resources="$lite_app/Contents/Resources"
full_resources="$full_app/Contents/Resources"
lite_plist="$lite_app/Contents/Info.plist"
full_plist="$full_app/Contents/Info.plist"

for plist in "$lite_plist" "$full_plist"; do
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")" \
    == "com.torstenmahr.MDViewer" ]] || fail "unexpected bundle identifier in $plist"
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")" \
    == "2.0.0" ]] || fail "unexpected marketing version in $plist"
done

[[ "$(/usr/libexec/PlistBuddy -c 'Print :MDViewerEdition' "$lite_plist")" \
  == "lite" ]] || fail "Lite edition marker is missing"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :MDViewerEdition' "$full_plist")" \
  == "full" ]] || fail "Full edition marker is missing"

for forbidden in WebModules renderer-full.js HIGHLIGHTJS-LICENSE.txt \
  JS-YAML-LICENSE.txt MERMAID-LICENSE.txt SVG-PAN-ZOOM-LICENSE.txt; do
  [[ ! -e "$lite_resources/$forbidden" ]] \
    || fail "Lite contains Full-only resource $forbidden"
done
find "$lite_resources" \
  \( -iname '*mermaid*' -o -iname '*highlight*' -o -iname '*js-yaml*' \
    -o -iname '*svg-pan-zoom*' \) -print -quit | grep -q . \
  && fail "Lite contains a Full-only asset"

for required in renderer-lite.js prism.min.js PRISM-LICENSE.txt; do
  [[ -f "$lite_resources/$required" ]] \
    || fail "Lite is missing $required"
done
for required in renderer-full.js WebModules/web-modules.json \
  WebModules/highlight/highlight.min.mjs \
  WebModules/js-yaml/js-yaml.mjs \
  WebModules/mermaid/mermaid.esm.min.mjs \
  WebModules/svg-pan-zoom/svg-pan-zoom.min.js \
  MERMAID-TRANSITIVE-NOTICES.txt; do
  [[ -f "$full_resources/$required" ]] \
    || fail "Full is missing $required"
done
[[ ! -e "$full_resources/prism.min.js" ]] \
  || fail "Full must not bundle the Lite Prism engine"

for app in "$lite_app" "$full_app"; do
  entitlements="$(codesign -d --entitlements :- "$app" 2>/dev/null || true)"
  if [[ -n "$entitlements" ]]; then
    grep -q 'com.apple.security.app-sandbox' <<<"$entitlements" \
      || fail "$app is missing App Sandbox"
    # WKWebView's separate WebContent process cannot launch under App Sandbox
    # without this entitlement, even though the render page itself never
    # makes a network request: the page's CSP sets `connect-src 'none'` (and
    # every other network-capable directive to 'none'), so no in-page code
    # can ever reach the network. Without this entitlement the WebContent
    # process crashes on launch with "Application does not have permission to
    # communicate with network resources," and every document fails to
    # render. See MDViewer.entitlements.
    grep -q 'com.apple.security.network.client' <<<"$entitlements" \
      || fail "$app is missing the network client entitlement WKWebView requires to launch its WebContent process under App Sandbox"
    grep -q 'com.apple.security.files.user-selected.read-write' <<<"$entitlements" \
      && fail "$app unexpectedly has read-write file access"
  fi
done

lite_bytes="$(du -sk "$lite_app" | awk '{print $1 * 1024}')"
full_bytes="$(du -sk "$full_app" | awk '{print $1 * 1024}')"
echo "Bundle audit passed."
echo "  Lite: $lite_bytes bytes"
echo "  Full: $full_bytes bytes"
