#!/bin/bash

# BSD 2-Clause License
# Copyright (c) 2020-2025, Supreeth Herle
# All rights reserved.

# Script to clone all source codes locally for docker_open5gs

set -e

SOURCES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/sources"

echo "Creating sources directory structure..."
mkdir -p "$SOURCES_DIR"

# Clone open5gs
echo "Cloning open5gs..."
if [ ! -d "$SOURCES_DIR/open5gs" ]; then
    git clone --recursive https://github.com/open5gs/open5gs "$SOURCES_DIR/open5gs"
    cd "$SOURCES_DIR/open5gs"
    git checkout 8e286b67f1ccdd1d6bc31d36b553991337583f33
    cd - > /dev/null
else
    echo "open5gs already exists, skipping..."
fi

# Clone kamailio
echo "Cloning kamailio..."
if [ ! -d "$SOURCES_DIR/kamailio" ]; then
    git clone https://github.com/kamailio/kamailio "$SOURCES_DIR/kamailio"
    cd "$SOURCES_DIR/kamailio"
    git checkout 1f022ac2cf75fe190aa4b4af7b9ca633d3ebd4d2
    cd - > /dev/null
else
    echo "kamailio already exists, skipping..."
fi

# Clone SoapySDR
echo "Cloning SoapySDR..."
if [ ! -d "$SOURCES_DIR/SoapySDR" ]; then
    git clone https://github.com/pothosware/SoapySDR.git "$SOURCES_DIR/SoapySDR"
    cd "$SOURCES_DIR/SoapySDR"
    git checkout 640ac414f7c8bd77a581661d5d99372cd79419f3
    cd - > /dev/null
else
    echo "SoapySDR already exists, skipping..."
fi

# Clone LimeSuite
echo "Cloning LimeSuite..."
if [ ! -d "$SOURCES_DIR/LimeSuite" ]; then
    git clone https://github.com/myriadrf/LimeSuite.git "$SOURCES_DIR/LimeSuite"
    cd "$SOURCES_DIR/LimeSuite"
    git checkout 524cd2e548b11084e6f739b2dfe0f958c2e30354
    cd - > /dev/null
else
    echo "LimeSuite already exists, skipping..."
fi

# Clone bladeRF
echo "Cloning bladeRF..."
if [ ! -d "$SOURCES_DIR/bladeRF" ]; then
    git clone https://github.com/Nuand/bladeRF.git "$SOURCES_DIR/bladeRF"
    cd "$SOURCES_DIR/bladeRF"
    git checkout tags/2024.05
    cd - > /dev/null
else
    echo "bladeRF already exists, skipping..."
fi

# Clone SoapyBladeRF
echo "Cloning SoapyBladeRF..."
if [ ! -d "$SOURCES_DIR/SoapyBladeRF" ]; then
    git clone https://github.com/pothosware/SoapyBladeRF.git "$SOURCES_DIR/SoapyBladeRF"
    cd "$SOURCES_DIR/SoapyBladeRF"
    # Use latest master branch instead of specific commit
    cd - > /dev/null
else
    echo "SoapyBladeRF already exists, skipping..."
fi

# Clone srsGUI
echo "Cloning srsGUI..."
if [ ! -d "$SOURCES_DIR/srsGUI" ]; then
    git clone https://github.com/srsran/srsGUI "$SOURCES_DIR/srsGUI"
    cd "$SOURCES_DIR/srsGUI"
    # Use latest master branch instead of specific commit
    cd - > /dev/null
else
    echo "srsGUI already exists, skipping..."
fi

# Clone srsRAN_4G
echo "Cloning srsRAN_4G..."
if [ ! -d "$SOURCES_DIR/srsRAN_4G" ]; then
    git clone https://github.com/srsran/srsRAN_4G.git "$SOURCES_DIR/srsRAN_4G"
    cd "$SOURCES_DIR/srsRAN_4G"
    # Use latest master branch instead of specific commit
    cd - > /dev/null
else
    echo "srsRAN_4G already exists, skipping..."
fi

# Clone srsRAN_Project
echo "Cloning srsRAN_Project..."
if [ ! -d "$SOURCES_DIR/srsRAN_Project" ]; then
    git clone https://github.com/srsran/srsRAN_Project.git "$SOURCES_DIR/srsRAN_Project"
    cd "$SOURCES_DIR/srsRAN_Project"
    git checkout 55d6f3b80f46d53b23e82ff7b93b65cd01a426e5
    cd - > /dev/null
else
    echo "srsRAN_Project already exists, skipping..."
fi

