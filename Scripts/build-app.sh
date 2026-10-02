#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
CONFIGURATION="${CONFIGURATION:-release}"
APP_DIR="${PROJECT_DIR}/dist/MacTape.app"
CONTENTS_DIR="${APP_DIR}/Contents"
BUILD_OPTIONS=(--build-system native -c "${CONFIGURATION}")
if [[ "${UNIVERSAL:-0}" == 1 ]]; then
  BUILD_OPTIONS+=(--arch arm64 --arch x86_64)
fi

cd "${PROJECT_DIR}"
swift build "${BUILD_OPTIONS[@]}" --product MacTapeDesktop
BINARY_PATH="$(swift build "${BUILD_OPTIONS[@]}" --show-bin-path)/MacTapeDesktop"

/bin/rm -rf "${APP_DIR}"
/bin/mkdir -p "${CONTENTS_DIR}/MacOS" "${CONTENTS_DIR}/Resources"
/bin/cp "${BINARY_PATH}" "${CONTENTS_DIR}/MacOS/MacTape"
/bin/cp "${PROJECT_DIR}/Packaging/Info.plist" "${CONTENTS_DIR}/Info.plist"

SOURCE_ICON="${PROJECT_DIR}/assets/MacTape-AppIcon-1024.png"
if [[ -f "${SOURCE_ICON}" ]]; then
  ICONSET="${PROJECT_DIR}/.build/MacTape.iconset"
  /bin/rm -rf "${ICONSET}"
  /bin/mkdir -p "${ICONSET}"
  for SIZE in 16 32 128 256 512; do
    /usr/bin/sips -z "${SIZE}" "${SIZE}" "${SOURCE_ICON}" --out "${ICONSET}/icon_${SIZE}x${SIZE}.png" >/dev/null
    DOUBLE_SIZE="$((SIZE * 2))"
    /usr/bin/sips -z "${DOUBLE_SIZE}" "${DOUBLE_SIZE}" "${SOURCE_ICON}" --out "${ICONSET}/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
  done
  /usr/bin/iconutil -c icns "${ICONSET}" -o "${CONTENTS_DIR}/Resources/AppIcon.icns"
fi

SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
/usr/bin/codesign --force --deep --options runtime --entitlements "${PROJECT_DIR}/Packaging/MacTape.entitlements" --sign "${SIGN_IDENTITY}" "${APP_DIR}"
/usr/bin/codesign --verify --deep --strict "${APP_DIR}"
/usr/bin/plutil -lint "${CONTENTS_DIR}/Info.plist"

print "Built ${APP_DIR}"
