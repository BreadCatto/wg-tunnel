#!/bin/bash
set -euo pipefail

echo "===== VPS SETUP PHASE 1: Install & Generate Keys ====="

# Install dependencies
sudo apt update
sudo apt install -y wireguard iptables iptables-persistent curl net-tools qrencode jq

# Generate WireGuard keys (Reuse if exist)
if [ -f /etc/wireguard/privatekey ]; then
    echo "Reusing existing WireGuard keys..."
    VPS_PRIV=$(cat /etc/wireguard/privatekey)
    VPS_PUB=$(cat /etc/wireguard/publickey)
else
    umask 077
    wg genkey | tee /etc/wireguard/privatekey | wg pubkey > /etc/wireguard/publickey
    VPS_PRIV=$(cat /etc/wireguard/privatekey)
    VPS_PUB=$(cat /etc/wireguard/publickey)
fi

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
read -p "Enter Local WireGuard interface IP (default 10.8.0.2): " HOME_IP
HOME_IP=${HOME_IP:-10.8.0.2}
read -p "Enter ports/ranges to forward (e.g., '22 25565 8000-9000'): " PORTS

# Change SSH port to 23 (if not already done)
if ! grep -q "^Port 23" /etc/ssh/sshd_config; then
    echo "Changing SSH port to 23..."
    sed -i 's/^#Port 22/Port 23/' /etc/ssh/sshd_config
    sed -i 's/^Port 22/Port 23/' /etc/ssh/sshd_config
    systemctl restart ssh
fi

# WireGuard config (Initialize if not exist, then append Peer)
if [ ! -f /etc/wireguard/wg0.conf ]; then
    echo "Creating new wg0.conf..."
    cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
PrivateKey = $VPS_PRIV
Address = $WG_IP/24
ListenPort = 51820
EOF
fi

# Check if peer already exists
if grep -Fq "$HOME_PUB" /etc/wireguard/wg0.conf; then
    echo "⚠️ Peer with this public key already exists in wg0.conf. Skipping append."
else
    echo "Adding new peer to wg0.conf..."
    cat >> /etc/wireguard/wg0.conf <<EOF

[Peer]
PublicKey = $HOME_PUB
AllowedIPs = $HOME_IP/32
EOF
fi

chmod 600 /etc/wireguard/wg0.conf

# Enable IP forwarding
echo "Enabling IP forwarding..."
sysctl -w net.ipv4.ip_forward=1
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
fi

# Detect main network interface automatically
ETH_IFACE=$(ip route | grep default | awk '{print $5}')

# Base NAT + FORWARD rules (Check if exist before adding)
iptables -t nat -C POSTROUTING -o wg0 -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -o wg0 -j MASQUERADE
iptables -C FORWARD -i $ETH_IFACE -o wg0 -j ACCEPT 2>/dev/null || iptables -A FORWARD -i $ETH_IFACE -o wg0 -j ACCEPT
iptables -C FORWARD -i wg0 -o $ETH_IFACE -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || iptables -A FORWARD -i wg0 -o $ETH_IFACE -m state --state RELATED,ESTABLISHED -j ACCEPT

# Port forwarding to Home (DNAT)
for P in $PORTS; do
    # Normalize range format for checking (iptables uses : in output)
    CHECK_P=${P//-/:}
    
    # Check if port or range is already forwarded to SOME destination
    EXISTING_RULE=$(iptables -t nat -S PREROUTING | grep -E "tcp.*--dport $CHECK_P( |$)" || true)
    if [ -n "$EXISTING_RULE" ]; then
        if echo "$EXISTING_RULE" | grep -q "$HOME_IP"; then
            echo "✅ Port/Range $P is already forwarded to $HOME_IP. Skipping."
        else
            EXISTING_DEST=$(echo "$EXISTING_RULE" | grep -oE "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+")
            echo "⚠️  WARNING: Port/Range $P is already forwarded to $EXISTING_DEST. Skipping $HOME_IP."
        fi
        continue
    fi

    if [[ $P == *"-"* ]]; then
        START=$(echo $P | cut -d'-' -f1)
        END=$(echo $P | cut -d'-' -f2)
        iptables -t nat -A PREROUTING -p tcp --dport $START:$END -j DNAT --to-destination $HOME_IP
        iptables -t nat -A PREROUTING -p udp --dport $START:$END -j DNAT --to-destination $HOME_IP
    else
        iptables -t nat -A PREROUTING -p tcp --dport $P -j DNAT --to-destination $HOME_IP
        iptables -t nat -A PREROUTING -p udp --dport $P -j DNAT --to-destination $HOME_IP
    fi
    echo "Forwarded port $P to $HOME_IP"
done

# Save iptables rules
netfilter-persistent save

# Reload WireGuard
if systemctl is-active --quiet wg-quick@wg0; then
    echo "Reloading wg0..."
    wg syncconf wg0 <(wg-quick strip wg0)
else
    echo "Starting wg0..."
    systemctl enable wg-quick@wg0
    wg-quick up wg0 || wg-quick up /etc/wireguard/wg0.conf
fi

echo
echo "✅ VPS setup complete!"
echo "Forwarded ports: $PORTS"
echo "SSH to VPS on port 23"
