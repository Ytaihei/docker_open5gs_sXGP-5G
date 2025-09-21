#!/bin/bash

# Quick build script for essential deployment images only
set -e

PROJECT_ROOT="/home/taihei/docker_open5gs_sXGP-5G"
SOURCES_DIR="$PROJECT_ROOT/sources"

echo "Building essential images for deployments..."

cd "$PROJECT_ROOT"

# 1. Build Open5GS using existing Dockerfile
if [ -d "$SOURCES_DIR/open5gs" ]; then
    echo "Building Open5GS..."
    docker build --no-cache --force-rm -t docker_open5gs -f open5gs/base/Dockerfile .
    echo "✅ Successfully built docker_open5gs"
else
    echo "❌ Open5GS source not found"
fi

# 2. Build srsRAN 4G using existing Dockerfile
if [ -d "$SOURCES_DIR/srsRAN_4G" ]; then
    echo "Building srsRAN 4G..."
    docker build --no-cache --force-rm -t docker_srslte -f ran/srslte/Dockerfile .
    echo "✅ Successfully built docker_srslte"
else
    echo "❌ srsRAN_4G source not found"
fi

# 3. Build srsRAN Project using existing Dockerfile
if [ -d "$SOURCES_DIR/srsRAN_Project" ]; then
    echo "Building srsRAN Project..."
    docker build --no-cache --force-rm -t docker_srsran -f ran/srsran/Dockerfile .
    echo "✅ Successfully built docker_srsran"
else
    echo "❌ srsRAN_Project source not found"
fi

echo ""
echo "✅ Essential images built successfully!"
echo "You can now use these images with the deployment YAML files:"
echo "  - docker_open5gs (for 5G/4G core network)"
echo "  - docker_srslte (for 4G RAN)"
echo "  - docker_srsran (for 5G RAN)"
