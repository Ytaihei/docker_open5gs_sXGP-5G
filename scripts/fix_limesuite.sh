#!/bin/bash

# Quick fix script for LimeSuite build issue
set -e

PROJECT_ROOT="/home/taihei/docker_open5gs_sXGP-5G"
cd "$PROJECT_ROOT"

echo "Building LimeSuite with fixed Dockerfile..."

# Create a simple Dockerfile for LimeSuite
cat > Dockerfile.limesuite << 'EOF'
FROM ubuntu:20.04
LABEL maintainer="LimeSuite Team"

ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    libusb-1.0-0-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy source code
COPY sources/LimeSuite /LimeSuite

# Build LimeSuite
WORKDIR /LimeSuite
RUN rm -rf build && mkdir build && cd build && \
    cmake ../ && \
    make -j$(nproc) && \
    make install && \
    ldconfig

WORKDIR /
CMD ["sleep", "infinity"]
EOF

# Build the image
docker build --no-cache --force-rm -t docker_limesuite -f Dockerfile.limesuite .

# Cleanup
rm -f Dockerfile.limesuite

echo "✅ Successfully built docker_limesuite"
