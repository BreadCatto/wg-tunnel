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
echo "You can copy this public key to the Home script."
echo
read -p "Press ENTER to start Phase 2 (enter required info and apply config)..."

# Phase 2: ask for inputs
read -p "Enter Home WireGuard public key: " HOME_PUB
read -p "Enter VPS WireGuard interface IP (default 10.8.0.1): " WG_IP
WG_IP=${WG_IP:-10.8.0.1}
read -p "Enter ports/ranges to forward (e.g., '22 25565 8000-9000'): " PORTS

# Change SSH port to 23
sed -i 's/^#Port 22/Port 23/' /etc/ssh/sshd_config
sed -i 's/^Port 22/Port 23/' /etc/ssh/sshd_config
systemctl restart ssh

# Create WireGuard config
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
sysctl -w net.ipv6.conf.all.forwarding=1
sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.conf
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
sed -i '/net.ipv6.conf.all.forwarding/d' /etc/sysctl.conf
echo "net.ipv6.conf.all.forwarding=1" | sudo tee -a /etc/sysctl.conf

# Flush iptables
iptables -F
iptables -t nat -F

# Detect default interface
DEFAULT_IF=$(ip route show default | awk '/default/ {print $5; exit}')

# NAT outgoing traffic from home through VPS
iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o $DEFAULT_IF -j MASQUERADE
iptables -A FORWARD -i wg0 -j ACCEPT
iptables -A FORWARD -o wg0 -j ACCEPT

# Forward entered ports/ranges TCP+UDP to home
for P in $PORTS; do
    if [[ $P == *"-"* ]]; then
        START=$(echo $P | cut -d'-' -f1)
        END=$(echo $P | cut -d'-' -f2)
        iptables -t nat -A PREROUTING -p tcp --dport $START:$END -j DNAT --to-destination 10.8.0.2
        iptables -t nat -A PREROUTING -p udp --dport $START:$END -j DNAT --to-destination 10.8.0.2
        iptables -A FORWARD -p tcp -d 10.8.0.2 --dport $START:$END -j ACCEPT
        iptables -A FORWARD -p udp -d 10.8.0.2 --dport $START:$END -j ACCEPT
    else
        iptables -t nat -A PREROUTING -p tcp --dport $P -j DNAT --to-destination 10.8.0.2
        iptables -t nat -A PREROUTING -p udp --dport $P -j DNAT --to-destination 10.8.0.2
        iptables -A FORWARD -p tcp -d 10.8.0.2 --dport $P -j ACCEPT
        iptables -A FORWARD -p udp -d 10.8.0.2 --dport $P -j ACCEPT
    fi
done

# Forward port 22 for home SSH via VPS IP
iptables -t nat -A PREROUTING -p tcp --dport 22 -j DNAT --to-destination 10.8.0.2
iptables -A FORWARD -p tcp -d 10.8.0.2 --dport 22 -j ACCEPT

# Save iptables rules
netfilter-persistent save

# Enable WireGuard
systemctl enable wg-quick@wg0
wg-quick up wg0 || wg-quick up /etc/wireguard/wg0.conf

echo
echo "✅ VPS setup Phase 2 complete!"
echo "SSH to VPS: port 23"
echo "SSH to Home via VPS: port 22"
echo "Forwarded ports/ranges: $PORTS"
