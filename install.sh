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


echo
echo "=========================================="
echo " LED Album Cover Installer"
echo "=========================================="
echo
echo "User:              $TARGET_USER"
echo "Home directory:    $TARGET_HOME"
echo "Installer location: $SCRIPT_DIR"
echo


# ============================================================
# Paths
# ============================================================

SAMPLES_DIR="$TARGET_HOME/LED-Display"

PYTHON="$TARGET_HOME/.venv/bin/python3"

MAIN_SCRIPT="$SAMPLES_DIR/main.py"


# ============================================================
# Verify required files/directories
# ============================================================

echo "[1/8] Checking installation..."

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


# ============================================================
# Create systemd service
# ============================================================

echo "[2/8] Creating program_launcher.service..."

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

echo "[3/8] Installing shutdown_services.sh..."

cp \
    "$SCRIPT_DIR/shutdown_services.sh" \
    "$TARGET_HOME/shutdown_services.sh"


chown \
    "$TARGET_USER:$TARGET_USER" \
    "$TARGET_HOME/shutdown_services.sh"


chmod +x \
    "$TARGET_HOME/shutdown_services.sh"


# ============================================================
# Configure Console Autologin
# ============================================================

echo "[4/8] Configuring console autologin..."

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

echo "[5/8] Reloading systemd..."

systemctl daemon-reload


# ============================================================
# Enable service
# ============================================================

echo "[6/8] Enabling program_launcher.service..."

systemctl enable program_launcher.service


# ============================================================
# Start service
# ============================================================

echo "[7/8] Starting program_launcher.service..."

systemctl restart program_launcher.service


# ============================================================
# Check service
# ============================================================

echo "[8/8] Checking service..."

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
echo "Installed service:"
echo "    /etc/systemd/system/program_launcher.service"
echo
echo "Installed shutdown script:"
echo "    $TARGET_HOME/shutdown_services.sh"
echo
echo "The Raspberry Pi will reboot in 5 seconds."
echo "Press Ctrl+C to cancel."
echo


sleep 5

reboot