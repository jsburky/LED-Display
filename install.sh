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
# Determine user information
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TARGET_USER="${SUDO_USER:-$(logname)}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
TARGET_GROUP="$(id -gn "$TARGET_USER")"


echo
echo "=========================================="
echo " LED Album Cover Installer"
echo "=========================================="
echo
echo "User:               $TARGET_USER"
echo "Home directory:     $TARGET_HOME"
echo "Installer location: $SCRIPT_DIR"
echo


# ============================================================
# Paths
# ============================================================

SAMPLES_DIR="$TARGET_HOME/LED-Display"

PYTHON="$TARGET_HOME/.venv/bin/python3"

MAIN_SCRIPT="$SAMPLES_DIR/main.py"

CONFIG_FILE="/boot/firmware/config.txt"

BLACKLIST_FILE="/etc/modprobe.d/blacklist.conf"

CMDLINE_FILE="/boot/firmware/cmdline.txt"


# ============================================================
# Verify required files/directories
# ============================================================

echo "[1/11] Checking installation..."

if [[ ! -d "$SAMPLES_DIR" ]]; then
    echo
    echo "ERROR: RGB matrix samples directory not found:"
    echo
    echo "    $SAMPLES_DIR"
    echo
    exit 1
fi


if [[ ! -f "$MAIN_SCRIPT" ]]; then
    echo
    echo "ERROR: main.py not found:"
    echo
    echo "    $MAIN_SCRIPT"
    echo
    exit 1
fi


if [[ ! -x "$PYTHON" ]]; then
    echo
    echo "ERROR: Python virtual environment not found:"
    echo
    echo "    $PYTHON"
    echo
    exit 1
fi


if [[ ! -f "$SCRIPT_DIR/shutdown_services.sh" ]]; then
    echo
    echo "ERROR: shutdown_services.sh not found:"
    echo
    echo "    $SCRIPT_DIR/shutdown_services.sh"
    echo
    exit 1
fi


if [[ ! -f "$CONFIG_FILE" ]]; then
    echo
    echo "ERROR: Could not find:"
    echo
    echo "    $CONFIG_FILE"
    echo
    exit 1
fi


if [[ ! -f "$CMDLINE_FILE" ]]; then
    echo
    echo "ERROR: Could not find:"
    echo
    echo "    $CMDLINE_FILE"
    echo
    exit 1
fi


# ============================================================
# Create systemd service
# ============================================================

echo "[2/11] Creating program_launcher.service..."

cat > /etc/systemd/system/program_launcher.service << EOF
[Unit]
Description=LED Album Cover Program Launcher
Wants=network-online.target
After=network-online.target

[Service]
Type=simple

WorkingDirectory=$SAMPLES_DIR

ExecStart=$PYTHON $MAIN_SCRIPT

Restart=always
RestartSec=5

StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF


chmod 644 /etc/systemd/system/program_launcher.service


# ============================================================
# Install shutdown_services.sh
# ============================================================

echo "[3/11] Installing shutdown_services.sh..."

cp \
    "$SCRIPT_DIR/shutdown_services.sh" \
    "$TARGET_HOME/shutdown_services.sh"


chown \
    "$TARGET_USER:$TARGET_GROUP" \
    "$TARGET_HOME/shutdown_services.sh"


chmod +x \
    "$TARGET_HOME/shutdown_services.sh"


# ============================================================
# Disable Raspberry Pi onboard audio
#
# Equivalent to:
# sudo nano /boot/firmware/config.txt
#
# Set:
# dtparam=audio=off
# ============================================================

echo "[4/11] Disabling onboard audio..."

# Create backup once
if [[ ! -f "${CONFIG_FILE}.led-album-cover.bak" ]]; then
    cp "$CONFIG_FILE" "${CONFIG_FILE}.led-album-cover.bak"
fi


# Check whether a dtparam=audio line already exists
if grep -qE '^[[:space:]]*dtparam=audio=' "$CONFIG_FILE"; then

    # Change existing setting to off
    sed -i -E \
        's/^[[:space:]]*dtparam=audio=.*/dtparam=audio=off/' \
        "$CONFIG_FILE"