# Clone OpenSIPS
echo "Cloning OpenSIPS..."
if [ ! -d "$SOURCES_DIR/opensips" ]; then
    git clone https://github.com/OpenSIPS/opensips "$SOURCES_DIR/opensips"
    cd "$SOURCES_DIR/opensips"
    git checkout 03b2b48e99f1c2e1bad9d7bb1b49a9b0ed9d1c3c
    cd - > /dev/null
else
    echo "opensips already exists, skipping..."
fi

# Clone UERANSIM
echo "Cloning UERANSIM..."
if [ ! -d "$SOURCES_DIR/UERANSIM" ]; then
    git clone https://github.com/aligungr/UERANSIM "$SOURCES_DIR/UERANSIM"
    cd "$SOURCES_DIR/UERANSIM"
    git checkout 7dd7f6c2c5f2dd26e4b6e47e74b1b4a5bd88a4a4
    cd - > /dev/null
else
    echo "UERANSIM already exists, skipping..."
fi

# Clone EUPF
echo "Cloning EUPF..."
if [ ! -d "$SOURCES_DIR/eupf" ]; then
    git clone https://github.com/edgecomllc/eupf.git "$SOURCES_DIR/eupf"
    cd "$SOURCES_DIR/eupf"
    git checkout 24e9ee38bb97dff6e1a7026c8bc05e3c61f7b0dc
    cd - > /dev/null
else
    echo "eupf already exists, skipping..."
fi

# Clone PyHSS
echo "Cloning PyHSS..."
if [ ! -d "$SOURCES_DIR/pyhss" ]; then
    git clone https://github.com/nickvsnetworking/pyhss "$SOURCES_DIR/pyhss"
    cd "$SOURCES_DIR/pyhss"
    git checkout 4a9a6eb56fd06b1ef9e3a3bb3e518bb4dc481ab0
    cd - > /dev/null
else
    echo "pyhss already exists, skipping..."
fi

# Clone Asterisk
echo "Cloning Asterisk..."
if [ ! -d "$SOURCES_DIR/asterisk" ]; then
    git clone -b releases/22 https://github.com/asterisk/asterisk.git "$SOURCES_DIR/asterisk"
else
    echo "asterisk already exists, skipping..."
fi

# Clone asterisk-evs
echo "Cloning asterisk-evs..."
if [ ! -d "$SOURCES_DIR/asterisk-evs" ]; then
    git clone https://github.com/NUCLEAR-WAR/asterisk-evs.git "$SOURCES_DIR/asterisk-evs"
else
    echo "asterisk-evs already exists, skipping..."
fi

# Clone osmo-epdg
echo "Cloning osmo-epdg..."
if [ ! -d "$SOURCES_DIR/osmo-epdg" ]; then
    git clone https://gitea.osmocom.org/erlang/osmo-epdg "$SOURCES_DIR/osmo-epdg"
    cd "$SOURCES_DIR/osmo-epdg"
    git checkout c8fd3b8d27b8f6a78e3b21a45b725b88e60334a0
    cd - > /dev/null
else
    echo "osmo-epdg already exists, skipping..."
fi

# Clone strongswan-epdg
echo "Cloning strongswan-epdg..."
if [ ! -d "$SOURCES_DIR/strongswan-epdg" ]; then
    git clone https://github.com/herlesupreeth/strongswan-epdg "$SOURCES_DIR/strongswan-epdg"
    cd "$SOURCES_DIR/strongswan-epdg"
    git checkout eb6a2725e2e73c5aa9da8999a71b8b02be83a0b0
    cd - > /dev/null
else
    echo "strongswan-epdg already exists, skipping..."
fi

# Clone SWu-IKEv2
echo "Cloning SWu-IKEv2..."
if [ ! -d "$SOURCES_DIR/SWu-IKEv2" ]; then
    git clone https://github.com/herlesupreeth/SWu-IKEv2 "$SOURCES_DIR/SWu-IKEv2"
    cd "$SOURCES_DIR/SWu-IKEv2"
    git checkout 6f4e04e0ae75bd90cd8b5ff1c4e83fd4c3ef7c03
    cd - > /dev/null
else
    echo "SWu-IKEv2 already exists, skipping..."
fi

# Clone OpenAirInterface5G
echo "Cloning OpenAirInterface5G..."
if [ ! -d "$SOURCES_DIR/openairinterface5g" ]; then
    git clone https://gitlab.eurecom.fr/oai/openairinterface5g.git "$SOURCES_DIR/openairinterface5g"
    cd "$SOURCES_DIR/openairinterface5g"
    git checkout v2.3.0
    cd - > /dev/null
else
    echo "OpenAirInterface5G already exists, skipping..."
fi

echo "All source codes have been cloned successfully!"
echo "Source codes are located in: $SOURCES_DIR"
echo ""
echo "You can now modify the source codes as needed and build the Docker images."
echo "To build the Docker images, run:"
echo "  ./build_from_source.sh"
