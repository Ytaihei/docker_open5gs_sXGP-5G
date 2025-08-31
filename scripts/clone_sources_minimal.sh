#!/bin/bash

# Minimal source cloning script for YAML-based deployments

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCES_DIR="$REPO_ROOT/sources"

echo "Repository root: $REPO_ROOT"
echo "Sources directory: $SOURCES_DIR"

# Create sources directory
mkdir -p "$SOURCES_DIR"

echo "Cloning minimal required source codes for YAML deployments..."

# 1. ESSENTIAL: Open5GS (core of all deployments)
echo "Cloning Open5GS (ESSENTIAL - used in all YAML files)..."
if [ ! -d "$SOURCES_DIR/open5gs" ]; then
    git clone --recursive https://github.com/open5gs/open5gs "$SOURCES_DIR/open5gs"
    cd "$SOURCES_DIR/open5gs"
    cd "$REPO_ROOT"
else
    echo "Open5GS already exists, skipping..."
fi

# 2. ESSENTIAL: Kamailio (for 4G VoLTE deployments)
echo "Cloning Kamailio (for 4G VoLTE IMS)..."
if [ ! -d "$SOURCES_DIR/kamailio" ]; then
    git clone https://github.com/kamailio/kamailio "$SOURCES_DIR/kamailio"
    cd "$SOURCES_DIR/kamailio"
    git checkout 5.8
    cd "$REPO_ROOT"
else
    echo "Kamailio already exists, skipping..."
fi

# 3. srsRAN 4G (for 4G RAN simulation)
echo "Cloning srsRAN_4G (for 4G RAN)..."
if [ ! -d "$SOURCES_DIR/srsRAN_4G" ]; then
    git clone https://github.com/srsran/srsRAN_4G.git "$SOURCES_DIR/srsRAN_4G"
    cd "$SOURCES_DIR/srsRAN_4G"
    cd "$REPO_ROOT"
else
    echo "srsRAN_4G already exists, skipping..."
fi

# 4. srsRAN Project (for 5G RAN simulation)
echo "Cloning srsRAN_Project (for 5G RAN)..."
if [ ! -d "$SOURCES_DIR/srsRAN_Project" ]; then
    git clone https://github.com/srsran/srsRAN_Project.git "$SOURCES_DIR/srsRAN_Project"
    cd "$SOURCES_DIR/srsRAN_Project"
    cd "$REPO_ROOT"
else
    echo "srsRAN_Project already exists, skipping..."
fi

# 5. PyHSS (for 4G VoLTE IMS HSS)
echo "Cloning PyHSS (for VoLTE IMS HSS)..."
if [ ! -d "$SOURCES_DIR/pyhss" ]; then
    git clone https://github.com/nickvsnetworking/pyhss "$SOURCES_DIR/pyhss"
    cd "$SOURCES_DIR/pyhss"
    cd "$REPO_ROOT"
else
    echo "PyHSS already exists, skipping..."
fi

# 6. Additional dependencies for srsRAN
echo "Cloning srsRAN dependencies..."

# SoapySDR
if [ ! -d "$SOURCES_DIR/SoapySDR" ]; then
    git clone https://github.com/pothosware/SoapySDR.git "$SOURCES_DIR/SoapySDR"
    cd "$SOURCES_DIR/SoapySDR"
    cd "$REPO_ROOT"
else
    echo "SoapySDR already exists, skipping..."
fi

# LimeSuite
if [ ! -d "$SOURCES_DIR/LimeSuite" ]; then
    git clone https://github.com/myriadrf/LimeSuite.git "$SOURCES_DIR/LimeSuite"
    cd "$SOURCES_DIR/LimeSuite"
    cd "$REPO_ROOT"
else
    echo "LimeSuite already exists, skipping..."
fi

# bladeRF
if [ ! -d "$SOURCES_DIR/bladeRF" ]; then
    git clone https://github.com/Nuand/bladeRF.git "$SOURCES_DIR/bladeRF"
    cd "$SOURCES_DIR/bladeRF"
    cd "$REPO_ROOT"
else
    echo "bladeRF already exists, skipping..."
fi

# SoapyBladeRF
if [ ! -d "$SOURCES_DIR/SoapyBladeRF" ]; then
    git clone https://github.com/pothosware/SoapyBladeRF.git "$SOURCES_DIR/SoapyBladeRF"
    cd "$SOURCES_DIR/SoapyBladeRF"
    cd "$REPO_ROOT"
else
    echo "SoapyBladeRF already exists, skipping..."
fi

# srsGUI
if [ ! -d "$SOURCES_DIR/srsGUI" ]; then
    git clone https://github.com/srsran/srsGUI "$SOURCES_DIR/srsGUI"
    cd "$SOURCES_DIR/srsGUI"
    cd "$REPO_ROOT"
else
    echo "srsGUI already exists, skipping..."
fi

echo ""
echo "✅ Minimal source code cloning completed!"
echo "📁 Source codes are located in: $SOURCES_DIR"
echo ""
echo "📋 Cloned components:"
echo "  🟢 open5gs (ESSENTIAL - 5G/4G core)"
echo "  🟢 kamailio (for VoLTE IMS)"
echo "  🟢 srsRAN_4G (for 4G RAN)"
echo "  🟢 srsRAN_Project (for 5G RAN)"
echo "  🟢 pyhss (for VoLTE IMS HSS)"
echo "  🟢 SDR libraries (SoapySDR, LimeSuite, bladeRF, etc.)"
echo ""
echo "🚫 Skipped unused components:"
echo "  ❌ opensips (not used in YAML files)"
echo "  ❌ UERANSIM (not used in YAML files)"
echo "  ❌ eupf (not used in YAML files)"
echo "  ❌ asterisk/IBCF (not used in YAML files)"
echo "  ❌ osmo-epdg/strongswan (not used in YAML files)"
echo ""
