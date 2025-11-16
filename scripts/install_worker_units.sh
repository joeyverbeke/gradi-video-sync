#!/usr/bin/env bash
# Install one or both VLC worker units on a Raspberry Pi.
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
screen0_enabled="${SCREEN0_ENABLED:-1}"
screen1_video="/media/videos/back.mp4"
screen1_display="1"
screen1_port="5002"
screen1_enabled="${SCREEN1_ENABLED:-0}"
screen0_extra_args="${SCREEN0_EXTRA_ARGS:-}"
screen1_extra_args="${SCREEN1_EXTRA_ARGS:-}"
default_audio_device="${AUDIO_DEVICE:-}"
screen0_audio_device="${SCREEN0_AUDIO_DEVICE:-$default_audio_device}"
screen1_audio_device="${SCREEN1_AUDIO_DEVICE:-$default_audio_device}"
run_user="${RUN_USER:-${SUDO_USER:-pi}}"
xdisplay=":0"

usage() {
  cat <<'EOF'
Usage: sudo ./scripts/install_worker_units.sh [options]

Options:
  --video PATH         Video file for screen 0 (default: /media/videos/front.mp4)
  --display NUM        VLC fullscreen screen index for screen 0 (default: 0)
  --rc-port NUM        RC port for screen 0 (default: 5001)
  --audio-device NAME  ALSA/Pulse audio device for screen 0 (default: env AUDIO_DEVICE or unset)
  --screen0-only       Manage only screen 0 (skip screen 1 this run)
  --extra-args "FLAGS" Extra VLC CLI flags for screen 0 (default: none)
  --screen1-video PATH Video file for screen 1 (enables second screen; default: /media/videos/back.mp4)
  --screen1-display NUM  Screen index for screen 1 (default: 1)
  --screen1-port NUM    RC port for screen 1 (default: 5002)
  --screen1-audio-device NAME  ALSA/Pulse audio device for screen 1 (default: env AUDIO_DEVICE or unset)
  --screen1-only       Manage only screen 1 (screen 0 untouched)
  --screen1-extra-args "FLAGS"  Extra VLC CLI flags for screen 1 (default: none)
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
    --audio-device)
      screen0_audio_device="$2"; shift 2;;
    --rc-port)
      screen0_port="$2"; shift 2;;
    --screen0-only)
      screen0_enabled="1"
      screen1_enabled="0"
      shift;;
    --extra-args)
      screen0_extra_args="$2"; shift 2;;
    --screen1-video)
      screen1_video="$2"; screen1_enabled=1; shift 2;;
    --screen1-display)
      screen1_display="$2"; screen1_enabled=1; shift 2;;
    --screen1-port)
      screen1_port="$2"; screen1_enabled=1; shift 2;;
    --screen1-only)
      screen0_enabled="0"
      screen1_enabled="1"
      shift;;
    --screen1-audio-device)
      screen1_audio_device="$2"; screen1_enabled=1; shift 2;;
    --screen1-extra-args)
      screen1_extra_args="$2"; screen1_enabled=1; shift 2;;
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

if [[ "$screen0_enabled" != "1" && "$screen1_enabled" != "1" ]]; then
  echo "At least one screen must be selected." >&2
  exit 1
fi

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
  local extra="$5"
  local audio_device="$6"
  cat >"$path" <<EOF
GRADI_VLC_VIDEO="$video"
GRADI_VLC_DISPLAY="$display"
GRADI_VLC_RC_PORT="$port"
GRADI_VLC_EXTRA_FLAGS="$extra"
GRADI_VLC_AUDIO_DEVICE="$audio_device"
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

if [[ "$screen0_enabled" == "1" ]]; then
  warn_if_missing "$screen0_video"
fi
if [[ "$screen1_enabled" == "1" ]]; then
  warn_if_missing "$screen1_video"
fi

log_section "Installing VLC worker dependencies"
apt-get update -y
apt-get install -y vlc netcat-openbsd

log_section "Deploying systemd unit(s)"
if [[ "$screen0_enabled" == "1" ]]; then
  install -Dm644 "$REPO_ROOT/systemd/gradi-vlc-screen0.service" /etc/systemd/system/gradi-vlc-screen0.service
fi
if [[ "$screen1_enabled" == "1" ]]; then
  install -Dm644 "$REPO_ROOT/systemd/gradi-vlc-screen1.service" /etc/systemd/system/gradi-vlc-screen1.service
fi

log_section "Writing environment overrides"
if [[ "$screen0_enabled" == "1" ]]; then
  write_env /etc/default/gradi-vlc-screen0 "$screen0_video" "$screen0_display" "$screen0_port" "$screen0_extra_args" "$screen0_audio_device"
  write_override "gradi-vlc-screen0"
fi
if [[ "$screen1_enabled" == "1" ]]; then
  write_env /etc/default/gradi-vlc-screen1 "$screen1_video" "$screen1_display" "$screen1_port" "$screen1_extra_args" "$screen1_audio_device"
  write_override "gradi-vlc-screen1"
fi

log_section "Enabling services"
systemctl daemon-reload
if [[ "$screen0_enabled" == "1" ]]; then
  systemctl enable --now gradi-vlc-screen0.service
fi
if [[ "$screen1_enabled" == "1" ]]; then
  systemctl enable --now gradi-vlc-screen1.service
fi

log_section "Active VLC RC ports"
ports=()
if [[ "$screen0_enabled" == "1" ]]; then
  ports+=("$screen0_port")
fi
if [[ "$screen1_enabled" == "1" ]]; then
  ports+=("$screen1_port")
fi
if [[ ${#ports[@]} -gt 0 ]]; then
  regex=$(printf '%s|' "${ports[@]}")
  regex="(${regex%|})"
  ss -ltnp | grep -E ":$regex" || true
fi

log_section "Worker install complete"
