# Deployments Directory

This directory contains organized deployment configurations for different network setups.

## Directory Structure

```
deployments/
├── 4g/                          # 4G EPC deployment
│   ├── .env                     # Auto-loaded environment file
│   ├── docker-compose.yaml      # Service definitions
│   └── README.md                # 4G-specific documentation
├── 5g/                          # 5G Standalone (future)
│   └── README.md
├── s1n2/                        # S1-N2 converter (reference)
│   ├── .env                     # Copy of sXGP-5G/.env_s1n2
│   └── README.md                # Points to ../../sXGP-5G/
└── README.md                    # This file
```

## Key Improvements

### ✅ No `--env-file` Required

Each deployment directory contains a `.env` file that is **automatically loaded** by Docker Compose. Simply run:

```bash
cd deployments/4g
docker compose up -d
```

### ✅ No Hardcoded IPs

All IP addresses are defined in environment variables, making it easy to reconfigure if needed.

### ✅ Isolated Deployments

Each deployment has its own:
- Network configuration
- Environment variables
- Service definitions
- Documentation

### ✅ Consistent Structure

All deployments follow the same pattern, making it easy to understand and maintain.

## Available Deployments

### 1. 4G EPC (Evolved Packet Core)

**Location**: `deployments/4g/`

**Purpose**: Full 4G core network for connecting physical eNB hardware

**Network**: `192.168.10.0/24` on `br-open5gs_4g`

**Quick Start**:
```bash
cd deployments/4g
docker compose up -d
```

**Components**:
- MME (Mobility Management)
- HSS (Home Subscriber Server)
- SGWC/SGWU (Serving Gateway)
- SMF/UPF (Session Management)
- PCRF (Policy Control)
- MongoDB + WebUI

**Use Cases**:
- Testing with physical eNB (192.168.10.110/111)
- Production 4G deployment
- Isolated from upstream network changes

### 2. S1-N2 Protocol Converter (Reference)

**Location**: `deployments/s1n2/` (points to `sXGP-5G/`)

**Purpose**: Bridge 4G eNB to 5G core using protocol conversion

**Network**: `172.24.0.0/16` on `br-s1n2-integrated`

**Quick Start**:
```bash
cd ../../sXGP-5G
docker compose -f docker-compose.s1n2.yml up -d
```

**Components**:
- S1-N2 Converter (4G ↔ 5G translation)
- Full 5G Core (AMF, SMF, UPF, etc.)
- srsLTE eNB (simulated 4G base station)
- srsUE (simulated 4G user equipment)

**Use Cases**:
- Testing 4G-to-5G migration
- Protocol conversion research
- Integrated testing environment

### 3. 5G Standalone (Future)

**Location**: `deployments/5g/` (placeholder)

**Purpose**: Pure 5G SA (Standalone) deployment

**Status**: Not yet implemented

## Running Multiple Deployments

You can run multiple deployments simultaneously as they use different networks:

```bash
# Terminal 1: Start 4G core
cd deployments/4g
docker compose up -d

# Terminal 2: Start S1-N2 system (includes 5G core)
cd ../../sXGP-5G
docker compose -f docker-compose.s1n2.yml up -d
```

**Networks in use**:
- 4G: `192.168.10.0/24` (br-open5gs_4g)
- S1-N2: `172.24.0.0/16` (br-s1n2-integrated)

## Migration Guide

### From Old Structure

**Old way** (in `deployments/`):
```bash
docker compose --env-file .env_4g -f 4g-data-only-deploy.yaml up -d
```

**New way** (in `deployments/4g/`):
```bash
cd 4g
docker compose up -d
```

### Benefits of New Structure

1. **No command-line options needed** - `.env` is auto-loaded
2. **Cleaner workspace** - Each deployment in its own directory
3. **Better documentation** - Deployment-specific README files
4. **Easier to maintain** - Clear separation of concerns
5. **Consistent patterns** - All deployments work the same way

## Network Setup

### 4G Deployment Requirements

1. **Create bridge network** (if not exists):
```bash
docker network create \
  --driver=bridge \
  --subnet=192.168.10.0/24 \
  --gateway=192.168.10.2 \
  --opt com.docker.network.bridge.name=br-open5gs_4g \
  br-open5gs_4g
```

2. **Connect physical interface** (for eNB access):
```bash
sudo ip link set eno1 master br-open5gs_4g
```

3. **Start deployment**:
```bash
cd deployments/4g
docker compose up -d
```

For detailed network setup instructions, see `README_NETWORK_SETUP.md`.

## Legacy Files

The following files in the parent `deployments/` directory are now superseded:

- `.env_4g` → `4g/.env`
- `4g-data-only-deploy.yaml` → `4g/docker-compose.yaml`
- `.env_5g` → (future: `5g/.env`)
- `5g-data-only-deploy.yaml` → (future: `5g/docker-compose.yaml`)

These legacy files can be kept for reference or removed after migration is complete.

## Helper Scripts

### Network Setup Script

Run before starting 4G deployment:

```bash
cd deployments
./setup_network.sh
```

This script:
- Verifies bridge network exists
- Connects eno1 to the bridge
- Tests connectivity to eNB

### Packet Capture

For 4G network:
```bash
cd ..
./scripts/tcpdump_4g.sh
```

## Troubleshooting

### Issue: Environment variables not found

**Solution**: Make sure you're in the deployment directory (e.g., `deployments/4g/`) and the `.env` file exists.

### Issue: Network already in use

**Solution**: Stop conflicting deployments or use different network names.

### Issue: Cannot access eNB WebUI

**Solution**: Ensure eno1 is connected to the bridge:
```bash
sudo ip link set eno1 master br-open5gs_4g
ping -I br-open5gs_4g 192.168.10.111
```

### Issue: Port conflicts

**Solution**: Check if another deployment is using the same ports (e.g., WebUI on 9999/tcp).

## Documentation

- **4G Deployment**: `4g/README.md`
- **S1-N2 Deployment**: `s1n2/README.md` and `../sXGP-5G/README.md`
- **Network Setup**: `README_NETWORK_SETUP.md`
- **Project Overview**: `../README.md`

## Contributing

When adding new deployments, follow this pattern:

1. Create a new directory: `deployments/<name>/`
2. Add `.env` file with all required variables
3. Add `docker-compose.yaml` with relative paths (`../../`)
4. Add `README.md` with deployment-specific documentation
5. Update this main README with the new deployment

## Support

For questions or issues, check:
1. Deployment-specific README
2. Docker logs: `docker compose logs`
3. Network connectivity: `ping`, `ip addr`, `docker network inspect`
