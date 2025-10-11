# WG Tunnel: Home Server ↔ VPS Tunnel

This repository provides scripts to make your **home server accessible via a VPS** using **WireGuard VPN**, forwarding **all outgoing traffic** and specific **incoming ports**.

It supports:

- TCP + UDP port forwarding  
- SSH redirection (VPS SSH → 23, Home SSH via VPS → 22)  
- Custom port ranges input  
- Full outgoing traffic tunneling  
- IPv6 ready  

---

## Table of Contents

- [Requirements](#requirements)  
- [Setup Overview](#setup-overview)  
- [One-line GitHub Installer](#one-line-github-installer)  
- [Phase 1: Home Server Setup](#phase-1-home-server-setup)  
- [Phase 2: VPS Setup](#phase-2-vps-setup)  
- [Usage](#usage)  
- [Notes](#notes)  
- [Troubleshooting](#troubleshooting)  
- [Traffic Flow Diagram](#traffic-flow-diagram)  

---

## Requirements

- **OS:** Ubuntu 24.04 (both Home and VPS)  
- **Root / sudo access**  
- **Public IP** for VPS  
- Ports you want to forward (single or ranges)  

### Packages Installed Automatically

```bash
sudo apt update
sudo apt install -y wireguard iptables iptables-persistent curl net-tools qrencode jq git
```

> `ufw` is **not required** (conflicts with `iptables-persistent`).  

---

## Setup Overview

1. **Universal Installer:** Run the one-line GitHub command and select whether you are on **VPS** or **Home server**.  
2. **Phase 1:** Installs packages, generates WireGuard keys, and shows keys/IPs.  
3. **Phase 2:** Enter required info (peer keys, VPS IP, ports to forward). Scripts configure WireGuard, NAT, port forwarding, and SSH ports.  
4. **Routing:** Home server outgoing traffic exits via VPS.  
5. **Access:** SSH and other services accessible via VPS IP.  

---

## One-line GitHub Installer

Run the following command to download the installer and run it directly:

```bash
bash <(curl -sSL https://raw.githubusercontent.com/BreadCatto/wg-tunnel/main/install.sh)
```

- Select **1) VPS** or **2) Home Server** when prompted.  
- The script installs dependencies, fetches keys, sets up WireGuard, NAT, and port forwarding.  

---

## Phase 1: Home Server Setup

- Generates WireGuard keys  
- Displays suggested WireGuard IP (`10.8.0.2`)  
- Pauses before Phase 2  

> Copy **Home public key** for VPS setup.

---

## Phase 2: VPS Setup

- Generates WireGuard keys  
- Displays suggested WireGuard IP (`10.8.0.1`)  
- Prompts for:  
  - Home public key  
  - Ports/ranges to forward (e.g., `22 25565 8000-9000`)  
  - VPS interface IP if custom  
- Applies NAT, port forwarding, and WireGuard configuration  
- Changes VPS SSH port to **23**, forwards Home SSH to **22**  

---

## Usage

### SSH

- **VPS SSH:**

```bash
ssh -p 23 root@VPS_IP
```

- **Home SSH via VPS:**

```bash
ssh -p 22 user@VPS_IP
```

### Other Services

- Connect using **VPS IP + forwarded port** (Minecraft, web, game servers)  
- Outgoing traffic from Home goes through VPS

### WireGuard Status

```bash
wg show
```

---

## Notes

- Ports can be **single or ranges**:

```text
22 25565 8000-9000
```

- Scripts are interactive; keys, IPs, and ports are shown before applying.  
- IP forwarding and NAT rules enabled automatically.  
- **iptables-persistent** ensures rules survive reboot.  

---

## Troubleshooting

- Restart WireGuard if VPN fails:

```bash
systemctl restart wg-quick@wg0
wg show
```

- Reset iptables rules:

```bash
iptables -F
iptables -t nat -F
netfilter-persistent save
```

---

## Traffic Flow Diagram

```text
+----------------+           +----------------+           +---------------+
|  Home Server   | <-------> |     VPS        | <-------> |  Internet     |
|  10.8.0.2/24   | WireGuard| 10.8.0.1/24    | NAT/Port  |  Public IP    |
+----------------+           +----------------+           +---------------+
```

---

## Example Port Forward Input

```text
22 25565 8000-9000
```

- Forwards **TCP + UDP** for single ports and ranges.  
- Port `22` allows SSH to Home server via VPS IP.  

---


his README is **ready for GitHub**, all code blocks are copyable using the GitHub **“copy” button**, and users can follow the **one-line installer** without cloning manually.
