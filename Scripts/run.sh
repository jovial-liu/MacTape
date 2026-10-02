#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
"${SCRIPT_DIR}/build-app.sh"
/usr/bin/open "${SCRIPT_DIR:h}/dist/MacTape.app"
