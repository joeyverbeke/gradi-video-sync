#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run this script with sudo on gradi-compress."
  exit 1
fi

./scripts/install_worker_units.sh \
  --video /media/videos/front.mp4 \
  --screen1-video /media/videos/back.mp4 \
  --screen1-display 1 \
  --screen1-port 5002 \
  --screen1-extra-args "--no-audio" \
  --user joeyverbeke
