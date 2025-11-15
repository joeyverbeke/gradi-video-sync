#!/usr/bin/env bash
# Phase 1 helper: validate Raspberry Pi 5 HEVC playback prerequisites.
set -euo pipefail

CONFIG_FILE_DEFAULT="/boot/firmware/config.txt"
VIDEO_DEFAULT="$HOME/Videos/test.mp4"
CONFIG_FILE="${CONFIG_FILE:-$CONFIG_FILE_DEFAULT}"
VIDEO_FILE="${1:-$VIDEO_DEFAULT}"

pass=()
warn=()
fail=()

log_section() {
  echo
  echo "=== $1 ==="
}

check_file_contains() {
  local file="$1"
  local pattern="$2"
  if sudo sh -c "[ -f \"$file\" ]"; then
    if sudo grep -qE "$pattern" "$file"; then
      pass+=("$3")
      echo "[OK] $3"
    else
      fail+=("$3 (missing pattern '$pattern' in $file)")
      echo "[WARN] $3"
    fi
  else
    fail+=("$3 (file $file missing)")
    echo "[WARN] $3"
  fi
}

log_section "GPU firmware config"
check_file_contains "$CONFIG_FILE" '^dtoverlay=vc4-kms-v3d' "Full KMS overlay enabled"
check_file_contains "$CONFIG_FILE" '^arm_64bit=1' "64-bit kernel enabled"

log_section "Kernel modules"
if lsmod | grep -q '^vc4'; then
  pass+=("vc4 module loaded")
  echo "[OK] vc4 kernel module present"
else
  fail+=("vc4 module not loaded")
  echo "[WARN] vc4 kernel module missing"
fi

if lsmod | grep -q 'rpi_hevc_dec'; then
  pass+=("rpi_hevc_dec module loaded")
  echo "[OK] rpi_hevc_dec module present"
elif lsmod | grep -q 'rpivid'; then
  pass+=("rpivid module loaded")
  echo "[OK] rpivid module present"
else
  warn+=("No rpi_hevc_dec/rpivid decoder module detected")
  echo "[WARN] Hardware decoder kernel module not detected"
fi

log_section "Packages"
needed_pkgs=(vlc vlc-plugin-base vainfo)
missing=()
for pkg in "${needed_pkgs[@]}"; do
  if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "installed"; then
    echo "[OK] $pkg installed"
  else
    missing+=("$pkg")
  fi
done
if [ "${#missing[@]}" -gt 0 ]; then
  fail+=("Missing packages: ${missing[*]}")
  echo "[WARN] Missing packages: ${missing[*]}"
else
  pass+=("Required packages installed")
fi

log_section "vainfo HEVC decoder"
if command -v vainfo >/dev/null 2>&1; then
  VAINFO_OUTPUT=$(vainfo --display drm --device /dev/dri/renderD128 2>&1 || true)
  if grep -qi hevc <<<"$VAINFO_OUTPUT"; then
    pass+=("HEVC decoder advertised via VAAPI")
    echo "[OK] HEVC VAAPI support detected"
  else
    warn+=("vainfo could not find HEVC support (driver may be missing); output saved above")
    echo "[WARN] HEVC VAAPI support missing"
    echo "$VAINFO_OUTPUT"
  fi
else
  warn+=("vainfo command not found")
  echo "[WARN] vainfo command not found"
fi

log_section "Test video availability"
if [ -f "$VIDEO_FILE" ]; then
  pass+=("Test video present at $VIDEO_FILE")
  if command -v ffprobe >/dev/null 2>&1; then
    ffprobe -v error -select_streams v:0 -show_entries stream=codec_name,width,height,avg_frame_rate \
      -of default=noprint_wrappers=1 "$VIDEO_FILE" 2>/dev/null || true
  else
    echo "[INFO] ffprobe not installed; skipping codec dump"
  fi
else
  fail+=("Test video missing at $VIDEO_FILE")
  echo "[WARN] Test video missing at $VIDEO_FILE"
fi

log_section "Manual steps"
cat <<INSTRUCTIONS
1. Launch VLC manually:
   vlc --fullscreen --loop --no-video-title-show "$VIDEO_FILE"
2. While playing, open Tools -> Codec Information and verify "Hardware decoding: yes".
3. Run htop in another terminal to confirm CPU load stays low (<40% total).
4. Stop playback with Ctrl+C when finished.
INSTRUCTIONS

log_section "Summary"
echo "Passes: ${#pass[@]}"
printf '  - %s\n' "${pass[@]}"
if [ "${#warn[@]}" -gt 0 ]; then
  echo "Warnings: ${#warn[@]}"
  printf '  - %s\n' "${warn[@]}"
fi
if [ "${#fail[@]}" -gt 0 ]; then
  echo "Failures: ${#fail[@]}"
  printf '  - %s\n' "${fail[@]}"
  exit 1
fi
echo "All critical checks passed."
