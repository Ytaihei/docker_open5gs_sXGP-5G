#!/bin/bash

# Create a custom bridge with fixed name for tcpdump
# This script creates br-open5gs_4g bridge manually

set -e

BRIDGE_NAME="br-open5gs_4g"
NETWORK_SUBNET="172.22.0.0/24"
BRIDGE_IP="172.22.0.1/24"

echo "Creating custom bridge: $BRIDGE_NAME"

# Check if bridge already exists
if ip link show "$BRIDGE_NAME" >/dev/null 2>&1; then
    echo "Bridge $BRIDGE_NAME already exists"
else
    # Create bridge
    sudo ip link add name "$BRIDGE_NAME" type bridge
    sudo ip addr add "$BRIDGE_IP" dev "$BRIDGE_NAME"
    sudo ip link set dev "$BRIDGE_NAME" up
    echo "Bridge $BRIDGE_NAME created successfully"
fi

# Create Docker network using the existing bridge
if docker network inspect "$BRIDGE_NAME" >/dev/null 2>&1; then
    echo "Docker network $BRIDGE_NAME already exists"
else
    docker network create \
        --driver bridge \
        --subnet="$NETWORK_SUBNET" \
        --gateway="172.22.0.1" \
        --opt com.docker.network.bridge.name="$BRIDGE_NAME" \
        "$BRIDGE_NAME"
    echo "Docker network $BRIDGE_NAME created"
fi

echo "You can now use: sudo tcpdump -i $BRIDGE_NAME"
