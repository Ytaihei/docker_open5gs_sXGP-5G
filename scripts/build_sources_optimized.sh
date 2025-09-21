#!/bin/bash

# BSD 2-Clause License
# Copyright (c) 2020-2025, Supreeth Herle
# All rights reserved.

# Advanced script to build optimized Docker images from sources directory
# Features: Multi-stage builds, parallel building, build caching

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SOURCES_DIR="$PROJECT_ROOT/sources"

# Build configuration
PARALLEL_BUILDS=false
USE_CACHE=true
BUILD_TARGET="all"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --parallel)
            PARALLEL_BUILDS=true
            shift
            ;;
        --no-cache)
            USE_CACHE=false
            shift
            ;;
        --target)
            BUILD_TARGET="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --parallel    Build images in parallel (experimental)"
            echo "  --no-cache    Disable Docker build cache"
            echo "  --target      Build specific target (open5gs|srsran4g|srsran5g|sdr|all)"
            echo "  --help        Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo "==================================================================="
echo "Advanced Docker Build Script for Sources"
echo "==================================================================="
echo "Build target: $BUILD_TARGET"
echo "Parallel builds: $PARALLEL_BUILDS"
echo "Use cache: $USE_CACHE"
echo "Project root: $PROJECT_ROOT"
echo "Sources directory: $SOURCES_DIR"
echo "==================================================================="

# Check if sources directory exists
if [ ! -d "$SOURCES_DIR" ]; then
    echo "❌ Error: Sources directory not found at $SOURCES_DIR"
    echo "Please run ./clone_sources.sh first to download source codes."
    exit 1
fi

# Function to build Docker image with advanced options
build_image_advanced() {
    local component="$1"
    local dockerfile_content="$2"
    local image_name="$3"
    local build_args="$4"

    echo ""
    echo "🔨 Building: $component -> $image_name"

    # Create temporary Dockerfile
    local temp_dockerfile=$(mktemp)
    echo "$dockerfile_content" > "$temp_dockerfile"

    # Prepare build command
    local build_cmd="docker build"

    if [ "$USE_CACHE" = false ]; then
        build_cmd="$build_cmd --no-cache"
    fi

    build_cmd="$build_cmd --force-rm -t $image_name -f $temp_dockerfile"

    if [ -n "$build_args" ]; then
        build_cmd="$build_cmd $build_args"
    fi

    build_cmd="$build_cmd $PROJECT_ROOT"

    # Execute build
    cd "$PROJECT_ROOT"
    eval "$build_cmd"

    # Cleanup
    rm -f "$temp_dockerfile"

    echo "✅ Successfully built: $image_name"
}

# Optimized Dockerfiles with multi-stage builds

