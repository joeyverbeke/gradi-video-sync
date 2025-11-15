#!/usr/bin/env bash
# Phase 5 helper: install VLC Sync Video Looper and switch from desktop autostart.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Please run this script with sudo."
  exit 1
fi

TARGET_USER="${TARGET_USER:-${SUDO_USER:-pi}}"
TARGET_UID="$(id -u "$TARGET_USER")"
TARGET_GID="$(id -g "$TARGET_USER")"
REPO_DIR="${REPO_DIR:-/opt/vlc_sync_video_looper}"
REPO_URL="${REPO_URL:-git@github.com:dreerr/vlc_sync_video_looper.git}"
CONFIG_PATH="${CONFIG_PATH:-/media/videos/video_looper.conf}"
MODE="${MODE:-controller}"
VIDEO_FILE="${VIDEO_FILE:-compress-front.mp4}"
MEDIA_DIR="${MEDIA_DIR:-/media/videos}"
WORKERS="${WORKERS:-}"
CONTROLLER_ADDR="${CONTROLLER_ADDR:-192.168.0.21:6001}"
RC_PORT="${RC_PORT:-6001}"
VLC_FLAGS="${VLC_FLAGS:---extraintf rc --no-video-title-show --fullscreen}"
DISPLAY_ENV="${DISPLAY_ENV:-:0}"
AUTOSTART_FILE="${AUTOSTART_FILE:-/home/$TARGET_USER/.config/autostart/vlc-loop.desktop}"

log() { echo "[phase5] $*"; }

log "Installing dependencies"
apt-get update -y
apt-get install -y git python3-venv

CURRENT_HOST="$(hostname)"
if ! grep -q "$CURRENT_HOST" /etc/hosts; then
  log "Ensuring /etc/hosts contains 127.0.1.1 entry for $CURRENT_HOST"
  echo "127.0.1.1	$CURRENT_HOST" >> /etc/hosts
fi

if [[ -d "$REPO_DIR/.git" ]]; then
  log "Repository already exists; pulling latest changes"
  git -C "$REPO_DIR" pull --ff-only
else
  log "Cloning VLC Sync Video Looper via SSH into $REPO_DIR"
  git clone "$REPO_URL" "$REPO_DIR"
fi

log "Setting up Python virtual environment"
python3 -m venv "$REPO_DIR/venv"
"$REPO_DIR/venv/bin/pip" install --upgrade pip
"$REPO_DIR/venv/bin/pip" install -r "$REPO_DIR/requirements.txt"
chown -R "$TARGET_USER":"$TARGET_USER" "$REPO_DIR"

RUNTIME_DIR="/run/user/$TARGET_UID"
install -d -m 700 "$RUNTIME_DIR"
chown "$TARGET_USER":"$TARGET_USER" "$RUNTIME_DIR"

SERVICE_FILE="/etc/systemd/system/vlc_sync_video_looper.service"
log "Writing systemd service to $SERVICE_FILE"
cat >"$SERVICE_FILE" <<EOF
[Unit]
Description=VLC Sync Video Looper
After=network.target

[Service]
ExecStart=$REPO_DIR/venv/bin/python $REPO_DIR/video_looper.py --media-dir $MEDIA_DIR --rc-port $RC_PORT
WorkingDirectory=$REPO_DIR
Restart=always
User=$TARGET_USER
Group=$TARGET_USER
Environment=XDG_RUNTIME_DIR=$RUNTIME_DIR
Environment=DISPLAY=$DISPLAY_ENV

[Install]
WantedBy=multi-user.target
EOF

log "Writing config to $CONFIG_PATH"
install -d -m 775 "$(dirname "$CONFIG_PATH")"
cat >"$CONFIG_PATH" <<EOF
MODE=$MODE
MEDIA_DIR=$MEDIA_DIR
VIDEO_FILE=$VIDEO_FILE
SCREEN=0
STARTUP_DELAY=2
WORKERS=$WORKERS
CONTROLLER=$CONTROLLER_ADDR
BROADCAST_PORT=$RC_PORT
VLC_FLAGS=$VLC_FLAGS
EOF
chown "$TARGET_USER":"$TARGET_USER" "$CONFIG_PATH"

if [[ -f "$AUTOSTART_FILE" ]]; then
  log "Disabling legacy desktop autostart ($AUTOSTART_FILE)"
  rm -f "$AUTOSTART_FILE"
fi

log "Enabling VLC Sync Video Looper systemd service"
systemctl enable --now vlc_sync_video_looper.service

log "Done. Use 'journalctl -fu vlc_sync_video_looper' to verify playback."
