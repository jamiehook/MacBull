#!/bin/bash
#
# Builds MacBull.app from the Swift package and (optionally) installs it.
#
#   ./build.sh           build the .app into ./build
#   ./build.sh install   build, then copy to /Applications and launch
#
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="MacBull"
EXEC_NAME="MacBull"
RELEASE_DIR=".build/release"
OUT_DIR="build"
APP_DIR="${OUT_DIR}/${APP_NAME}.app"

echo "==> Compiling (release)…"
swift build -c release

echo "==> Assembling ${APP_DIR}…"
rm -rf "$APP_DIR"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${RELEASE_DIR}/${EXEC_NAME}" "${APP_DIR}/Contents/MacOS/${EXEC_NAME}"
cp Info.plist "${APP_DIR}/Contents/Info.plist"

if [[ -f Icon/AppIcon.icns ]]; then
    cp Icon/AppIcon.icns "${APP_DIR}/Contents/Resources/AppIcon.icns"
else
    echo "    (Icon/AppIcon.icns not found — run ./Icon/make.sh first)"
fi

# Menu-bar bull glyphs (template PDFs)
for g in menubar-awake menubar-asleep; do
    [[ -f "Icon/${g}.pdf" ]] && cp "Icon/${g}.pdf" "${APP_DIR}/Contents/Resources/${g}.pdf"
done

# Ad-hoc signature so Launch-at-login (SMAppService) and Gatekeeper behave.
echo "==> Code signing (ad-hoc)…"
codesign --force --sign - "$APP_DIR" >/dev/null 2>&1 || \
    echo "    (codesign skipped — Launch-at-login may be unavailable)"

echo "==> Built: ${APP_DIR}"

if [[ "${1:-}" == "install" ]]; then
    DEST="/Applications/${APP_NAME}.app"
    echo "==> Installing to ${DEST}…"
    osascript -e "quit app \"${APP_NAME}\"" >/dev/null 2>&1 || true
    rm -rf "$DEST"
    cp -R "$APP_DIR" "$DEST"
    open "$DEST"
    echo "==> Launched. Look for the bull icon in the menu bar."
fi
