#!/bin/bash
# S1N2 UEContextRequest 実装確認スクリプト
# 実UEなしで、ソースコードとログから実装状態を確認

echo "========================================="
echo "S1N2 UEContextRequest Implementation Check"
echo "========================================="
echo ""

echo "[1] Checking s1n2 source code..."
echo "---"
if grep -q "ue_context_requested = true" /home/taihei/docker_open5gs_sXGP-5G/sXGP-5G/src/s1n2_converter.c; then
    echo "✅ Source code: ue_context_requested flag is set to true"
    grep -A 2 "ue_context_requested = true" /home/taihei/docker_open5gs_sXGP-5G/sXGP-5G/src/s1n2_converter.c | head -3
else
    echo "❌ Source code: ue_context_requested flag NOT found"
fi
echo ""

echo "[2] Checking s1n2 NGAP builder..."
echo "---"
if grep -q "NGAP_UEContextRequest_requested" /home/taihei/docker_open5gs_sXGP-5G/sXGP-5G/src/ngap/ngap_builder.c; then
    echo "✅ NGAP builder: UEContextRequest IE implementation found"
    grep -B 2 -A 2 "NGAP_UEContextRequest_requested" /home/taihei/docker_open5gs_sXGP-5G/sXGP-5G/src/ngap/ngap_builder.c | head -7
else
    echo "❌ NGAP builder: UEContextRequest IE NOT implemented"
fi
echo ""

echo "[3] Checking AMF source code..."
echo "---"
if grep -q "ICS gate check" /home/taihei/docker_open5gs_sXGP-5G/sources/open5gs/src/amf/nas-path.c; then
    echo "✅ AMF source: ICS gate check logging implemented"
    grep "ICS gate check" /home/taihei/docker_open5gs_sXGP-5G/sources/open5gs/src/amf/nas-path.c | head -1
else
    echo "❌ AMF source: ICS gate check logging NOT found"
fi
echo ""

echo "[4] Checking s1n2 container status..."
echo "---"
CONTAINER_STATUS=$(docker inspect s1n2 --format='{{.State.Status}}' 2>/dev/null)
if [ "$CONTAINER_STATUS" = "running" ]; then
    echo "✅ s1n2 container: Running"
    CONTAINER_CREATED=$(docker inspect s1n2 --format='{{.Created}}' | cut -d'T' -f1)
    echo "   Built on: $CONTAINER_CREATED"
else
    echo "❌ s1n2 container: Not running ($CONTAINER_STATUS)"
fi
echo ""

echo "[5] Checking AMF container status..."
echo "---"
AMF_STATUS=$(docker inspect amf-s1n2 --format='{{.State.Status}}' 2>/dev/null)
if [ "$AMF_STATUS" = "running" ]; then
    echo "✅ AMF container: Running"
    AMF_CREATED=$(docker inspect amf-s1n2 --format='{{.Created}}' | cut -d'T' -f1)
    echo "   Built on: $AMF_CREATED"
else
    echo "❌ AMF container: Not running ($AMF_STATUS)"
fi
echo ""

echo "[6] Checking s1n2 startup logs..."
echo "---"
if docker logs s1n2 2>&1 | grep -q "Handover block feature ENABLED"; then
    echo "✅ s1n2 logs: Phase 18.0 features active"
    docker logs s1n2 2>&1 | grep "Handover block feature" | tail -1
else
    echo "⚠️  s1n2 logs: No Phase 18.0 feature confirmation"
fi
echo ""

echo "[7] Source code modification dates..."
echo "---"
echo "s1n2_converter.c: $(stat -c '%y' /home/taihei/docker_open5gs_sXGP-5G/sXGP-5G/src/s1n2_converter.c | cut -d' ' -f1)"
echo "ngap_builder.c:   $(stat -c '%y' /home/taihei/docker_open5gs_sXGP-5G/sXGP-5G/src/ngap/ngap_builder.c | cut -d' ' -f1)"
echo "AMF nas-path.c:   $(stat -c '%y' /home/taihei/docker_open5gs_sXGP-5G/sources/open5gs/src/amf/nas-path.c | cut -d' ' -f1)"
echo ""

echo "========================================="
echo "Summary"
echo "========================================="
echo ""
echo "✅ = Implemented and ready"
echo "⚠️  = Implemented but needs verification"
echo "❌ = Not implemented or error"
echo ""
echo "To verify with real UE connection:"
echo "  1. Connect UE and eNB"
echo "  2. Check s1n2 log: docker logs s1n2 | grep UEContextRequest"
echo "  3. Check AMF log:  docker logs amf-s1n2 | grep 'ICS gate check'"
echo "  4. Capture pcap and analyze with tshark"
echo ""
