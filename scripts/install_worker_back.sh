#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run this back-screen installer with sudo."
  exit 1
fi

MEDIA_BACK="${MEDIA_BACK:-/media/videos/back.mp4}"
BACK_DISPLAY="${BACK_DISPLAY:-1}"
BACK_PORT="${BACK_PORT:-5002}"
RUN_USER="${RUN_USER:-${SUDO_USER:-pi}}"

./scripts/install_worker_units.sh \
  --screen1-only \
  --screen1-video "$MEDIA_BACK" \
  --screen1-display "$BACK_DISPLAY" \
  --screen1-port "$BACK_PORT" \
  --user "$RUN_USER"
