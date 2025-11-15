#!/usr/bin/env bash
# Phase 4 helper: set up /media/videos mount and retarget VLC autostart.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (use sudo)."
  exit 1
fi

TARGET_USER="${TARGET_USER:-${SUDO_USER:-pi}}"
MOUNT_POINT="${MOUNT_POINT:-/media/videos}"
DEVICE="${DEVICE:-}"
FSTYPE="${FSTYPE:-ext4}"
VIDEO_FILE="${VIDEO_FILE:-$MOUNT_POINT/compress-front.mp4}"
AUTOSTART_NAME="${AUTOSTART_NAME:-vlc-loop.desktop}"

if [[ -z "$DEVICE" ]]; then
  echo "Set DEVICE=/dev/sdX# (partition to use) when invoking this script."
  exit 1
fi

USER_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
AUTOSTART_FILE="$USER_HOME/.config/autostart/$AUTOSTART_NAME"

log() { echo "[phase4] $*"; }

log "Formatting $DEVICE as $FSTYPE"
mkfs -t "$FSTYPE" "$DEVICE"

UUID=$(blkid -s UUID -o value "$DEVICE")
log "Detected UUID: $UUID"

log "Creating mount point $MOUNT_POINT"
install -d -m 775 "$MOUNT_POINT"
chown "$TARGET_USER":"$TARGET_USER" "$MOUNT_POINT"

if ! grep -q "$MOUNT_POINT" /etc/fstab; then
  log "Adding entry to /etc/fstab"
  echo "UUID=$UUID  $MOUNT_POINT  $FSTYPE  defaults,uid=$(id -u "$TARGET_USER"),gid=$(id -g "$TARGET_USER"),fmask=0022,dmask=0022  0  2" >> /etc/fstab
else
  log "fstab already contains $MOUNT_POINT entry; skipping"
fi

log "Mounting $MOUNT_POINT"
mount "$MOUNT_POINT"

log "Copying any existing demo asset into $MOUNT_POINT"
if [[ -f "$VIDEO_FILE" ]]; then
  log "Target file $VIDEO_FILE already present; skipping copy"
else
  if [[ -f "/home/$TARGET_USER/Desktop/compress-1.mp4" ]]; then
    cp "/home/$TARGET_USER/Desktop/compress-1.mp4" "$VIDEO_FILE"
    chown "$TARGET_USER":"$TARGET_USER" "$VIDEO_FILE"
  fi
fi

if [[ -f "$AUTOSTART_FILE" ]]; then
  log "Updating autostart file $AUTOSTART_FILE to point at $VIDEO_FILE"
  sed -i "s|/home/$TARGET_USER/Desktop/[^']*|$VIDEO_FILE|g" "$AUTOSTART_FILE"
else
  log "Autostart file not found; re-run phase3 script if needed."
fi

log "Done. Reboot or run 'systemctl restart display-manager' to pick up the new media path."
