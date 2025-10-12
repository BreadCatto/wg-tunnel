#!/bin/bash
set -euo pipefail

echo "===== VPS SETUP PHASE 1: Install & Generate Keys ====="

# Install dependencies
sudo apt update
sudo apt install -y wireguard iptables iptables-persistent curl net-tools qrencode jq

# Generate WireGuard keys
umask 077
wg genkey | tee /etc/wireguard/privatekey | wg pubkey > /etc/wireguard/publickey
VPS_PRIV=$(cat /etc/wireguard/privatekey)
VPS_PUB=$(cat /etc/wireguard/publickey)

# Show all info
echo
echo "✅ Phase 1 Complete!"
echo "VPS SERVER INFO:"
echo "WireGuard Private Key: $VPS_PRIV"
echo "WireGuard Public Key:  $VPS_PUB"
echo "Suggested WireGuard interface IP: 10.8.0.1"
echo
read -p "Press ENTER to start Phase 2..."

# Phase 2 inputs
read -p "Enter Home WireGuard public key: " HOME_PUB
read -p "Enter VPS WireGuard interface IP (default 10.8.0.1): " WG_IP
WG_IP=${WG_IP:-10.8.0.1}
read -p "Enter ports/ranges to forward (e.g., '22 25565 8000-9000'): " PORTS

# Change SSH port to 23
sed -i 's/^#Port 22/Port 23/' /etc/ssh/sshd_config
sed -i 's/^Port 22/Port 23/' /etc/ssh/sshd_config
systemctl restart ssh

# WireGuard config
cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
PrivateKey = $VPS_PRIV
Address = $WG_IP/24
ListenPort = 51820

[Peer]
PublicKey = $HOME_PUB
AllowedIPs = 10.8.0.2/32
EOF

chmod 600 /etc/wireguard/wg0.conf

# Enable IP forwarding
echo "Enabling IP forwarding..."
sysctl -w net.ipv4.ip_forward=1
sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.conf
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf

# Detect main network interface automatically
ETH_IFACE=$(ip route | grep default | awk '{print $5}')

# Flush old rules
iptables -F
iptables -t nat -F

# ✅ FIXED NAT + FORWARD rules for incoming tunnel
iptables -t nat -A POSTROUTING -o wg0 -j MASQUERADE
iptables -A FORWARD -i $ETH_IFACE -o wg0 -j ACCEPT
iptables -A FORWARD -i wg0 -o $ETH_IFACE -m state --state RELATED,ESTABLISHED -j ACCEPT

# Port forwarding to Home (DNAT)
for P in $PORTS; do
    if [[ $P == *"-"* ]]; then
        START=$(echo $P | cut -d'-' -f1)
        END=$(echo $P | cut -d'-' -f2)
        iptables -t nat -A PREROUTING -p tcp --dport $START:$END -j DNAT --to-destination 10.8.0.2
        iptables -t nat -A PREROUTING -p udp --dport $START:$END -j DNAT --to-destination 10.8.0.2
    else
        iptables -t nat -A PREROUTING -p tcp --dport $P -j DNAT --to-destination 10.8.0.2
        iptables -t nat -A PREROUTING -p udp --dport $P -j DNAT --to-destination 10.8.0.2
    fi
done

# Save iptables rules
netfilter-persistent save

# Enable WireGuard
systemctl enable wg-quick@wg0
wg-quick up wg0 || wg-quick up /etc/wireguard/wg0.conf

echo
echo "✅ VPS setup complete!"
echo "Forwarded ports: $PORTS"
echo "SSH to VPS on port 23"
