#!/bin/bash
# Setup script for 4G network deployment
# This script ensures eno1 is connected to the internal bridge

set -e

BRIDGE_NAME="br-open5gs_4g"
PHYSICAL_IF="eno1"

echo "=== 4G Network Setup ==="

# Check if bridge exists
if ! docker network inspect "$BRIDGE_NAME" >/dev/null 2>&1; then
    echo "Error: Bridge network '$BRIDGE_NAME' not found."
    echo "Please run 'docker compose -f 4g-data-only-deploy.yaml up' first."
    exit 1
fi

# Check if physical interface exists
if ! ip link show "$PHYSICAL_IF" >/dev/null 2>&1; then
    echo "Error: Physical interface '$PHYSICAL_IF' not found."
    exit 1
fi

# Connect physical interface to bridge if not already connected
CURRENT_MASTER=$(ip -o link show "$PHYSICAL_IF" | grep -oP 'master \K\S+' || echo "none")

if [ "$CURRENT_MASTER" = "$BRIDGE_NAME" ]; then
    echo "✓ $PHYSICAL_IF is already connected to $BRIDGE_NAME"
else
    echo "Connecting $PHYSICAL_IF to $BRIDGE_NAME..."
    sudo ip link set "$PHYSICAL_IF" master "$BRIDGE_NAME"
    echo "✓ $PHYSICAL_IF connected to $BRIDGE_NAME"
fi

# Verify connectivity
BRIDGE_IP=$(ip -4 addr show "$BRIDGE_NAME" | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
echo ""
echo "Bridge IP: $BRIDGE_IP"
echo ""

echo "Testing connectivity to eNB..."
if ping -c 2 -W 2 -I "$BRIDGE_NAME" 192.168.10.110 >/dev/null 2>&1; then
    echo "✓ eNB WAN (192.168.10.110) is reachable"
else
    echo "✗ eNB WAN (192.168.10.110) is NOT reachable"
fi

if ping -c 2 -W 2 -I "$BRIDGE_NAME" 192.168.10.111 >/dev/null 2>&1; then
    echo "✓ eNB WebUI (192.168.10.111) is reachable"
else
    echo "✗ eNB WebUI (192.168.10.111) is NOT reachable"
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "To access eNB WebUI from your local machine:"
echo "  ssh -p 2002 -L 8443:192.168.10.111:443 taihei@<HOST_IP>"
echo "  Then open: https://localhost:8443"
echo ""
