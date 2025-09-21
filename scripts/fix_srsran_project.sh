#!/bin/bash

# Fix srsRAN Project build issue
set -e

PROJECT_ROOT="/home/taihei/docker_open5gs_sXGP-5G"
cd "$PROJECT_ROOT"

echo "Building srsRAN Project with warning fix..."

# Create a fixed Dockerfile for srsRAN Project
cat > Dockerfile.srsran_fixed << 'EOF'
FROM ubuntu:jammy

ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt-get update && \
    apt-get -y install cmake make gcc g++ pkg-config libfftw3-dev \
                       libmbedtls-dev libsctp-dev libyaml-cpp-dev \
                       software-properties-common && \
    rm -rf /var/lib/apt/lists/*

# Install UHD and ZeroMQ
RUN add-apt-repository ppa:ettusresearch/uhd && \
    apt update && apt -y install libuhd-dev uhd-host && \
    apt -y install libzmq3-dev && \
    rm -rf /var/lib/apt/lists/*

# Copy source code
COPY sources/srsRAN_Project /srsRAN_Project

# Build srsRAN Project with relaxed warnings
WORKDIR /srsRAN_Project
RUN mkdir build && cd build && \
    cmake ../ -DENABLE_EXPORT=ON -DENABLE_ZEROMQ=ON -DCMAKE_CXX_FLAGS="-Wno-error=switch" && \
    make -j$(nproc) && \
    make install && \
    ldconfig

# Set working directory
WORKDIR /srsRAN_Project/build

CMD ["sleep", "infinity"]
EOF

# Build the fixed image
docker build --no-cache --force-rm -t docker_srsran -f Dockerfile.srsran_fixed .

# Cleanup
rm -f Dockerfile.srsran_fixed

echo "✅ Successfully built docker_srsran with warning fix"
