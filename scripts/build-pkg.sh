#!/bin/bash
# Builds the installer package from the signed binaries in dist/.
#
#   INSTALLER_SIGNING_IDENTITY   Developer ID Installer identity (name or SHA-1). If unset, an UNSIGNED package is built (development only).
#   ALLOW_ADHOC=1                accept ad-hoc binaries (fixture builds; never ship)
#   BUNDLE_ID_PREFIX, VERSION, SERVICE_USER, IPP_PORT, QUEUE_NAME   see scripts/config.sh
#
# Output: build/pkg/ReceiptPrinter-<version>.pkg   (or -unsigned.pkg)
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/config.sh

./scripts/verify-signing.sh

ROOT="$BUILD_DIR/pkgroot"
SCRIPTS="$BUILD_DIR/pkgscripts"
COMPONENT_DIR="$BUILD_DIR/component"
OUT_DIR="$BUILD_DIR/pkg"
rm -rf "$ROOT" "$SCRIPTS" "$COMPONENT_DIR"
mkdir -p "$ROOT$(dirname "$SERVICE_BINARY_PATH")" "$ROOT$(dirname "$PLIST_PATH")" \
         "$ROOT$SUPPORT_DIR/bin" "$ROOT$SUPPORT_DIR/share" "$SCRIPTS" "$COMPONENT_DIR" "$OUT_DIR"

install -m 755 "$DIST_DIR/receipt-printer-service" "$ROOT$SERVICE_BINARY_PATH"
install -m 755 "$DIST_DIR/receipt-printer-updater" "$ROOT$UPDATER_BINARY_PATH"
install -m 755 "$DIST_DIR/receipt-printer-diag" "$ROOT$SUPPORT_DIR/bin/receipt-printer-diag"
install -m 755 "$DIST_DIR/receipt-printer-test" "$ROOT$SUPPORT_DIR/bin/receipt-printer-test"
install -m 755 "$DIST_DIR/receipt-printer-raster-test" "$ROOT$SUPPORT_DIR/bin/receipt-printer-raster-test"
install -m 755 "$DIST_DIR/receipt-printer-config" "$ROOT$SUPPORT_DIR/bin/receipt-printer-config"
[[ -d "$DIST_DIR/$APP_NAME.app" ]] || { echo "missing $DIST_DIR/$APP_NAME.app (run scripts/build.sh first)"; exit 1; }
mkdir -p "$ROOT/Applications"
ditto "$DIST_DIR/$APP_NAME.app" "$ROOT$APP_PATH"
install -m 644 pkg/share/healthcheck.test "$ROOT$SUPPORT_DIR/share/healthcheck.test"
install -m 644 pkg/share/config.default.json "$ROOT$SUPPORT_DIR/share/config.default.json"
install -m 755 scripts/uninstall.sh "$ROOT$SUPPORT_DIR/uninstall.sh"

render_template pkg/launchd/service.plist.template "$ROOT$PLIST_PATH"
chmod 644 "$ROOT$PLIST_PATH"
plutil -lint "$ROOT$PLIST_PATH"
render_template pkg/launchd/updater.plist.template "$ROOT$UPDATER_PLIST_PATH"
chmod 644 "$ROOT$UPDATER_PLIST_PATH"
plutil -lint "$ROOT$UPDATER_PLIST_PATH"

for script in preinstall postinstall lib.sh; do
    render_template "pkg/scripts/$script" "$SCRIPTS/$script"
    bash -n "$SCRIPTS/$script"
done
chmod 755 "$SCRIPTS/preinstall" "$SCRIPTS/postinstall"
chmod 644 "$SCRIPTS/lib.sh"

# A bundle in the payload makes pkgbuild infer a RELOCATABLE component: Installer would then update a copy of the app found
# anywhere on the disk instead of /Applications. Pin it to /Applications and always overwrite.
COMPONENT_PLIST="$BUILD_DIR/component.plist"
pkgbuild --analyze --root "$ROOT" "$COMPONENT_PLIST" > /dev/null
index=0
while /usr/libexec/PlistBuddy -c "Print :$index:RootRelativeBundlePath" "$COMPONENT_PLIST" > /dev/null 2>&1; do
    for setting in "BundleIsRelocatable bool false" "BundleIsVersionChecked bool false" "BundleOverwriteAction string upgrade"; do
        set -- $setting
        /usr/libexec/PlistBuddy -c "Set :$index:$1 $3" "$COMPONENT_PLIST" 2> /dev/null \
            || /usr/libexec/PlistBuddy -c "Add :$index:$1 $2 $3" "$COMPONENT_PLIST"
    done
    index=$((index + 1))
done
echo "component bundles pinned: $index"

pkgbuild --root "$ROOT" \
         --component-plist "$COMPONENT_PLIST" \
         --identifier "$PKG_IDENTIFIER" \
         --version "$VERSION" \
         --install-location / \
         --ownership recommended \
         --scripts "$SCRIPTS" \
         "$COMPONENT_DIR/component.pkg"

# One tiny picker component per printer model. Selecting a model in the installer installs its (empty) marker file; the
# main package's postinstall turns the marker into the model in printer.json. The picker's preinstall clears stale markers.
for model in "${MODEL_IDS[@]}"; do
    picker_root="$BUILD_DIR/picker-root-$model"
    picker_scripts="$BUILD_DIR/picker-scripts-$model"
    rm -rf "$picker_root" "$picker_scripts"
    mkdir -p "$picker_root$SUPPORT_DIR/selected-model" "$picker_scripts"
    : > "$picker_root$SUPPORT_DIR/selected-model/$model"
    printf '#!/bin/bash\nrm -rf "%s/selected-model"\nexit 0\n' "$SUPPORT_DIR" > "$picker_scripts/preinstall"
    chmod 755 "$picker_scripts/preinstall"
    pkgbuild --root "$picker_root" \
             --identifier "$MODEL_PKG_PREFIX.$model" \
             --version "$VERSION" \
             --install-location / \
             --ownership recommended \
             --scripts "$picker_scripts" \
             "$COMPONENT_DIR/picker-$model.pkg"
    grep -q "id=\"model-$model\"" pkg/distribution.xml.template || { echo "pkg/distribution.xml.template has no choice for model $model"; exit 1; }
done

render_template pkg/distribution.xml.template "$BUILD_DIR/distribution.xml"

sign_args=()
output="$OUT_DIR/$PKG_FILE_BASENAME.pkg"
if [[ -n "${INSTALLER_SIGNING_IDENTITY:-}" ]]; then
    sign_args=(--sign "$INSTALLER_SIGNING_IDENTITY" --timestamp)
else
    output="$OUT_DIR/$PKG_FILE_BASENAME-unsigned.pkg"
    echo "INSTALLER_SIGNING_IDENTITY not set: building an UNSIGNED package (cannot be notarized)"
fi

rm -f "$output"
productbuild --distribution "$BUILD_DIR/distribution.xml" --package-path "$COMPONENT_DIR" ${sign_args[@]+"${sign_args[@]}"} "$output"

echo "built $output"
