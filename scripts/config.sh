#!/bin/bash
# Single source of identifiers, paths and defaults. Sourced by the build, signing, packaging and test scripts.
# Every value can be overridden through the environment, except where noted.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

VERSION="${VERSION:-$(tr -d '[:space:]' < "$REPO_ROOT/VERSION")}"
BUNDLE_ID_PREFIX="${BUNDLE_ID_PREFIX:-com.belchuke.receiptprinter}"

SERVICE_LABEL="${SERVICE_LABEL:-$BUNDLE_ID_PREFIX.service}"
PKG_IDENTIFIER="${PKG_IDENTIFIER:-$BUNDLE_ID_PREFIX.pkg}"
MANAGER_IDENTIFIER="$BUNDLE_ID_PREFIX.manager"
UPDATER_LABEL="${UPDATER_LABEL:-$BUNDLE_ID_PREFIX.updater}"

QUEUE_NAME="${QUEUE_NAME:-Receipt_Printer}"
QUEUE_DESCRIPTION="${QUEUE_DESCRIPTION:-Epson Receipt Printer}"
IPP_PORT="${IPP_PORT:-8632}"
PRINTER_URI="ipp://127.0.0.1:$IPP_PORT/ipp/print"

# The executable's FILE NAME must not end in a macOS bundle extension (.service, .app, ...). syspolicyd treats such a
# path as an app bundle, fails to register the plain Mach-O for bundle protection and SIGKILLs it at exec, before main().
# The launchd label ends in ".service" (that is fine for a label); the file is therefore named ".daemon".
SERVICE_BINARY_NAME="${SERVICE_BINARY_NAME:-$BUNDLE_ID_PREFIX.daemon}"
SERVICE_BINARY_PATH="/Library/PrivilegedHelperTools/$SERVICE_BINARY_NAME"
# The updater binary is likewise never named *.service or *.app (see the comment above).
UPDATER_BINARY_NAME="${UPDATER_BINARY_NAME:-$BUNDLE_ID_PREFIX.updater}"
UPDATER_BINARY_PATH="/Library/PrivilegedHelperTools/$UPDATER_BINARY_NAME"
UPDATER_PLIST_PATH="/Library/LaunchDaemons/$UPDATER_LABEL.plist"
PLIST_PATH="/Library/LaunchDaemons/$SERVICE_LABEL.plist"
SUPPORT_DIR="/Library/Application Support/ReceiptPrinter"
LOG_DIR="/Library/Logs/ReceiptPrinter"
SERVICE_USER="${SERVICE_USER:-root}"

MIN_MACOS="13.0"
MIN_MACOS_MAJOR="${MIN_MACOS%%.*}"

DIST_DIR="${DIST_DIR:-$REPO_ROOT/dist}"
BUILD_DIR="${BUILD_DIR:-$REPO_ROOT/build}"
PKG_FILE_BASENAME="ReceiptPrinter-$VERSION"

# Printer models offered by the installer, one picker component package each. Keep in sync with PrinterModel.registry,
# UpdaterConstants.knownModelIDs and the choices in pkg/distribution.xml.template.
MODEL_IDS=(tm-t88v tm-t88vii tm-m30ii)
MODEL_PKG_PREFIX="$BUNDLE_ID_PREFIX.model"

# The settings app (receipt logo). The printer queue's "Open Printer Utility" button opens SETTINGS_URL; macOS passes the
# utility link to LaunchServices as a URL, so a file path fails with error -50 and a registered URL scheme is required.
APP_NAME="Receipt Printer Settings"
APP_EXECUTABLE="receipt-printer-settings"
APP_BUNDLE_ID="$BUNDLE_ID_PREFIX.settings"
APP_PATH="/Applications/$APP_NAME.app"
SETTINGS_URL_SCHEME="receiptprinter"
SETTINGS_URL="$SETTINGS_URL_SCHEME://settings"

BINARIES=(receipt-printer-service receipt-printer-updater receipt-printer-diag receipt-printer-test receipt-printer-raster-test receipt-printer-config)

# Code signing identifier for a built binary name.
signing_identifier() {
    case "$1" in
        receipt-printer-service) echo "$SERVICE_LABEL" ;;
        receipt-printer-updater) echo "$UPDATER_LABEL" ;;
        receipt-printer-diag) echo "$BUNDLE_ID_PREFIX.diag" ;;
        receipt-printer-test) echo "$BUNDLE_ID_PREFIX.test" ;;
        receipt-printer-raster-test) echo "$BUNDLE_ID_PREFIX.raster-test" ;;
        receipt-printer-config) echo "$BUNDLE_ID_PREFIX.config" ;;
        *) echo "unknown binary $1" >&2; return 1 ;;
    esac
}

# render_template INPUT OUTPUT: substitutes @TOKENS@ and fails if any remain.
render_template() {
    sed -e "s|@LABEL@|$SERVICE_LABEL|g" \
        -e "s|@PKG_ID_PREFIX@|$BUNDLE_ID_PREFIX|g" \
        -e "s|@PKG_ID@|$PKG_IDENTIFIER|g" \
        -e "s|@VERSION@|$VERSION|g" \
        -e "s|@QUEUE_NAME@|$QUEUE_NAME|g" \
        -e "s|@QUEUE_DESCRIPTION@|$QUEUE_DESCRIPTION|g" \
        -e "s|@PRINTER_URI@|$PRINTER_URI|g" \
        -e "s|@PORT@|$IPP_PORT|g" \
        -e "s|@SERVICE_BINARY_PATH@|$SERVICE_BINARY_PATH|g" \
        -e "s|@UPDATER_LABEL@|$UPDATER_LABEL|g" \
        -e "s|@UPDATER_BINARY_PATH@|$UPDATER_BINARY_PATH|g" \
        -e "s|@UPDATER_PLIST_PATH@|$UPDATER_PLIST_PATH|g" \
        -e "s|@PLIST_PATH@|$PLIST_PATH|g" \
        -e "s|@SUPPORT_DIR@|$SUPPORT_DIR|g" \
        -e "s|@LOG_DIR@|$LOG_DIR|g" \
        -e "s|@SERVICE_USER@|$SERVICE_USER|g" \
        -e "s|@MODEL_IDS@|${MODEL_IDS[*]}|g" \
        -e "s|@APP_NAME@|$APP_NAME|g" \
        -e "s|@APP_EXECUTABLE@|$APP_EXECUTABLE|g" \
        -e "s|@APP_BUNDLE_ID@|$APP_BUNDLE_ID|g" \
        -e "s|@APP_PATH@|$APP_PATH|g" \
        -e "s|@SETTINGS_URL_SCHEME@|$SETTINGS_URL_SCHEME|g" \
        -e "s|@SETTINGS_URL@|$SETTINGS_URL|g" \
        -e "s|@MIN_MACOS@|$MIN_MACOS|g" \
        -e "s|@MIN_MACOS_MAJOR@|$MIN_MACOS_MAJOR|g" \
        "$1" > "$2"
    if grep -n '@[A-Z_]*@' "$2"; then
        echo "unrendered tokens remain in $2" >&2
        return 1
    fi
}
