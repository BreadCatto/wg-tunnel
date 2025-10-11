#!/bin/bash
set -euo pipefail

echo "===== Universal WireGuard Tunnel Installer ====="

# Step 1: Install git if not installed
if ! command -v git &>/dev/null; then
    echo "Installing git..."
    sudo apt update && sudo apt install -y git
fi

# Step 2: Clone or update repository
TMP_DIR="/tmp/wg-tunnel-install"
if [[ -d "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR"
fi

git clone https://github.com/BreadCatto/wg-tunnel.git "$TMP_DIR"

# Step 3: Run the universal installer
cd "$TMP_DIR"
chmod +x install.sh vps-setup.sh local-setup.sh

echo
echo "Select environment:"
echo "1) VPS"
echo "2) Home Server"
read -p "Enter 1 or 2: " CHOICE

if [[ "$CHOICE" == "1" ]]; then
    bash vps-setup.sh
elif [[ "$CHOICE" == "2" ]]; then
    bash local-setup.sh
else
    echo "Invalid selection. Exiting."
    exit 1
fi
