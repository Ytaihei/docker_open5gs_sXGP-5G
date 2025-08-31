#!/bin/bash

# Simple clone script for testing - only essential components with latest versions

set -e

REPO_ROOT=$(pwd)
SOURCES_DIR="$REPO_ROOT/sources"

echo "Creating sources directory structure..."
mkdir -p "$SOURCES_DIR"

# Clone open5gs (latest stable)
echo "Cloning open5gs..."
if [ ! -d "$SOURCES_DIR/open5gs" ]; then
    git clone --recursive https://github.com/open5gs/open5gs "$SOURCES_DIR/open5gs"
    cd "$SOURCES_DIR/open5gs"
    # Use latest stable release
    git checkout v2.7.2
    cd - > /dev/null
else
    echo "open5gs already exists, skipping..."
fi

# Clone kamailio (latest stable)
echo "Cloning kamailio..."
if [ ! -d "$SOURCES_DIR/kamailio" ]; then
    git clone https://github.com/kamailio/kamailio "$SOURCES_DIR/kamailio"
    cd "$SOURCES_DIR/kamailio"
    # Use latest stable release
    git checkout 5.8
    cd - > /dev/null
else
    echo "kamailio already exists, skipping..."
fi

# Clone SoapySDR (latest master)
echo "Cloning SoapySDR..."
if [ ! -d "$SOURCES_DIR/SoapySDR" ]; then
    git clone https://github.com/pothosware/SoapySDR.git "$SOURCES_DIR/SoapySDR"
    # Use latest master
else
    echo "SoapySDR already exists, skipping..."
fi

# Clone LimeSuite (latest master)
echo "Cloning LimeSuite..."
if [ ! -d "$SOURCES_DIR/LimeSuite" ]; then
    git clone https://github.com/myriadrf/LimeSuite.git "$SOURCES_DIR/LimeSuite"
    # Use latest master
else
    echo "LimeSuite already exists, skipping..."
fi

# Clone bladeRF (use specific tag that works)
echo "Cloning bladeRF..."
if [ ! -d "$SOURCES_DIR/bladeRF" ]; then
    git clone https://github.com/Nuand/bladeRF.git "$SOURCES_DIR/bladeRF"
    cd "$SOURCES_DIR/bladeRF"
    git checkout tags/2024.05
    cd - > /dev/null
else
    echo "bladeRF already exists, skipping..."
fi

# Clone SoapyBladeRF (latest master)
echo "Cloning SoapyBladeRF..."
if [ ! -d "$SOURCES_DIR/SoapyBladeRF" ]; then
    git clone https://github.com/pothosware/SoapyBladeRF.git "$SOURCES_DIR/SoapyBladeRF"
    # Use latest master
else
    echo "SoapyBladeRF already exists, skipping..."
fi

# Clone srsGUI (latest master)
echo "Cloning srsGUI..."
if [ ! -d "$SOURCES_DIR/srsGUI" ]; then
    git clone https://github.com/srsran/srsGUI "$SOURCES_DIR/srsGUI"
    # Use latest master
else
    echo "srsGUI already exists, skipping..."
fi

# Clone srsRAN_4G (latest master)
echo "Cloning srsRAN_4G..."
if [ ! -d "$SOURCES_DIR/srsRAN_4G" ]; then
    git clone https://github.com/srsran/srsRAN_4G.git "$SOURCES_DIR/srsRAN_4G"
    # Use latest master
else
    echo "srsRAN_4G already exists, skipping..."
fi

# Clone srsRAN_Project (latest master)
echo "Cloning srsRAN_Project..."
if [ ! -d "$SOURCES_DIR/srsRAN_Project" ]; then
    git clone https://github.com/srsran/srsRAN_Project.git "$SOURCES_DIR/srsRAN_Project"
    # Use latest master
else
    echo "srsRAN_Project already exists, skipping..."
fi

# Clone UERANSIM (latest master)
echo "Cloning UERANSIM..."
if [ ! -d "$SOURCES_DIR/UERANSIM" ]; then
    git clone https://github.com/aligungr/UERANSIM "$SOURCES_DIR/UERANSIM"
    # Use latest master
else
    echo "UERANSIM already exists, skipping..."
fi

echo "All essential source codes have been cloned successfully!"
echo "Source codes are located in: $SOURCES_DIR"
echo ""
echo "To build Docker images, run: ./build_from_source.sh"