else

    # Add setting if it does not exist
    echo >> "$CONFIG_FILE"
    echo "# Disabled for RGB LED matrix" >> "$CONFIG_FILE"
    echo "dtparam=audio=off" >> "$CONFIG_FILE"

fi


echo "    dtparam=audio=off"


# ============================================================
# Blacklist snd_bcm2835
#
# Equivalent to:
# sudo nano /etc/modprobe.d/blacklist.conf
#
# Add:
# blacklist snd_bcm2835
# ============================================================

echo "[5/11] Blacklisting snd_bcm2835..."

# blacklist.conf may not exist, so create it if necessary
touch "$BLACKLIST_FILE"


# Create backup once
if [[ ! -f "${BLACKLIST_FILE}.led-album-cover.bak" ]]; then
    cp "$BLACKLIST_FILE" "${BLACKLIST_FILE}.led-album-cover.bak"
fi


# Add blacklist only if it isn't already present
if ! grep -qE \
    '^[[:space:]]*blacklist[[:space:]]+snd_bcm2835([[:space:]]*)$' \
    "$BLACKLIST_FILE"; then

    echo >> "$BLACKLIST_FILE"
    echo "# Disabled for RGB LED matrix" >> "$BLACKLIST_FILE"
    echo "blacklist snd_bcm2835" >> "$BLACKLIST_FILE"

fi


echo "    blacklist snd_bcm2835"


# ============================================================
# Add isolcpus=3 to kernel command line
#
# Equivalent to:
# sudo nano /boot/firmware/cmdline.txt
#
# Add to END of existing line:
# isolcpus=3
# ============================================================

echo "[6/11] Isolating CPU core 3..."

# Create backup once
if [[ ! -f "${CMDLINE_FILE}.led-album-cover.bak" ]]; then
    cp "$CMDLINE_FILE" "${CMDLINE_FILE}.led-album-cover.bak"
fi


# cmdline.txt MUST remain one line.
#
# Only add isolcpus=3 if it is not already present.

if ! grep -qw 'isolcpus=3' "$CMDLINE_FILE"; then

    sed -i '1 s/[[:space:]]*$//' "$CMDLINE_FILE"
    sed -i '1 s/$/ isolcpus=3/' "$CMDLINE_FILE"

fi


echo "    isolcpus=3"


# ============================================================
# Configure Console Autologin
#
# Equivalent to:
#
# sudo raspi-config
#
# System Options
#   -> Boot / Auto Login
#       -> Console Autologin
# ============================================================

echo "[7/11] Configuring console autologin..."

if ! command -v raspi-config >/dev/null 2>&1; then
    echo
    echo "ERROR: raspi-config was not found."
    echo "Are you running Raspberry Pi OS?"
    echo
    exit 1
fi


env SUDO_USER="$TARGET_USER" \
    raspi-config nonint do_boot_behaviour B2


# ============================================================
# Reload systemd
# ============================================================

echo "[8/11] Reloading systemd..."

systemctl daemon-reload


# ============================================================
# Enable service
# ============================================================

echo "[9/11] Enabling program_launcher.service..."

systemctl enable program_launcher.service


# ============================================================
# Start service
# ============================================================

echo "[10/11] Starting program_launcher.service..."

systemctl restart program_launcher.service


# ============================================================
# Check service
# ============================================================

echo "[11/11] Checking service..."

sleep 2


if systemctl is-active --quiet program_launcher.service; then

    echo
    echo "program_launcher.service is running successfully."

else

    echo
    echo "WARNING: program_launcher.service failed to start."
    echo
    echo "Check the logs with:"
    echo
    echo "    sudo journalctl -u program_launcher.service -n 50"
    echo

    exit 1

fi


# ============================================================
# Finished
# ============================================================

echo
echo "=========================================="
echo " Installation Complete"
echo "=========================================="
echo
echo "Configured:"
echo
echo "    Console autologin"
echo "    dtparam=audio=off"
echo "    blacklist snd_bcm2835"
echo "    isolcpus=3"
echo "    program_launcher.service"
echo "    shutdown_services.sh"
echo
echo "Backups of modified boot files were created."
echo
echo "The Raspberry Pi will reboot in 5 seconds."
echo "Press Ctrl+C to cancel the reboot."
echo


sleep 5

reboot