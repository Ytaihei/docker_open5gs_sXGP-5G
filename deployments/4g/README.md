# 4G Core Network Deployment

This directory contains the 4G EPC (Evolved Packet Core) deployment configuration.

## Network Architecture

- **Bridge Network**: `br-open5gs_4g`
- **Subnet**: `192.168.10.0/24`
- **Gateway**: `192.168.10.2`

### Physical Interface Connection

The `eno1` (RJ45) interface must be connected to the bridge for eNB access:

```bash
sudo ip link set eno1 master br-open5gs_4g
```

## Quick Start

### Prerequisites

1. Ensure the bridge network exists:
```bash
docker network ls | grep br-open5gs_4g
```

If not, create it:
```bash
docker network create \
  --driver=bridge \
  --subnet=192.168.10.0/24 \
  --gateway=192.168.10.2 \
  --opt com.docker.network.bridge.name=br-open5gs_4g \
  br-open5gs_4g
```

2. Connect eno1 to the bridge:
```bash
sudo ip link set eno1 master br-open5gs_4g
```

### Starting the 4G Core

Simply run from this directory:

```bash
docker compose up -d
```

**No `--env-file` option needed!** The `.env` file in this directory is automatically loaded.

### Stopping the 4G Core

```bash
docker compose down
```

## Components

| Service | IP Address | Ports | Description |
|---------|------------|-------|-------------|
| MongoDB | 192.168.10.30 | 27017 | Database |
| WebUI | 192.168.10.54 | 9999/tcp | Management UI |
| HSS | 192.168.10.31 | 3868/sctp | Home Subscriber Server |
| MME | 192.168.10.37 | 36412/sctp | Mobility Management Entity |
| SGWC | 192.168.10.33 | 2123/udp | Serving Gateway Control |
| SGWU | 192.168.10.34 | 2152/udp | Serving Gateway User Plane |
| SMF | 192.168.10.35 | - | Session Management Function |
| UPF | 192.168.10.36 | 2152/udp | User Plane Function |
| PCRF | 192.168.10.32 | 3873/sctp | Policy Control |

## eNB Configuration

External eNB hardware should be configured with:

- **MME IP**: `192.168.10.37`
- **MME Port**: `36412/sctp`
- **SGWU IP**: `192.168.10.34` (for S1-U interface)
- **Gateway**: `192.168.10.2`

### eNB WebUI Access

From your local machine via SSH tunnel:

```bash
ssh -p 2002 -L 8443:192.168.10.111:443 taihei@<HOST_IP>
```

Then access: https://localhost:8443

## Configuration Files

- **`.env`**: Environment variables (automatically loaded)
- **`docker-compose.yaml`**: Service definitions

## Logs

Container logs are stored in: `../../log/`

View logs:
```bash
docker compose logs -f mme
docker compose logs -f sgwu
```

## Troubleshooting

### Check connectivity to eNB

```bash
ping -I br-open5gs_4g 192.168.10.111
curl -k https://192.168.10.111
```

### Verify containers are running

```bash
docker compose ps
```

### Check MME logs for S1 connection

```bash
docker compose logs mme | grep -i "s1 setup"
```

## Network Isolation

This deployment uses an isolated internal network (`192.168.10.0/24`) that is independent of upstream network changes. Only the SSH tunnel target IP needs to be updated when the upstream network changes.

For detailed network setup instructions, see `../README_NETWORK_SETUP.md`.
