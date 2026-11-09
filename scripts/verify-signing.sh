#!/bin/bash
# Verifies the signatures of the receipt-printer binaries. Set ALLOW_ADHOC=1 to skip the identity/timestamp checks (dry runs).
set -euo pipefail

cd "$(dirname "$0")/.."

source scripts/config.sh
TOOLS=("${BINARIES[@]}")
status=0

fail() { echo "  FAIL: $*"; status=1; }

for tool in "${TOOLS[@]}"; do
    bin="$DIST_DIR/$tool"
    echo "== $bin"
    [[ -f "$bin" ]] || { fail "missing"; continue; }

    codesign --verify --deep --strict --verbose=2 "$bin" || fail "codesign --verify --deep --strict"

    info="$(codesign -dv --verbose=4 "$bin" 2>&1)"
    echo "$info" | sed 's/^/  /'

    expected="$(signing_identifier "$tool")"
    echo "$info" | grep -qxF "Identifier=$expected" || fail "identifier is not $expected"
    echo "$info" | grep -Eq "flags=0x[0-9a-f]+\(.*runtime" || fail "hardened runtime flag missing"
    [[ "$(lipo -archs "$bin")" == "arm64" ]] || fail "not arm64-only: $(lipo -archs "$bin")"

    entitlements="$(codesign -d --entitlements - "$bin" 2>/dev/null | tr -d '\0' || true)"
    echo "$entitlements" | grep -q "get-task-allow" && fail "get-task-allow entitlement present (debug build?)"

    if [[ "${ALLOW_ADHOC:-}" != "1" ]]; then
        echo "$info" | grep -q "^Authority=Developer ID Application:" || fail "not signed by a Developer ID Application certificate"
        echo "$info" | grep -q "^Authority=Developer ID Certification Authority$" || fail "Developer ID CA missing from chain"
        echo "$info" | grep -q "^Timestamp=" || fail "no secure timestamp"
        echo "$info" | grep -Eq "^TeamIdentifier=[A-Z0-9]{10}$" || fail "no TeamIdentifier"
    fi
done

app="$DIST_DIR/$APP_NAME.app"
echo "== $app"
if [[ ! -d "$app" ]]; then
    fail "settings app missing"
else
    codesign --verify --deep --strict --verbose=2 "$app" || fail "codesign --verify --deep --strict (settings app)"
    info="$(codesign -dv --verbose=4 "$app" 2>&1)"
    echo "$info" | sed 's/^/  /'
    echo "$info" | grep -qxF "Identifier=$APP_BUNDLE_ID" || fail "settings app identifier is not $APP_BUNDLE_ID"
    echo "$info" | grep -Eq "flags=0x[0-9a-f]+\(.*runtime" || fail "settings app: hardened runtime flag missing"
    [[ "$(lipo -archs "$app/Contents/MacOS/$APP_EXECUTABLE")" == "arm64" ]] || fail "settings app is not arm64-only"
    /usr/libexec/PlistBuddy -c "Print :CFBundleURLTypes:0:CFBundleURLSchemes:0" "$app/Contents/Info.plist" 2>/dev/null | grep -qxF "$SETTINGS_URL_SCHEME" || fail "settings app does not register the $SETTINGS_URL_SCHEME:// URL scheme"
    if [[ "${ALLOW_ADHOC:-}" != "1" ]]; then
        echo "$info" | grep -q "^Authority=Developer ID Application:" || fail "settings app not signed by a Developer ID Application certificate"
        echo "$info" | grep -q "^Timestamp=" || fail "settings app has no secure timestamp"
        echo "$info" | grep -Eq "^TeamIdentifier=[A-Z0-9]{10}$" || fail "settings app has no TeamIdentifier"
    fi
fi

[[ $status -eq 0 ]] && echo "signing verification PASSED" || echo "signing verification FAILED"
exit $status
