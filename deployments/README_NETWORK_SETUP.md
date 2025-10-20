# 4G Network Setup Guide

## Network Architecture

This deployment uses an **isolated internal bridge network** (`br-open5gs_4g` / 192.168.10.0/24) that is independent of upstream network changes.

```
┌─────────────────────────────────────────────────────────────┐
│ Host Machine                                                │
│                                                             │
│  ┌──────────────┐         ┌──────────────────────────┐    │
│  │ Upstream NIC │         │ br-open5gs_4g            │    │
│  │ (enxc8a...)  │         │ 192.168.10.2/24          │    │
│  │ 203.178.x.x  │         │                          │    │
│  │ (changeable) │         │  ┌────────────────────┐  │    │
│  └──────────────┘         │  │ eno1 (RJ45 port)   │  │    │
│                           │  │ connects to eNB    │  │    │
│                           │  └────────────────────┘  │    │
│                           │                          │    │
│                           │  ┌────────────────────┐  │    │
│                           │  │ Docker Containers  │  │    │
│                           │  │ - MME: .37         │  │    │
│                           │  │ - HSS: .31         │  │    │
│                           │  │ - SGW: .33/.34     │  │    │
│                           │  │ - WebUI: .54       │  │    │
│                           │  └────────────────────┘  │    │
│                           └──────────────────────────┘    │
│                                                             │
│  External eNB Network (via eno1)                           │
│  ├─ eNB WAN:    192.168.10.110                             │
│  └─ eNB WebUI:  192.168.10.111:443                         │
└─────────────────────────────────────────────────────────────┘
```

## Setup Instructions

### 1. Connect Physical Interface to Bridge

The RJ45 port (`eno1`) must be connected to the internal bridge to enable:
- eNB ↔ MME communication (S1AP/SCTP on port 36412)
- Access to eNB WebUI (192.168.10.111:443)

```bash
sudo ip link set eno1 master br-open5gs_4g
```

**Verify:**
```bash
ip link show eno1 | grep master
# Should show: master br-open5gs_4g
```

### 2. Start the 4G Core

```bash
cd /home/taihei/docker_open5gs_sXGP-5G/deployments
docker compose -f 4g-data-only-deploy.yaml up -d
```

### 3. Access eNB WebUI from Remote

From your local machine, create an SSH tunnel:

```bash
ssh -p 2002 -L 8443:192.168.10.111:443 taihei@<CURRENT_HOST_IP>
```

Then open in browser:
```
https://localhost:8443
```

## Network Isolation Benefits

### ✅ Upstream Network Independence
- Internal bridge uses fixed 192.168.10.0/24
- Upstream IP changes (203.178.x.x → new IP) **do not affect**:
  - eNB ↔ MME connectivity
  - Container networking
  - eNB WebUI access path

### ✅ What Needs Update When Upstream Changes
**Only SSH access command:**
```bash
# Old command
ssh -p 2002 -L 8443:192.168.10.111:443 taihei@203.178.128.98

# New command (after upstream change)
ssh -p 2002 -L 8443:192.168.10.111:443 taihei@<NEW_UPSTREAM_IP>
```

**Nothing else changes** - all internal routing remains identical.

## Persistent Configuration

To make `eno1` bridge connection survive reboots, add to NetworkManager or systemd-networkd:

### Option A: NetworkManager
```bash
sudo nmcli connection add type bridge-slave ifname eno1 master br-open5gs_4g
```

### Option B: systemd-networkd
Create `/etc/systemd/network/10-eno1-bridge.network`:
```ini
[Match]
Name=eno1

[Network]
Bridge=br-open5gs_4g
```

Then restart:
```bash
sudo systemctl restart systemd-networkd
```

## Troubleshooting

### Check Bridge Connectivity
```bash
# Verify bridge IP
ip addr show br-open5gs_4g

# Test eNB reachability
ping -c 4 -I br-open5gs_4g 192.168.10.110
ping -c 4 -I br-open5gs_4g 192.168.10.111

# Test HTTPS to WebUI
curl -k https://192.168.10.111 | head
```

### Check MME Status
```bash
docker logs mme --tail 50
```

### Verify Network Topology
```bash
docker network inspect br-open5gs_4g
bridge link show br-open5gs_4g
```

## FAQ

**Q: Why not use host networking?**
A: Bridge isolation provides better security and predictable routing independent of host network changes.

**Q: Can I access Open5GS WebUI from outside?**
A: Yes, it's published on host port 9999:
```bash
ssh -p 2002 -L 9999:localhost:9999 taihei@<HOST_IP>
# Then open http://localhost:9999
```

**Q: What if upstream network completely changes subnet?**
A: No problem - only SSH tunnel target IP needs updating. Internal 192.168.10.0/24 network remains unchanged.
