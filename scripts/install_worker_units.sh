#!/usr/bin/env bash
# Install the single-screen VLC worker unit on a Raspberry Pi.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Please run this installer with sudo."
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

screen0_video="/media/videos/front.mp4"
screen0_display="0"
screen0_port="5001"
screen1_video="/media/videos/back.mp4"
screen1_display="1"
screen1_port="5002"
screen1_enabled="${SCREEN1_ENABLED:-0}"
run_user="${RUN_USER:-${SUDO_USER:-pi}}"
xdisplay=":0"

usage() {
  cat <<'EOF'
Usage: sudo ./scripts/install_worker_units.sh [options]

Options:
  --video PATH         Video file for screen 0 (default: /media/videos/front.mp4)
  --display NUM        VLC fullscreen screen index for screen 0 (default: 0)
  --rc-port NUM        RC port for screen 0 (default: 5001)
  --screen1-video PATH Video file for screen 1 (enables second screen; default: /media/videos/back.mp4)
  --screen1-display NUM  Screen index for screen 1 (default: 1)
  --screen1-port NUM    RC port for screen 1 (default: 5002)
  --user NAME      System user that should own the VLC process (default: detected sudo user or pi)
  --xdisplay DISP  X11 display to target (default: :0)
  -h, --help       Show this message

Use these flags to point at the correct media for the current Pi
(e.g., /media/videos/back.mp4).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --video)
      screen0_video="$2"; shift 2;;
    --display)
      screen0_display="$2"; shift 2;;
    --rc-port)
      screen0_port="$2"; shift 2;;
    --screen1-video)
      screen1_video="$2"; screen1_enabled=1; shift 2;;
    --screen1-display)
      screen1_display="$2"; screen1_enabled=1; shift 2;;
    --screen1-port)
      screen1_port="$2"; screen1_enabled=1; shift 2;;
    --user)
      run_user="$2"; shift 2;;
    --xdisplay)
      xdisplay="$2"; shift 2;;
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
  local video="$2"
  local display="$3"
  local port="$4"
  cat >"$path" <<EOF
GRADI_VLC_VIDEO="$video"
GRADI_VLC_DISPLAY="$display"
GRADI_VLC_RC_PORT="$port"
EOF
}

write_override() {
  local service="$1"
  local dir="/etc/systemd/system/${service}.service.d"
  install -d -m 755 "$dir"
  cat >"$dir/override.conf" <<EOF
[Service]
User=$run_user
Environment=DISPLAY=$xdisplay
EOF
}

warn_if_missing "$screen0_video"
if [[ "$screen1_enabled" == "1" ]]; then
  warn_if_missing "$screen1_video"
fi

log_section "Installing VLC worker dependencies"
apt-get update -y
apt-get install -y vlc netcat-openbsd

log_section "Deploying systemd unit(s)"
install -Dm644 "$REPO_ROOT/systemd/gradi-vlc-screen0.service" /etc/systemd/system/gradi-vlc-screen0.service
if [[ "$screen1_enabled" == "1" ]]; then
  install -Dm644 "$REPO_ROOT/systemd/gradi-vlc-screen1.service" /etc/systemd/system/gradi-vlc-screen1.service
fi

log_section "Writing environment overrides"
write_env /etc/default/gradi-vlc-screen0 "$screen0_video" "$screen0_display" "$screen0_port"
write_override "gradi-vlc-screen0"
if [[ "$screen1_enabled" == "1" ]]; then
  write_env /etc/default/gradi-vlc-screen1 "$screen1_video" "$screen1_display" "$screen1_port"
  write_override "gradi-vlc-screen1"
fi

log_section "Enabling services"
systemctl daemon-reload
if [[ "$screen1_enabled" == "1" ]]; then
  systemctl enable --now gradi-vlc-screen0.service gradi-vlc-screen1.service
else
  systemctl enable --now gradi-vlc-screen0.service
  if systemctl cat gradi-vlc-screen1.service >/dev/null 2>&1; then
    systemctl disable --now gradi-vlc-screen1.service || true
  fi
fi

log_section "Active VLC RC ports"
ports="$screen0_port"
if [[ "$screen1_enabled" == "1" ]]; then
  ports="$ports|$screen1_port"
fi
ss -ltnp | grep -E ":($ports)" || true

log_section "Worker install complete"
