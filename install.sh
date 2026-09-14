#!/bin/bash

set -e


# ============================================================
# Make sure script is running as root
# ============================================================

if [[ $EUID -ne 0 ]]; then
    echo
    echo "Please run this installer with:"
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


echo
echo "=========================================="
echo " LED Display Installer"
echo "=========================================="
echo
echo "User:              $TARGET_USER"
echo "Home directory:    $TARGET_HOME"
echo "Project directory: $PROJECT_DIR"
echo


# ============================================================
# Paths
# ============================================================

VENV_DIR="$PROJECT_DIR/.venv"
PYTHON="$VENV_DIR/bin/python3"
PIP="$VENV_DIR/bin/pip"

MAIN_SCRIPT="$PROJECT_DIR/main.py"
REQUIREMENTS="$PROJECT_DIR/requirements.txt"

SHUTDOWN_SOURCE="$PROJECT_DIR/shutdown_services.sh"
SHUTDOWN_DEST="$TARGET_HOME/shutdown_services.sh"

SERVICE_FILE="/etc/systemd/system/program_launcher.service"

BLACKLIST_FILE="/etc/modprobe.d/blacklist.conf"


# ============================================================
# Find Raspberry Pi boot files
#
# New Raspberry Pi OS:
#   /boot/firmware/config.txt
#
# Older Raspberry Pi OS:
#   /boot/config.txt
# ============================================================

if [[ -f /boot/firmware/config.txt ]]; then

    CONFIG_FILE="/boot/firmware/config.txt"
    CMDLINE_FILE="/boot/firmware/cmdline.txt"

elif [[ -f /boot/config.txt ]]; then

    CONFIG_FILE="/boot/config.txt"
    CMDLINE_FILE="/boot/cmdline.txt"

else

    echo
    echo "ERROR: Raspberry Pi boot configuration files were not found."
    echo
    exit 1

fi


# ============================================================
# 1. Check project files
# ============================================================

echo "[1/13] Checking project files..."


if [[ ! -f "$MAIN_SCRIPT" ]]; then
    echo
    echo "ERROR: main.py not found:"
    echo
    echo "    $MAIN_SCRIPT"
    echo
    exit 1
fi


if [[ ! -f "$REQUIREMENTS" ]]; then
    echo
    echo "ERROR: requirements.txt not found:"
    echo
    echo "    $REQUIREMENTS"
    echo
    exit 1
fi


if [[ ! -f "$SHUTDOWN_SOURCE" ]]; then
    echo
    echo "ERROR: shutdown_services.sh not found:"
    echo
    echo "    $SHUTDOWN_SOURCE"
    echo
    exit 1
fi


if [[ ! -f "$CMDLINE_FILE" ]]; then
    echo
    echo "ERROR: cmdline.txt not found:"
    echo
    echo "    $CMDLINE_FILE"
    echo
    exit 1
fi


# ============================================================
# 2. Update package lists
# ============================================================

echo "[2/13] Updating package lists..."

apt-get update


# ============================================================
# 3. Install operating system dependencies
# ============================================================

echo "[3/13] Installing system dependencies..."

DEBIAN_FRONTEND=noninteractive apt-get install -y \
    git \
    build-essential \
    cmake \
    python3 \
    python3-dev \
    python3-pip \
    python3-venv \
    python3-evdev \
    python3-pil \
    cython3


# ============================================================
# 4. Create Python virtual environment
# ============================================================

echo "[4/13] Creating Python virtual environment..."


if [[ ! -d "$VENV_DIR" ]]; then

    sudo -u "$TARGET_USER" -H \
        python3 -m venv "$VENV_DIR"

else

    echo "    Existing virtual environment found."

fi


if [[ ! -x "$PYTHON" ]]; then

    echo
    echo "ERROR: Failed to create Python virtual environment."
    echo
    exit 1

fi


# ============================================================
# 5. Upgrade pip
# ============================================================

echo "[5/13] Updating pip..."

