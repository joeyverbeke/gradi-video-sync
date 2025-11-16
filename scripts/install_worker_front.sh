#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run this front-screen installer with sudo."
  exit 1
fi

MEDIA_FRONT="${MEDIA_FRONT:-/media/videos/front.mp4}"
FRONT_DISPLAY="${FRONT_DISPLAY:-0}"
FRONT_PORT="${FRONT_PORT:-5001}"
RUN_USER="${RUN_USER:-${SUDO_USER:-pi}}"

./scripts/install_worker_units.sh \
  --screen0-only \
  --video "$MEDIA_FRONT" \
  --display "$FRONT_DISPLAY" \
  --rc-port "$FRONT_PORT" \
  --user "$RUN_USER"
