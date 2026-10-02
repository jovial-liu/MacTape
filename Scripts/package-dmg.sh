#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
VERSION="${VERSION:-0.1.0}"
DMG_PATH="${PROJECT_DIR}/dist/MacTape-${VERSION}.dmg"
STAGING_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/mactape-dmg.XXXXXX")"
trap '/bin/rm -rf "${STAGING_DIR}"' EXIT

"${SCRIPT_DIR}/build-app.sh"
/bin/cp -R "${PROJECT_DIR}/dist/MacTape.app" "${STAGING_DIR}/MacTape.app"
/bin/ln -s /Applications "${STAGING_DIR}/Applications"
/bin/rm -f "${DMG_PATH}"
/usr/bin/hdiutil create -volname "MacTape" -srcfolder "${STAGING_DIR}" -ov -format UDZO "${DMG_PATH}"

print "Created ${DMG_PATH}"
