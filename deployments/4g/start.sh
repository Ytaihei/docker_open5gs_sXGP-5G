#!/bin/bash
# 4G構成の起動スクリプト

cd "$(dirname "$0")"

BRIDGE_NAME="br-open5gs_4g"
BRIDGE_IP="172.24.1.1/16"
OTHER_BRIDGE="br-sXGP-5G"

echo "========================================="
echo "  Starting 4G Configuration"
echo "========================================="
echo ""

# sXGP-5G構成を停止（競合回避）
echo "Stopping sXGP-5G configuration if running..."
cd ../../sXGP-5G && docker compose down 2>/dev/null || true
cd - > /dev/null
echo ""

echo "=== Pre-Setup ==="

# sXGP-5G構成のブリッジからIPアドレスを削除（競合回避）
if ip addr show ${OTHER_BRIDGE} 2>/dev/null | grep -q "172.24"; then
    echo "Cleaning up sXGP-5G bridge..."
    sudo ip addr flush dev ${OTHER_BRIDGE} 2>/dev/null || true
    echo "✓ Done"
else
    echo "✓ sXGP-5G bridge already clean"
fi

echo ""
echo "Starting Docker containers..."
docker compose up -d --force-recreate

echo ""
echo "=== Network Setup ==="

# Docker起動後に実行
sleep 2

# 1. eno1を4Gブリッジに接続
echo "1. Connecting eno1 to ${BRIDGE_NAME}..."
if ! ip link show eno1 2>/dev/null | grep -q "master ${BRIDGE_NAME}"; then
    # NetworkManager経由で永続的に設定を変更
    if nmcli connection show "bridge-slave-eno1" >/dev/null 2>&1; then
        echo "   Configuring via NetworkManager..."
        sudo nmcli connection modify "bridge-slave-eno1" connection.master "${BRIDGE_NAME}"
        sudo nmcli connection down "bridge-slave-eno1" 2>/dev/null || true
        sudo nmcli connection up "bridge-slave-eno1"
        echo "   ✓ eno1 connected (permanent)"
    else
        # NetworkManager未使用の場合は直接設定
        sudo ip link set eno1 nomaster 2>/dev/null || true
        sudo ip link set eno1 master ${BRIDGE_NAME}
        echo "   ✓ eno1 connected"
    fi
else
    echo "   ✓ eno1 already connected"
fi

# 2. ブリッジのIPアドレスを修正（Dockerが/24で設定するため）
echo "2. Fixing bridge IP..."
if ip addr show ${BRIDGE_NAME} 2>/dev/null | grep -q "${BRIDGE_IP%/*}/24"; then
    sudo ip addr del ${BRIDGE_IP%/*}/24 dev ${BRIDGE_NAME}
    sudo ip addr add ${BRIDGE_IP} dev ${BRIDGE_NAME}
    echo "   ✓ Changed to /16"
elif ! ip addr show ${BRIDGE_NAME} 2>/dev/null | grep -q "${BRIDGE_IP}"; then
    sudo ip addr add ${BRIDGE_IP} dev ${BRIDGE_NAME}
    echo "   ✓ Added ${BRIDGE_IP}"
else
    echo "   ✓ /16 address configured"
fi

# 3. 疎通確認
echo "3. Testing connectivity..."
sleep 1
if ping -c 1 -W 2 172.24.0.111 > /dev/null 2>&1; then
    echo "   ✓ eNB (172.24.0.111) reachable"
else
    echo "   ⚠ eNB (172.24.0.111) NOT reachable"
fi

if ping -c 1 -W 2 172.24.1.40 > /dev/null 2>&1; then
    echo "   ✓ MME (172.24.1.40) reachable"
else
    echo "   ⚠ MME (172.24.1.40) NOT reachable"
fi

echo ""
echo "========================================="
echo "  4G Configuration Started"
echo "========================================="
echo ""
echo "Service URLs:"
echo "  - WebUI: http://$(hostname -I | awk '{print $1}'):9998"
echo "  - eNB WebUI: https://localhost:8443 (via SSH tunnel)"
echo ""
echo "Check status: docker ps"
echo "View logs: docker logs -f mme-4g"
