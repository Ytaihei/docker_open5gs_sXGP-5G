#!/bin/bash
# 4G Network Setup Script
# Automatically called before docker compose up

set -e

BRIDGE_NAME="br-open5gs_4g"
BRIDGE_IP="172.24.1.1/16"
OTHER_BRIDGE="br-sXGP-5G"

echo "=== 4G Network Setup ==="

# 1. sXGP-5G構成のブリッジからIPアドレスを削除（競合回避）
if ip addr show ${OTHER_BRIDGE} 2>/dev/null | grep -q "172.24"; then
    echo "1. Cleaning up sXGP-5G bridge IP addresses..."
    sudo ip addr flush dev ${OTHER_BRIDGE} 2>/dev/null || true
    echo "   ✓ sXGP-5G bridge cleaned"
else
    echo "1. sXGP-5G bridge already clean"
fi

# 2. eno1を4Gブリッジに接続
echo "2. Connecting eno1 to ${BRIDGE_NAME}..."
if ! ip link show eno1 2>/dev/null | grep -q "master ${BRIDGE_NAME}"; then
    # 既存のmaster接続を解除
    sudo ip link set eno1 nomaster 2>/dev/null || true
    # 新しいブリッジに接続
    sudo ip link set eno1 master ${BRIDGE_NAME}
    echo "   ✓ eno1 connected to ${BRIDGE_NAME}"
else
    echo "   ✓ eno1 already connected"
fi

# 3. ブリッジのIPアドレスを修正（Dockerが/24で設定するため）
echo "3. Fixing bridge IP address..."
if ip addr show ${BRIDGE_NAME} 2>/dev/null | grep -q "${BRIDGE_IP%/*}/24"; then
    sudo ip addr del ${BRIDGE_IP%/*}/24 dev ${BRIDGE_NAME}
    echo "   ✓ Removed /24 address"
fi

if ! ip addr show ${BRIDGE_NAME} 2>/dev/null | grep -q "${BRIDGE_IP}"; then
    sudo ip addr add ${BRIDGE_IP} dev ${BRIDGE_NAME}
    echo "   ✓ Added ${BRIDGE_IP}"
else
    echo "   ✓ /16 address already configured"
fi

# 4. 疎通確認
echo "4. Testing connectivity..."
sleep 1
if ping -c 1 -W 2 172.24.0.111 > /dev/null 2>&1; then
    echo "   ✓ eNB (172.24.0.111) reachable"
else
    echo "   ⚠ eNB (172.24.0.111) NOT reachable - check eNB power/cable"
fi

if ping -c 1 -W 2 172.24.1.40 > /dev/null 2>&1; then
    echo "   ✓ MME (172.24.1.40) reachable"
else
    echo "   ⚠ MME (172.24.1.40) NOT reachable - check docker containers"
fi

echo ""
echo "=== 4G Network Ready ==="
echo "You can now access eNB WebUI via SSH port forwarding:"
echo "  ssh -p 2002 -L 8443:172.24.0.111:443 taihei-nuc-ubuntu"
echo "Then open: https://localhost:8443"
