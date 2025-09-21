#!/bin/bash

# BSD 2-Clause License
# Copyright (c) 2020-2025, Supreeth Herle
# All rights reserved.

# Script to build all Docker images from sources directory

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SOURCES_DIR="$PROJECT_ROOT/sources"

echo "==================================================================="
echo "Building all Docker images from sources directory"
echo "Project root: $PROJECT_ROOT"
echo "Sources directory: $SOURCES_DIR"
echo "==================================================================="

# Check if sources directory exists
if [ ! -d "$SOURCES_DIR" ]; then
    echo "Error: Sources directory not found at $SOURCES_DIR"
    echo "Please run ./clone_sources.sh first to download source codes."
    exit 1
fi

# Function to check if directory exists
check_source_dir() {
    local dir_name="$1"
    if [ ! -d "$SOURCES_DIR/$dir_name" ]; then
        echo "Warning: $dir_name source directory not found. Skipping..."
        return 1
    fi
    return 0
}

# Function to build Docker image
build_docker_image() {
    local component="$1"
    local dockerfile_path="$2"
    local image_name="$3"
    local build_context="$4"

    echo ""
    echo "-------------------------------------------------------------------"
    echo "Building Docker image for: $component"
    echo "Dockerfile: $dockerfile_path"
    echo "Image name: $image_name"
    echo "Build context: $build_context"
    echo "-------------------------------------------------------------------"

    if [ -f "$dockerfile_path" ]; then
        cd "$build_context"
        docker build --no-cache --force-rm -t "$image_name" -f "$dockerfile_path" .
        echo "✅ Successfully built $image_name"
    else
        echo "❌ Dockerfile not found: $dockerfile_path"
        echo "Creating basic Dockerfile for $component..."
        create_basic_dockerfile "$component" "$dockerfile_path"
        if [ -f "$dockerfile_path" ]; then
            cd "$build_context"
            docker build --no-cache --force-rm -t "$image_name" -f "$dockerfile_path" .
            echo "✅ Successfully built $image_name with generated Dockerfile"
        fi
    fi
    cd "$PROJECT_ROOT"
}

# Function to create basic Dockerfile for components
create_basic_dockerfile() {
    local component="$1"
    local dockerfile_path="$2"
    local dir_path="$(dirname "$dockerfile_path")"

    mkdir -p "$dir_path"

    case "$component" in
        "Open5GS")
            cat > "$dockerfile_path" << 'EOF'
FROM ubuntu:20.04
LABEL maintainer="Open5GS Team"

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Tokyo

