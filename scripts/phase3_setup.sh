#!/usr/bin/env bash
# Phase 3 helper: configure auto-login, VLC autostart, and screen blanking settings.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Please run this script with sudo."
  exit 1
fi

TARGET_USER="${TARGET_USER:-${SUDO_USER:-pi}}"
VIDEO_FILE="${VIDEO_FILE:-/media/videos/compress-front.mp4}"
AUTOSTART_NAME="${AUTOSTART_NAME:-vlc-loop.desktop}"

USER_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
if [[ -z "$USER_HOME" ]]; then
  echo "Could not determine home directory for user $TARGET_USER"
  exit 1
fi

log() { echo "[phase3] $*"; }

log "Setting boot behaviour to desktop autologin (user: $TARGET_USER)"
raspi-config nonint do_boot_behaviour B4

log "Disabling screen blanking via raspi-config"
raspi-config nonint do_blanking 1

AUTOSTART_DIR="$USER_HOME/.config/autostart"
log "Creating autostart entry in $AUTOSTART_DIR"
install -d -m 755 "$AUTOSTART_DIR"
AUTOSTART_FILE="$AUTOSTART_DIR/$AUTOSTART_NAME"
cat >"$AUTOSTART_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=VLC Loop
Comment=Launch VLC in fullscreen loop on login
Exec=/usr/bin/env bash -lc 'export DISPLAY=:0; xset s off -dpms; /usr/bin/vlc --fullscreen --loop --no-video-title-show "$VIDEO_FILE"'
X-GNOME-Autostart-enabled=true
EOF
chown "$TARGET_USER":"$TARGET_USER" "$AUTOSTART_FILE"

log "Autostart file written to $AUTOSTART_FILE"
log "Set VIDEO_FILE env var before invoking this script to point at another clip if needed."
log "Reboot to validate: sudo reboot"
