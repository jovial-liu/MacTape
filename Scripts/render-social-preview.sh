#!/bin/zsh
set -euo pipefail
SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
STAGING_DIR="$(mktemp -d -t mactape-social)"
trap '/bin/rm -rf "${STAGING_DIR}"' EXIT

command -v ffmpeg >/dev/null || { print -u2 'Install ffmpeg to render this marketing asset.'; exit 1; }
/usr/bin/sips -s format png "${PROJECT_DIR}/assets/social-preview.svg" --out "${STAGING_DIR}/base.png" >/dev/null
ffmpeg -hide_banner -loglevel error -y \
  -i "${STAGING_DIR}/base.png" -i "${PROJECT_DIR}/assets/MacTape-AppIcon-1024.png" \
  -filter_complex '[1:v]scale=432:432[icon];[0:v][icon]overlay=82:104:format=auto' \
  -frames:v 1 "${PROJECT_DIR}/assets/social-preview-v2.png"
