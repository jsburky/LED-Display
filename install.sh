#!/bin/bash

set -e


# ============================================================
# Must be run with sudo
# ============================================================

if [[ $EUID -ne 0 ]]; then
    echo
    echo "Please run:"
    echo
    echo "    sudo ./install.sh"
    echo
    exit 1
fi


# ============================================================
# Determine user/project information
# ============================================================

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TARGET_USER="${SUDO_USER:-$(logname)}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
TARGET_GROUP="$(id -gn "$TARGET_USER")"


# Keep this environment owned by this checkout so uninstall cannot remove a
# shared environment used by another project.
VENV_DIR="$PROJECT_DIR/.venv"
VENV_MARKER="$VENV_DIR/.led-display-owned"
HOME_MODE_FILE="$PROJECT_DIR/.led-display-home-mode"
PYTHON="$VENV_DIR/bin/python3"

MAIN_SCRIPT="$PROJECT_DIR/main.py"
TIME_SCRIPT="$PROJECT_DIR/time.py"
REQUIREMENTS="$PROJECT_DIR/requirements.txt"

CONFIG_FILE="/boot/firmware/config.txt"
CMDLINE_FILE="/boot/firmware/cmdline.txt"
BLACKLIST_FILE="/etc/modprobe.d/blacklist.conf"

SERVICE_FILE="/etc/systemd/system/program_launcher.service"


echo
echo "=========================================="
echo " LED Display Installer"
echo "=========================================="
echo
echo "User:              $TARGET_USER"
echo "Home directory:    $TARGET_HOME"
echo "Project directory: $PROJECT_DIR"
echo "Virtual env:       $VENV_DIR"
echo


# ============================================================
# 1. Verify repository
# ============================================================

echo "[1/15] Checking repository..."


if [[ ! -f "$MAIN_SCRIPT" ]]; then
    echo "ERROR: main.py not found:"
    echo "    $MAIN_SCRIPT"
    exit 1
fi


if [[ ! -f "$TIME_SCRIPT" ]]; then
    echo "ERROR: time.py not found:"
    echo "    $TIME_SCRIPT"
    exit 1
fi


if [[ ! -f "$REQUIREMENTS" ]]; then
    echo "ERROR: requirements.txt not found:"
    echo "    $REQUIREMENTS"
    exit 1
fi


if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "ERROR: $CONFIG_FILE not found."
    exit 1
fi


if [[ ! -f "$CMDLINE_FILE" ]]; then
    echo "ERROR: $CMDLINE_FILE not found."
    exit 1
fi


# ============================================================
# 2. apt update
#
# Old step:
# sudo apt update
# ============================================================

echo "[2/15] Updating apt package lists..."

apt-get update


# ============================================================
# 3. Install EXACT system packages from old working setup
#
# Old steps:
#
# sudo apt install python3-venv
#
# sudo apt install -y \
#     git build-essential cmake \
#     python3-dev python3-pip cython3
#
# sudo apt-get install \
#     python-dev-is-python3 python3-pil
#
# sudo apt install python3-evdev
# ============================================================

echo "[3/15] Installing system dependencies..."

DEBIAN_FRONTEND=noninteractive apt-get install -y \
    git \
    build-essential \
    cmake \
    python3 \
    python3-venv \
    python3-dev \
    python3-pip \
    python-dev-is-python3 \
    python3-pil \
    python3-evdev \
    cython3


# ============================================================
# 4. Create ~/.venv
#
# EXACTLY matches old:
#
# cd ~
# python3 -m venv .venv
# ============================================================

echo "[4/15] Creating Python virtual environment..."

if [[ ! -d "$VENV_DIR" ]]; then

    sudo -u "$TARGET_USER" -H \
        python3 -m venv "$VENV_DIR"

    sudo -u "$TARGET_USER" -H touch "$VENV_MARKER"

else

    echo "    Existing virtual environment found:"
    echo "    $VENV_DIR"

fi


if [[ ! -x "$PYTHON" ]]; then
    echo
    echo "ERROR: Could not create virtual environment."
    exit 1
fi


# ============================================================
# 5. Upgrade pip
# ============================================================

echo "[5/15] Updating pip..."

sudo -u "$TARGET_USER" -H \
    "$PYTHON" -m pip install --upgrade pip


# ============================================================
# 6. Install requirements
#
# Equivalent to:
#
# source ~/.venv/bin/activate
# cd LED-Display
# pip install -r requirements.txt
#
# We don't actually need to 'source' the venv.
# ============================================================

echo "[6/15] Installing requirements.txt..."

sudo -u "$TARGET_USER" -H \
    "$PYTHON" -m pip install \
    -r "$REQUIREMENTS"


# ============================================================
# 7. Verify critical Python imports
#
# main.py requires evdev
# time.py requires rgbmatrix, requests and dotenv
# ============================================================

echo "[7/15] Testing Python installation..."


"$PYTHON" - <<'PYTHON_TEST'

import sys

modules = [
    "evdev",
    "rgbmatrix",
    "requests",
    "dotenv",
]

failed = []

for module in modules:
    try:
        __import__(module)
        print(f"    OK: {module}")
    except Exception as error:
        print(f"    FAILED: {module}: {error}")
        failed.append(module)

if failed:
    print()
    print("Missing required Python modules:")
    for module in failed:
        print(f"    {module}")

    sys.exit(1)

print()
print("    Python dependency check passed.")

PYTHON_TEST


