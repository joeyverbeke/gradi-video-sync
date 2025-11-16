#!/usr/bin/env bash
# Install the single-screen VLC worker unit on a Raspberry Pi.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Please run this installer with sudo."
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

video="/media/videos/front.mp4"
display="0"
rc_port="5001"

usage() {
  cat <<'EOF'
Usage: sudo ./scripts/install_worker_units.sh [options]

Options:
  --video PATH     Video file to loop (default: /media/videos/front.mp4)
  --display NUM    VLC fullscreen screen index (default: 0)
  --rc-port NUM    RC port to listen on (default: 5001)
  -h, --help       Show this message

Use these flags to point at the correct media for the current Pi
(e.g., /media/videos/back.mp4).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --video)
      video="$2"; shift 2;;
    --display)
      display="$2"; shift 2;;
    --rc-port)
      rc_port="$2"; shift 2;;
    -h|--help)
      usage; exit 0;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1;;
  esac
done

log_section() {
  printf '\n[%s] %s\n' "$(date +'%H:%M:%S')" "$*"
}

warn_if_missing() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    printf 'WARNING: video file %s not found yet. VLC will stay black until it exists.\n' "$path"
  fi
}

write_env() {
  local path="$1"
  cat >"$path" <<EOF
GRADI_VLC_VIDEO="$video"
GRADI_VLC_DISPLAY="$display"
GRADI_VLC_RC_PORT="$rc_port"
EOF
}

warn_if_missing "$video"

log_section "Installing VLC worker dependencies"
apt-get update -y
apt-get install -y vlc netcat-openbsd

log_section "Deploying systemd unit"
install -Dm644 "$REPO_ROOT/systemd/gradi-vlc-screen0.service" /etc/systemd/system/gradi-vlc-screen0.service

log_section "Writing environment overrides"
write_env /etc/default/gradi-vlc-screen0

log_section "Enabling services"
systemctl daemon-reload
systemctl enable --now gradi-vlc-screen0.service

log_section "Active VLC RC ports"
ss -ltnp | grep -E ":${rc_port}" || true

log_section "Worker install complete"
