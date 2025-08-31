#!/bin/bash

# BSD 2-Clause License
# Copyright (c) 2020-2025, Supreeth Herle
# All rights reserved.

# Script to build Docker images from local source code

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCES_DIR="$SCRIPT_DIR/sources"

echo "Building Docker images from local source code..."

# Check if sources directory exists
if [ ! -d "$SOURCES_DIR" ]; then
    echo "Error: Sources directory not found. Please run ./clone_sources.sh first."
    exit 1
fi

# Check required source directories
REQUIRED_SOURCES=(
    "open5gs"
    "kamailio"
    "SoapySDR"
    "LimeSuite"
    "bladeRF"
    "SoapyBladeRF"
    "srsGUI"
    "srsRAN_4G"
    "srsRAN_Project"
    "opensips"
    "UERANSIM"
    "eupf"
    "pyhss"
)

for source in "${REQUIRED_SOURCES[@]}"; do
    if [ ! -d "$SOURCES_DIR/$source" ]; then
        echo "Warning: $source source directory not found. Some builds may fail."
    fi
done

cd "$SCRIPT_DIR"

# Set environment variables
set -a
source .env
set +a

# Disable UFW and set network parameters
echo "Setting up system parameters..."
sudo ufw disable
sudo sysctl -w net.ipv4.ip_forward=1
sudo cpupower frequency-set -g performance

echo "Building base Docker images..."

# Build docker images for open5gs EPC/5GC components
echo "Building open5gs base image..."
cd base
docker build --no-cache --force-rm -t docker_open5gs .
cd ..

# Build docker images for kamailio IMS components
echo "Building kamailio IMS image..."
cd ims_base
docker build --no-cache --force-rm -t docker_kamailio .
cd ..

# Build docker images for srsRAN_4G eNB + srsUE (4G+5G)
echo "Building srsRAN_4G image..."
cd srslte
docker build --no-cache --force-rm -t docker_srslte .
cd ..

# Build docker images for srsRAN_Project gNB
echo "Building srsRAN_Project image..."
cd srsran
docker build --no-cache --force-rm -t docker_srsran .
cd ..

# Build docker images for UERANSIM (gNB + UE)
echo "Building UERANSIM image..."
cd ueransim
docker build --no-cache --force-rm -t docker_ueransim .
cd ..

# Build docker images for EUPF
echo "Building EUPF image..."
cd eupf
docker build --no-cache --force-rm -t docker_eupf .
cd ..

# Build docker images for OpenSIPS IMS
echo "Building OpenSIPS IMS image..."
cd opensips_ims_base
docker build --no-cache --force-rm -t docker_opensips .
cd ..

# Build additional component images
echo "Building additional component images..."

# Build other docker images
echo "Building other components..."
echo "Note: Run the following commands individually for specific deployments:"
echo ""
echo "# For 4G deployment:"
echo "docker compose -f 4g-volte-deploy.yaml build"
echo ""
echo "# For 5G deployment:"
echo "docker compose -f sa-deploy.yaml build"
echo ""
echo "# For other specific deployments, use the corresponding docker compose files"

echo ""
echo "Base Docker images built successfully!"
echo "You can now use docker compose to deploy your network."
echo ""
echo "To deploy 4G network:"
echo "  docker compose -f 4g-volte-deploy.yaml up"
echo ""
echo "To deploy 5G SA network:"
echo "  docker compose -f sa-deploy.yaml up"
