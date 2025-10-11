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

# Show all info
echo
echo "✅ Phase 1 Complete!"
echo "HOME SERVER INFO:"
echo "WireGuard Private Key: $HOME_PRIV"
echo "WireGuard Public Key:  $HOME_PUB"
echo "Suggested WireGuard interface IP: 10.8.0.2"
echo "You can copy the public key to the VPS script later."
echo "You will configure ports after Phase 2 starts."
echo
read -p "Press ENTER to start Phase 2 (enter required info and apply config)..."

# Phase 2: ask for inputs
read -p "Enter VPS WireGuard public key: " VPS_PUB
read -p "Enter desired VPS public IP or hostname (for Endpoint in config): " VPS_IP
read -p "Enter Home WireGuard interface IP (default 10.8.0.2): " WG_IP
WG_IP=${WG_IP:-10.8.0.2}

# Create WireGuard config
cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
PrivateKey = $HOME_PRIV
Address = $WG_IP/24
DNS = 1.1.1.1

[Peer]
PublicKey = $VPS_PUB
Endpoint = $VPS_IP:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF

chmod 600 /etc/wireguard/wg0.conf

# Enable IP forwarding
echo "Enabling IP forwarding..."
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv6.conf.all.forwarding=1
sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.conf
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
sed -i '/net.ipv6.conf.all.forwarding/d' /etc/sysctl.conf
echo "net.ipv6.conf.all.forwarding=1" | sudo tee -a /etc/sysctl.conf

# Bring up WireGuard
wg-quick up wg0 || wg-quick up /etc/wireguard/wg0.conf
systemctl enable wg-quick@wg0

echo
echo "✅ Home server setup Phase 2 complete!"
echo "WireGuard is running."
echo "Connect test: wg show"
