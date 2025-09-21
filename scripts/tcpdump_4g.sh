#!/bin/bash

# tcpdump wrapper script for br-open5gs_4g network
# Usage: ./tcpdump_4g.sh [tcpdump options]

NETWORK_NAME="br-open5gs_4g"

# Get the actual bridge interface name
BRIDGE_NAME=$(docker network inspect $NETWORK_NAME --format='{{.Id}}' 2>/dev/null | cut -c1-12)

if [ -z "$BRIDGE_NAME" ]; then
    echo "Error: Docker network '$NETWORK_NAME' not found."
    echo "Please make sure the 4G deployment is running."
    exit 1
fi

INTERFACE="br-$BRIDGE_NAME"

# Check if interface exists
if ! ip link show "$INTERFACE" >/dev/null 2>&1; then
    echo "Error: Bridge interface '$INTERFACE' not found."
    exit 1
fi

echo "Using bridge interface: $INTERFACE"
echo "Running: sudo tcpdump -i $INTERFACE $@"
echo ""

# Execute tcpdump with the correct interface
sudo tcpdump -i "$INTERFACE" "$@"
