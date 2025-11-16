#!/usr/bin/env bash
# Install or redeploy the vlcsync controller user service on the designated Pi.
set -euo pipefail

if [[ $EUID -eq 0 ]]; then
  echo "Run this controller installer as the non-root user that will own the service."
  exit 1
fi

usage() {
  cat <<'EOF'
Usage: ./scripts/install_controller_service.sh [--skip-deps]

  --skip-deps   Skip apt/pip installation steps (useful when redeploying
                after editing systemd/gradi-vlcsync-gated.user.service).
  -h, --help    Show this message.
EOF
}

INSTALL_DEPS=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-deps)
      INSTALL_DEPS=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SERVICE_NAME="gradi-vlcsync-gated.service"
SERVICE_SRC="$REPO_ROOT/systemd/gradi-vlcsync-gated.user.service"
SERVICE_DEST="$HOME/.config/systemd/user/$SERVICE_NAME"

log_section() {
  printf '\n[%s] %s\n' "$(date +'%H:%M:%S')" "$*"
}

if [[ $INSTALL_DEPS -eq 1 ]]; then
  log_section "Installing controller dependencies"
  sudo apt-get update -y
  sudo apt-get install -y python3-pip netcat-openbsd

  log_section "Installing vlcsync Python module"
  export PIP_BREAK_SYSTEM_PACKAGES=1
  python3 -m pip install --user --upgrade pip
  python3 -m pip install --user --upgrade vlcsync
else
  log_section "Skipping dependency installation (--skip-deps)"
fi

log_section "Deploying user service"
mkdir -p "$(dirname "$SERVICE_DEST")"
install -m 644 "$SERVICE_SRC" "$SERVICE_DEST"

log_section "Activating systemd user service"
systemctl --user daemon-reload
systemctl --user enable --now "$SERVICE_NAME"
sudo loginctl enable-linger "$USER"

log_section "Controller install complete"
systemctl --user status "$SERVICE_NAME" --no-pager || true
