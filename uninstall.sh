#!/bin/bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_FILE="/etc/systemd/system/program_launcher.service"
CONFIG_FILE="/boot/firmware/config.txt"
CMDLINE_FILE="/boot/firmware/cmdline.txt"
BLACKLIST_FILE="/etc/modprobe.d/blacklist.conf"

REMOVE_VENV=false
REMOVE_CACHE=false
REMOVE_LOG=false

usage() {
    cat <<EOF
Usage: sudo ./uninstall.sh [options]

Stops and removes the LED display service and restores configuration files
saved by install.sh. User configuration and data are kept by default.

Options:
  --remove-venv    Remove the project's ~/.venv virtual environment
  --remove-cache   Remove stock_prices.json
  --remove-log     Remove error.log
  -h, --help       Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --remove-venv) REMOVE_VENV=true ;;
        --remove-cache) REMOVE_CACHE=true ;;
        --remove-log) REMOVE_LOG=true ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

if [[ $EUID -ne 0 ]]; then
    echo "Please run: sudo ./uninstall.sh"
    exit 1
fi

TARGET_USER="${SUDO_USER:-$(logname 2>/dev/null || true)}"
if [[ -z "$TARGET_USER" ]] || ! getent passwd "$TARGET_USER" >/dev/null; then
    echo "Could not determine the non-root installation user." >&2
    exit 1
fi
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
VENV_DIR="$TARGET_HOME/.venv"

echo "Stopping program_launcher.service..."
systemctl disable --now program_launcher.service 2>/dev/null || true
rm -f "$SERVICE_FILE"
systemctl daemon-reload

restore_backup() {
    local file="$1"
    local backup="${file}.led-display.bak"
    if [[ -f "$backup" ]]; then
        cp "$backup" "$file"
        rm -f "$backup"
        echo "Restored $file"
    fi
}

restore_backup "$CONFIG_FILE"
restore_backup "$CMDLINE_FILE"
restore_backup "$BLACKLIST_FILE"

if [[ "$REMOVE_VENV" == true ]]; then
    rm -rf -- "$VENV_DIR"
    echo "Removed $VENV_DIR"
fi
if [[ "$REMOVE_CACHE" == true ]]; then
    rm -f -- "$PROJECT_DIR/stock_prices.json"
    echo "Removed stock cache"
fi
if [[ "$REMOVE_LOG" == true ]]; then
    rm -f -- "$PROJECT_DIR/error.log"
    echo "Removed error log"
fi

echo
echo "Uninstall complete. The project files, .env, cache, log, and virtual"
echo "environment were kept unless their explicit removal option was used."
echo "Console autologin was not changed; restore it with raspi-config if needed."