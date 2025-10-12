#!/bin/bash
set -euo pipefail

echo "===== HOME SERVER SETUP PHASE 1: Install & Generate Keys ====="

# Install dependencies
sudo apt update
sudo apt install -y wireguard iptables iptables-persistent curl net-tools qrencode jq

# Generate WireGuard keys
umask 077
wg genkey | tee /etc/wireguard/privatekey | wg pubkey > /etc/wireguard/publickey
HOME_PRIV=$(cat /etc/wireguard/privatekey)
HOME_PUB=$(cat /etc/wireguard/publickey)

echo
echo "✅ Phase 1 Complete!"
echo "HOME SERVER INFO:"
echo "WireGuard Private Key: $HOME_PRIV"
echo "WireGuard Public Key:  $HOME_PUB"
echo "Suggested WireGuard interface IP: 10.8.0.2"
echo
read -p "Press ENTER to start Phase 2..."

# Phase 2 inputs
read -p "Enter VPS WireGuard public key: " VPS_PUB
read -p "Enter VPS public IP or hostname: " VPS_IP
read -p "Enter Home WireGuard interface IP (default 10.8.0.2): " WG_IP
WG_IP=${WG_IP:-10.8.0.2}

# WireGuard config
cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
PrivateKey = $HOME_PRIV
Address = $WG_IP/24
ListenPort = 51820

[Peer]
PublicKey = $VPS_PUB
Endpoint = $VPS_IP:51820
AllowedIPs = 10.8.0.1/32
PersistentKeepalive = 25
EOF

chmod 600 /etc/wireguard/wg0.conf

# Enable IP forwarding
echo "Enabling IP forwarding..."
sysctl -w net.ipv4.ip_forward=1
sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.conf
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf

# Bring up WireGuard
wg-quick down wg0 2>/dev/null || true
wg-quick up wg0
systemctl enable wg-quick@wg0

echo
echo "✅ Home server WireGuard tunnel is active!"
echo "Tunnel IP: $WG_IP"
echo "You should now run: ping 10.8.0.1"