# Install dependencies
RUN apt-get update && apt-get install -y \
    python3-pip \
    python3-setuptools \
    python3-wheel \
    ninja-build \
    build-essential \
    flex \
    bison \
    git \
    cmake \
    libsctp-dev \
    libgnutls28-dev \
    libgcrypt-dev \
    libssl-dev \
    libidn11-dev \
    libmongoc-dev \
    libbson-dev \
    libyaml-dev \
    libnghttp2-dev \
    libmicrohttpd-dev \
    libcurl4-gnutls-dev \
    libnghttp2-dev \
    libtins-dev \
    libtalloc-dev \
    meson \
    && rm -rf /var/lib/apt/lists/*

# Copy source code
COPY sources/open5gs /open5gs

# Build Open5GS
WORKDIR /open5gs
RUN meson build --prefix=`pwd`/install
RUN ninja -C build
RUN ninja -C build install

# Set working directory
WORKDIR /open5gs/install

# Expose ports
EXPOSE 3868 5868 8805 2123 7777 9999

CMD ["sleep", "infinity"]
EOF
            ;;
        "SoapySDR")
            cat > "$dockerfile_path" << 'EOF'
FROM ubuntu:20.04
LABEL maintainer="SoapySDR Team"

ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    libpython3-dev \
    python3-numpy \
    swig \
    && rm -rf /var/lib/apt/lists/*

# Copy source code
COPY sources/SoapySDR /SoapySDR

# Build SoapySDR
WORKDIR /SoapySDR
RUN rm -rf build && mkdir build && cd build && \
    cmake ../ && \
    make -j$(nproc) && \
    make install && \
    ldconfig

WORKDIR /
CMD ["sleep", "infinity"]
EOF
            ;;
        "LimeSuite")
            cat > "$dockerfile_path" << 'EOF'
FROM ubuntu:20.04
LABEL maintainer="LimeSuite Team"

ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    libusb-1.0-0-dev \
    libwxgtk3.0-gtk3-dev \
    freeglut3-dev \
    libsoapysdr-dev \
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
            ;;
        "srsRAN_4G")
            cat > "$dockerfile_path" << 'EOF'
FROM ubuntu:20.04
LABEL maintainer="srsRAN Team"

ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    libfftw3-dev \
    libmbedtls-dev \
    libboost-program-options-dev \
    libconfig++-dev \
    libsctp-dev \
    libpcsclite-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy source code
COPY sources/srsRAN_4G /srsRAN_4G

# Build srsRAN_4G
WORKDIR /srsRAN_4G
RUN rm -rf build && mkdir build && cd build && \
    cmake ../ && \
    make -j$(nproc) && \
    make install

WORKDIR /srsRAN_4G/build
CMD ["sleep", "infinity"]
EOF
            ;;
        "srsRAN_Project")
            cat > "$dockerfile_path" << 'EOF'
FROM ubuntu:20.04
LABEL maintainer="srsRAN Project Team"

ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt-get update && apt-get install -y \
    cmake \
    make \
    gcc \
    g++ \
    pkg-config \
    libfftw3-dev \
    libmbedtls-dev \
    libsctp-dev \
    libyaml-cpp-dev \
    libgtest-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy source code
COPY sources/srsRAN_Project /srsRAN_Project

# Build srsRAN_Project
WORKDIR /srsRAN_Project
RUN rm -rf build && mkdir build && cd build && \
    cmake ../ && \
    make -j$(nproc)

WORKDIR /srsRAN_Project/build
CMD ["sleep", "infinity"]
EOF
            ;;
        "bladeRF")
            cat > "$dockerfile_path" << 'EOF'
FROM ubuntu:20.04
LABEL maintainer="bladeRF Team"

ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    libusb-1.0-0-dev \
    libtecla-dev \
    help2man \
    pandoc \
    && rm -rf /var/lib/apt/lists/*

# Copy source code
COPY sources/bladeRF /bladeRF

# Build bladeRF
WORKDIR /bladeRF
RUN rm -rf build && mkdir build && cd build && \
    cmake ../ && \
    make -j$(nproc) && \
    make install && \
    ldconfig

WORKDIR /
CMD ["sleep", "infinity"]
EOF
            ;;
        "srsGUI")
            cat > "$dockerfile_path" << 'EOF'
FROM ubuntu:20.04
LABEL maintainer="srsGUI Team"

ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    libboost-system-dev \
    libboost-test-dev \
    libboost-thread-dev \
    libqwt-qt5-dev \
    qtbase5-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy source code
COPY sources/srsGUI /srsGUI

# Build srsGUI
WORKDIR /srsGUI
RUN rm -rf build && mkdir build && cd build && \
    cmake ../ && \
    make -j$(nproc) && \
    make install

WORKDIR /
CMD ["sleep", "infinity"]
EOF
            ;;
        "SoapyBladeRF")
            cat > "$dockerfile_path" << 'EOF'
FROM ubuntu:20.04
LABEL maintainer="SoapyBladeRF Team"

ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    libsoapysdr-dev \
    libbladerf-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy source code
COPY sources/SoapyBladeRF /SoapyBladeRF

# Build SoapyBladeRF
WORKDIR /SoapyBladeRF
RUN rm -rf build && mkdir build && cd build && \
    cmake ../ && \
    make -j$(nproc) && \
    make install

WORKDIR /
CMD ["sleep", "infinity"]
EOF
            ;;
    esac
}

# Set system parameters
echo "Setting up system parameters..."
# Disable UFW if available (optional)
if command -v ufw >/dev/null 2>&1; then
    echo "Disabling UFW firewall..."
    sudo ufw disable 2>/dev/null || echo "UFW disable failed or not needed"
fi

# Enable IP forwarding (optional)
echo "Enabling IP forwarding..."
sudo sysctl -w net.ipv4.ip_forward=1 2>/dev/null || echo "IP forwarding setup failed or not needed"

# Set CPU governor to performance (optional)
if command -v cpupower >/dev/null 2>&1; then
    echo "Setting CPU governor to performance..."
    sudo cpupower frequency-set -g performance 2>/dev/null || echo "CPU governor setup failed or not needed"
fi

echo ""
echo "Starting Docker image builds..."

# SDR libraries for OTA (Over-The-Air) are not needed for ZMQ simulation
# Commented out to reduce build time and image size:
# - SoapySDR, bladeRF, LimeSuite, SoapyBladeRF are only required for actual SDR hardware

# # 1. Build SoapySDR (base dependency)
# if check_source_dir "SoapySDR"; then
#     build_docker_image "SoapySDR" "$PROJECT_ROOT/docker/soapysdr/Dockerfile" "docker_soapysdr" "$PROJECT_ROOT"
# fi

# # 2. Build bladeRF
# if check_source_dir "bladeRF"; then
#     build_docker_image "bladeRF" "$PROJECT_ROOT/docker/bladerf/Dockerfile" "docker_bladerf" "$PROJECT_ROOT"
# fi

# # 3. Build LimeSuite
# if check_source_dir "LimeSuite"; then
#     build_docker_image "LimeSuite" "$PROJECT_ROOT/docker/limesuite/Dockerfile" "docker_limesuite" "$PROJECT_ROOT"
# fi

# # 4. Build SoapyBladeRF (depends on SoapySDR and bladeRF)
# if check_source_dir "SoapyBladeRF"; then
#     build_docker_image "SoapyBladeRF" "$PROJECT_ROOT/docker/soapybladerf/Dockerfile" "docker_soapybladerf" "$PROJECT_ROOT"
# fi

# 5. Build srsGUI (optional - only needed for real-time monitoring GUI)
if check_source_dir "srsGUI"; then
    build_docker_image "srsGUI" "$PROJECT_ROOT/ran/srsgui/Dockerfile" "docker_srsgui" "$PROJECT_ROOT"
fi

# 6. Build Open5GS (core network) - use existing Dockerfile
if check_source_dir "open5gs"; then
    build_docker_image "Open5GS" "$PROJECT_ROOT/open5gs/base/Dockerfile" "docker_open5gs" "$PROJECT_ROOT"
fi

# 7. Build srsRAN_4G (4G RAN) - use existing Dockerfile with deployment-compatible name
if check_source_dir "srsRAN_4G"; then
    build_docker_image "srsRAN_4G" "$PROJECT_ROOT/ran/srslte/Dockerfile" "docker_srslte" "$PROJECT_ROOT"
fi

# 8. Build srsRAN_Project (5G RAN) - use existing Dockerfile with deployment-compatible name
if check_source_dir "srsRAN_Project"; then
    build_docker_image "srsRAN_Project" "$PROJECT_ROOT/ran/srsran/Dockerfile" "docker_srsran" "$PROJECT_ROOT"
fi

echo ""
echo "==================================================================="
echo "✅ All Docker images built successfully!"
echo "==================================================================="
echo ""
echo "Built images:"
docker images | grep -E "(docker_srsgui|docker_open5gs|docker_srslte|docker_srsran)" || echo "No images found with expected names"

echo ""
echo "==================================================================="
echo "Next steps:"
echo "1. Update your docker-compose files to use these source-built images"
echo "2. Deploy using: docker compose -f <deployment-file>.yaml up"
echo "==================================================================="
