#!/bin/bash
#
# Builds a release MacBull.app (universal when possible) and packages it into a
# drag-to-install .dmg, plus a ReleaseInfo.json marker — the artifacts uploaded
# to a GitHub release.
#
#   ./package.sh
#   => build/MacBull-<version>.dmg
#      build/ReleaseInfo.json
#
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="MacBull"
EXEC_NAME="MacBull"
MIN_OS="13.0"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)"

OUT_DIR="build"
APP_DIR="${OUT_DIR}/${APP_NAME}.app"

# 1. Compile — try a universal (arm64 + x86_64) build, fall back to host-only.
echo "==> Compiling release ${VERSION}…"
if swift build -c release --arch arm64 --arch x86_64 >/dev/null 2>&1; then
    BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
    echo "    universal build ok"
else
    echo "    universal build unavailable — building for $(uname -m) only"
    swift build -c release >/dev/null
    BIN_DIR="$(swift build -c release --show-bin-path)"
fi

# Name the DMG by the architectures actually present (mirrors MarkEdit's
# "-apple-silicon" suffix); a true universal build gets no suffix.
ARCHS="$(lipo -archs "${BIN_DIR}/${EXEC_NAME}")"
echo "    archs: ${ARCHS} → ${BIN_DIR}/${EXEC_NAME}"
case "$ARCHS" in
    *arm64*x86_64* | *x86_64*arm64*) SUFFIX="" ;;
    *arm64*)                         SUFFIX="-apple-silicon" ;;
    *x86_64*)                        SUFFIX="-intel" ;;
    *)                               SUFFIX="" ;;
esac
DMG="${OUT_DIR}/${APP_NAME}-${VERSION}${SUFFIX}.dmg"

# 2. Assemble the .app bundle.
echo "==> Assembling ${APP_DIR}…"
rm -rf "$APP_DIR"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"
cp "${BIN_DIR}/${EXEC_NAME}" "${APP_DIR}/Contents/MacOS/${EXEC_NAME}"
cp Info.plist "${APP_DIR}/Contents/Info.plist"
[[ -f Icon/AppIcon.icns ]] && cp Icon/AppIcon.icns "${APP_DIR}/Contents/Resources/AppIcon.icns"
for g in menubar-awake menubar-asleep; do
    [[ -f "Icon/${g}.pdf" ]] && cp "Icon/${g}.pdf" "${APP_DIR}/Contents/Resources/${g}.pdf"
done
codesign --force --sign - "$APP_DIR" >/dev/null 2>&1 || echo "    (ad-hoc codesign skipped)"

# 3. Build the drag-to-install DMG (app + Applications symlink).
echo "==> Building ${DMG}…"
STAGE="$(mktemp -d)"
cp -R "$APP_DIR" "${STAGE}/${APP_NAME}.app"
ln -s /Applications "${STAGE}/Applications"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" \
    -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGE"

# 4. Release metadata marker (mirrors MarkEdit's ReleaseInfo.json).
printf '{ "minOSVer": "%s" }\n' "$MIN_OS" > "${OUT_DIR}/ReleaseInfo.json"

echo "==> Done:"
echo "    ${DMG} ($(du -h "$DMG" | cut -f1))"
echo "    ${OUT_DIR}/ReleaseInfo.json"