# ============================================================
# 8. Configure onboard audio
# ============================================================

echo "[8/15] Disabling onboard audio..."


if [[ ! -f "${CONFIG_FILE}.led-display.bak" ]]; then
    cp "$CONFIG_FILE" "${CONFIG_FILE}.led-display.bak"
fi


if grep -qE \
    '^[[:space:]]*dtparam=audio=' \
    "$CONFIG_FILE"; then

    sed -i -E \
        's/^[[:space:]]*dtparam=audio=.*/dtparam=audio=off/' \
        "$CONFIG_FILE"

else

    echo >> "$CONFIG_FILE"
    echo "# Disabled for RGB LED matrix" >> "$CONFIG_FILE"
    echo "dtparam=audio=off" >> "$CONFIG_FILE"

fi


echo "    dtparam=audio=off"


# ============================================================
# 9. Blacklist snd_bcm2835
# ============================================================

echo "[9/15] Blacklisting snd_bcm2835..."


touch "$BLACKLIST_FILE"


if [[ ! -f "${BLACKLIST_FILE}.led-display.bak" ]]; then
    cp "$BLACKLIST_FILE" \
       "${BLACKLIST_FILE}.led-display.bak"
fi


if ! grep -qE \
    '^[[:space:]]*blacklist[[:space:]]+snd_bcm2835([[:space:]]*)$' \
    "$BLACKLIST_FILE"; then

    echo >> "$BLACKLIST_FILE"
    echo "# Disabled for RGB LED matrix" >> "$BLACKLIST_FILE"
    echo "blacklist snd_bcm2835" >> "$BLACKLIST_FILE"

fi


echo "    blacklist snd_bcm2835"


# ============================================================
# 10. isolcpus=3
# ============================================================

echo "[10/15] Configuring CPU isolation..."


if [[ ! -f "${CMDLINE_FILE}.led-display.bak" ]]; then
    cp "$CMDLINE_FILE" \
       "${CMDLINE_FILE}.led-display.bak"
fi


# cmdline.txt must stay one line.
if ! grep -qw 'isolcpus=3' "$CMDLINE_FILE"; then

    sed -i '1 s/[[:space:]]*$//' "$CMDLINE_FILE"
    sed -i '1 s/$/ isolcpus=3/' "$CMDLINE_FILE"

fi


echo "    isolcpus=3"


# ============================================================
# 11. Configure Console Autologin
# ============================================================

echo "[11/15] Configuring console autologin..."


if ! command -v raspi-config >/dev/null 2>&1; then

    echo
    echo "ERROR: raspi-config not found."
    echo "This installer is intended for Raspberry Pi OS."
    exit 1

fi


env SUDO_USER="$TARGET_USER" \
    raspi-config nonint do_boot_behaviour B2


# ============================================================
# 12. Configure project permissions
#
# main.py now accesses the copy INSIDE the project.
# ============================================================

echo "[12/15] Configuring project permissions..."


# time.py runs as daemon after the matrix library drops root privileges.
# Keep the cache's owner and contents, but allow daemon to save stock prices.
if [[ ! -f "$HOME_MODE_FILE" ]]; then
    stat -c '%a' "$TARGET_HOME" > "$HOME_MODE_FILE"
fi
chmod o+x "$TARGET_HOME"
if [[ ! -e "$PROJECT_DIR/stock_prices.json" ]]; then
    install -o "$TARGET_USER" -g daemon -m 664 /dev/null "$PROJECT_DIR/stock_prices.json"
fi
chgrp daemon "$PROJECT_DIR/stock_prices.json"
chmod g+w "$PROJECT_DIR/stock_prices.json"


if [[ -f "$PROJECT_DIR/shutdown_services.sh" ]]; then

    chmod +x "$PROJECT_DIR/shutdown_services.sh"

else

    echo
    echo "WARNING: shutdown_services.sh not found."
    echo

fi


# ============================================================
# 13. Create systemd service
# ============================================================

echo "[13/15] Creating systemd service..."


cat > "$SERVICE_FILE" << EOF
[Unit]
Description=LED Display Program Launcher
Wants=network-online.target
After=network-online.target

[Service]
Type=simple

WorkingDirectory=$PROJECT_DIR

ExecStart=$PYTHON $MAIN_SCRIPT

Restart=always
RestartSec=5

Environment=PYTHONUNBUFFERED=1
Environment=PYTHONDONTWRITEBYTECODE=1

StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF


chmod 644 "$SERVICE_FILE"


# ============================================================
# 14. Reload systemd
# ============================================================

echo "[14/15] Reloading systemd..."

systemctl daemon-reload


# ============================================================
# 15. Enable service
# ============================================================

echo "[15/15] Enabling program_launcher.service..."

systemctl enable program_launcher.service


# ============================================================
# Finish
# ============================================================

echo
echo "=========================================="
echo " Installation Complete"
echo "=========================================="
echo
echo "Python:"
echo "    $PYTHON"
echo
echo "Program:"
echo "    $MAIN_SCRIPT"
echo
echo "Configured:"
echo "    Python dependencies"
echo "    RGB matrix dependencies"
echo "    evdev"
echo "    Stock cache write permissions"
echo "    Console autologin"
echo "    dtparam=audio=off"
echo "    blacklist snd_bcm2835"
echo "    isolcpus=3"
echo "    program_launcher.service"
echo
echo "The Pi will reboot in 5 seconds."
echo "Press Ctrl+C to cancel."
echo

sleep 5

reboot