sudo -u "$TARGET_USER" -H \
    "$PYTHON" -m pip install --upgrade pip setuptools wheel


# ============================================================
# 6. Install Python requirements
# ============================================================

echo "[6/13] Installing Python dependencies..."

sudo -u "$TARGET_USER" -H \
    "$PYTHON" -m pip install \
    -r "$REQUIREMENTS"


# ============================================================
# 7. Install shutdown_services.sh
# ============================================================

echo "[7/13] Installing shutdown_services.sh..."

cp \
    "$SHUTDOWN_SOURCE" \
    "$SHUTDOWN_DEST"


chown \
    "$TARGET_USER:$TARGET_GROUP" \
    "$SHUTDOWN_DEST"


chmod +x "$SHUTDOWN_DEST"


# ============================================================
# 8. Disable Raspberry Pi onboard audio
#
# Set:
#
# dtparam=audio=off
# ============================================================

echo "[8/13] Disabling onboard audio..."


if [[ ! -f "${CONFIG_FILE}.led-display.bak" ]]; then

    cp \
        "$CONFIG_FILE" \
        "${CONFIG_FILE}.led-display.bak"

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

echo "[9/13] Blacklisting snd_bcm2835..."


touch "$BLACKLIST_FILE"


if [[ ! -f "${BLACKLIST_FILE}.led-display.bak" ]]; then

    cp \
        "$BLACKLIST_FILE" \
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
# 10. Add isolcpus=3
# ============================================================

echo "[10/13] Configuring CPU isolation..."


if [[ ! -f "${CMDLINE_FILE}.led-display.bak" ]]; then

    cp \
        "$CMDLINE_FILE" \
        "${CMDLINE_FILE}.led-display.bak"

fi


# cmdline.txt must remain one line.
if ! grep -qw 'isolcpus=3' "$CMDLINE_FILE"; then

    sed -i '1 s/[[:space:]]*$//' "$CMDLINE_FILE"
    sed -i '1 s/$/ isolcpus=3/' "$CMDLINE_FILE"

fi


echo "    isolcpus=3"


# ============================================================
# 11. Configure console autologin
# ============================================================

echo "[11/13] Configuring console autologin..."


if ! command -v raspi-config >/dev/null 2>&1; then

    echo
    echo "ERROR: raspi-config was not found."
    echo "This installer is intended for Raspberry Pi OS."
    echo
    exit 1

fi


env SUDO_USER="$TARGET_USER" \
    raspi-config nonint do_boot_behaviour B2


# ============================================================
# 12. Create systemd service
# ============================================================

echo "[12/13] Creating program_launcher.service..."


cat > "$SERVICE_FILE" << EOF
[Unit]
Description=LED Display Program Launcher
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=root

WorkingDirectory=$PROJECT_DIR

ExecStart=$PYTHON $MAIN_SCRIPT

Restart=always
RestartSec=5

Environment=PYTHONUNBUFFERED=1

StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF


chmod 644 "$SERVICE_FILE"


# ============================================================
# 13. Enable service
# ============================================================

echo "[13/13] Enabling program_launcher.service..."

systemctl daemon-reload
systemctl enable program_launcher.service


# ============================================================
# Finished
# ============================================================

echo
echo "=========================================="
echo " Installation Complete"
echo "=========================================="
echo
echo "Installed:"
echo
echo "    System dependencies"
echo "    Python virtual environment"
echo "    Python requirements"
echo "    Console autologin"
echo "    dtparam=audio=off"
echo "    blacklist snd_bcm2835"
echo "    isolcpus=3"
echo "    program_launcher.service"
echo "    shutdown_services.sh"
echo
echo "Virtual environment:"
echo "    $VENV_DIR"
echo
echo "Service:"
echo "    $SERVICE_FILE"
echo
echo "Boot configuration backups were created."
echo
echo "The Raspberry Pi will reboot in 5 seconds."
echo "Press Ctrl+C to cancel the reboot."
echo


sleep 5

reboot
