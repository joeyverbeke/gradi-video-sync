#!/usr/bin/env bash
# Remove legacy VLC/looper systemd services and desktop autostart entries.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Please run this reset script with sudo."
  exit 1
fi

DRY_RUN="${DRY_RUN:-0}"

log_section() {
  printf '\n[%s] %s\n' "$(date +'%H:%M:%S')" "$*"
}

run_cmd() {
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '[dry-run] %s\n' "$*"
    return 0
  fi
  "$@"
}

disable_units() {
  local -a units=(
    vlc-sync-video-looper.service
    vlc-sync-video-looper@.service
    vlcsync.service
    video-sync.service
    rpi-video-sync-looper.service
    omxplayer-sync.service
    mp4museum.service
    vlc-screen0.service
    vlc-screen1.service
    gradi-vlc-screen0.service
    gradi-vlc-screen1.service
    gradi-vlcsync-gated.service
  )

  log_section "Disabling stale systemd units"
  local unit
  for unit in "${units[@]}"; do
    if systemctl cat "$unit" >/dev/null 2>&1; then
      printf '  - removing %s\n' "$unit"
      run_cmd systemctl disable --now "$unit" || true
      run_cmd rm -f "/etc/systemd/system/$unit" || true
    fi
  done
  run_cmd systemctl daemon-reload
}

stop_vlc_processes() {
  log_section "Stopping any stray VLC processes"
  run_cmd pkill -x vlc || true
  run_cmd pkill -x cvlc || true
}

cleanup_autostart() {
  local autostart_dir="/home/${SUDO_USER:-$USER}/.config/autostart"
  log_section "Removing desktop autostart shortcuts that launch VLC"
  if [[ -d "$autostart_dir" ]]; then
    local files_removed=0
    shopt -s nullglob
    for desktop in "$autostart_dir"/*vlc*.desktop; do
      printf '  - deleting %s\n' "$desktop"
      run_cmd rm -f "$desktop"
      files_removed=1
    done
    shopt -u nullglob
    if [[ $files_removed -eq 0 ]]; then
      echo "  (none found)"
    fi
  else
    echo "  (autostart dir not present)"
  fi
}

disable_units
stop_vlc_processes
cleanup_autostart

log_section "Reset complete"