# SDR Base Image (shared dependencies)
SDR_BASE_DOCKERFILE='
FROM ubuntu:20.04 as sdr-base
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    build-essential cmake git pkg-config \
    libusb-1.0-0-dev libfftw3-dev \
    && rm -rf /var/lib/apt/lists/*
'

# SoapySDR Optimized Dockerfile
SOAPYSDR_DOCKERFILE="
$SDR_BASE_DOCKERFILE

FROM sdr-base as soapysdr-build
RUN apt-get update && apt-get install -y \
    libpython3-dev python3-numpy swig \
    && rm -rf /var/lib/apt/lists/*

COPY sources/SoapySDR /SoapySDR
WORKDIR /SoapySDR
RUN mkdir build && cd build && \
    cmake -DCMAKE_BUILD_TYPE=Release ../ && \
    make -j\$(nproc) && \
    make install && \
    ldconfig

FROM ubuntu:20.04
RUN apt-get update && apt-get install -y \
    libpython3-dev python3-numpy \
    && rm -rf /var/lib/apt/lists/*
COPY --from=soapysdr-build /usr/local /usr/local
RUN ldconfig
CMD [\"sleep\", \"infinity\"]
"

# Open5GS Optimized Dockerfile
OPEN5GS_DOCKERFILE='
FROM ubuntu:20.04 as build-stage
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    python3-pip python3-setuptools python3-wheel ninja-build \
    build-essential flex bison git cmake libsctp-dev \
    libgnutls28-dev libgcrypt-dev libssl-dev libidn11-dev \
    libmongoc-dev libbson-dev libyaml-dev libnghttp2-dev \
    libmicrohttpd-dev libcurl4-gnutls-dev libtins-dev \
    libtalloc-dev meson \
    && rm -rf /var/lib/apt/lists/*

COPY sources/open5gs /open5gs
WORKDIR /open5gs
RUN meson build --prefix=/open5gs/install --buildtype=release
RUN ninja -C build
RUN ninja -C build install

FROM ubuntu:20.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    libsctp1 libgnutls30 libgcrypt20 libssl1.1 \
    libidn11 libmongoc-1.0-0 libbson-1.0-0 libyaml-0-2 \
    libnghttp2-14 libmicrohttpd12 libcurl4 libtins4.0 \
    libtalloc2 && rm -rf /var/lib/apt/lists/*

COPY --from=build-stage /open5gs/install /open5gs/install
WORKDIR /open5gs/install
EXPOSE 3868 5868 8805 2123 7777 9999
CMD ["sleep", "infinity"]
'

# srsRAN 4G Optimized Dockerfile
SRSRAN4G_DOCKERFILE='
FROM ubuntu:20.04 as build-stage
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    build-essential cmake libfftw3-dev libmbedtls-dev \
    libboost-program-options-dev libconfig++-dev \
    libsctp-dev libpcsclite-dev git \
    && rm -rf /var/lib/apt/lists/*

COPY sources/srsRAN_4G /srsRAN_4G
WORKDIR /srsRAN_4G
RUN mkdir build && cd build && \
    cmake -DCMAKE_BUILD_TYPE=Release ../ && \
    make -j$(nproc)

FROM ubuntu:20.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    libfftw3-3 libmbedtls12 libboost-program-options1.71.0 \
    libconfig++9v5 libsctp1 libpcsclite1 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build-stage /srsRAN_4G/build /srsRAN_4G/build
COPY --from=build-stage /srsRAN_4G/srsenb /srsRAN_4G/srsenb
COPY --from=build-stage /srsRAN_4G/srsue /srsRAN_4G/srsue
COPY --from=build-stage /srsRAN_4G/srsepc /srsRAN_4G/srsepc
WORKDIR /srsRAN_4G/build
CMD ["sleep", "infinity"]
'

# srsRAN Project (5G) Optimized Dockerfile
SRSRAN5G_DOCKERFILE='
FROM ubuntu:20.04 as build-stage
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    cmake make gcc g++ pkg-config libfftw3-dev \
    libmbedtls-dev libsctp-dev libyaml-cpp-dev \
    libgtest-dev git \
    && rm -rf /var/lib/apt/lists/*

COPY sources/srsRAN_Project /srsRAN_Project
WORKDIR /srsRAN_Project
RUN mkdir build && cd build && \
    cmake -DCMAKE_BUILD_TYPE=Release ../ && \
    make -j$(nproc)

FROM ubuntu:20.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    libfftw3-3 libmbedtls12 libsctp1 libyaml-cpp0.6 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build-stage /srsRAN_Project/build /srsRAN_Project/build
COPY --from=build-stage /srsRAN_Project/configs /srsRAN_Project/configs
WORKDIR /srsRAN_Project/build
CMD ["sleep", "infinity"]
'

# Build functions for different targets
build_sdr_components() {
    echo "🔧 Building SDR components..."

    if [ -d "$SOURCES_DIR/SoapySDR" ]; then
        build_image_advanced "SoapySDR" "$SOAPYSDR_DOCKERFILE" "docker_soapysdr_optimized"
    fi

    # Add other SDR components as needed
}

build_open5gs() {
    echo "🔧 Building Open5GS..."

    if [ -d "$SOURCES_DIR/open5gs" ]; then
        # Use existing Dockerfile instead of generated one
        cd "$PROJECT_ROOT"
        docker build --no-cache --force-rm -t docker_open5gs -f open5gs/base/Dockerfile .
        echo "✅ Successfully built: docker_open5gs"
    fi
}

build_srsran4g() {
    echo "🔧 Building srsRAN 4G..."

    if [ -d "$SOURCES_DIR/srsRAN_4G" ]; then
        # Use existing Dockerfile instead of generated one
        cd "$PROJECT_ROOT"
        docker build --no-cache --force-rm -t docker_srslte -f ran/srslte/Dockerfile .
        echo "✅ Successfully built: docker_srslte"
    fi
}

build_srsran5g() {
    echo "🔧 Building srsRAN Project (5G)..."

    if [ -d "$SOURCES_DIR/srsRAN_Project" ]; then
        # Use existing Dockerfile instead of generated one
        cd "$PROJECT_ROOT"
        docker build --no-cache --force-rm -t docker_srsran -f ran/srsran/Dockerfile .
        echo "✅ Successfully built: docker_srsran"
    fi
}

# Main build execution
case "$BUILD_TARGET" in
    "sdr")
        build_sdr_components
        ;;
    "open5gs")
        build_open5gs
        ;;
    "srsran4g")
        build_srsran4g
        ;;
    "srsran5g")
        build_srsran5g
        ;;
    "all")
        if [ "$PARALLEL_BUILDS" = true ]; then
            echo "⚡ Starting parallel builds..."
            build_sdr_components &
            build_open5gs &
            build_srsran4g &
            build_srsran5g &
            wait
            echo "✅ All parallel builds completed!"
        else
            echo "🔄 Starting sequential builds..."
            build_sdr_components
            build_open5gs
            build_srsran4g
            build_srsran5g
        fi
        ;;
    *)
        echo "❌ Unknown build target: $BUILD_TARGET"
        exit 1
        ;;
esac

echo ""
echo "==================================================================="
echo "✅ Build process completed!"
echo "==================================================================="
echo ""
echo "Built images:"
docker images | grep -E "(docker_soapysdr|docker_open5gs|docker_srslte|docker_srsran)" || echo "No deployment-compatible images found"

echo ""
echo "Usage examples:"
echo "  docker run -it docker_open5gs bash"
echo "  docker run -it docker_srsran bash"
echo "  docker run -it docker_srslte bash"
