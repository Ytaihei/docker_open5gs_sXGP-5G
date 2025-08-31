#!/bin/bash

# Docker images build script for reorganized project structure
cd "$(dirname "$0")/.."

echo "Building Docker images..."

# Build main Open5GS image
echo "Building docker_open5gs image..."
docker build -t docker_open5gs -f open5gs/base/Dockerfile .

# Build srsLTE image if needed
if [ -d "ran/srslte" ]; then
    echo "Building srsLTE image..."
    docker build -t srslte -f ran/srslte/Dockerfile ran/srslte/
fi

# Build srsRAN image if needed
if [ -d "ran/srsran" ]; then
    echo "Building srsRAN image..."
    docker build -t srsran -f ran/srsran/Dockerfile ran/srsran/
fi

echo "Docker images build completed!"
