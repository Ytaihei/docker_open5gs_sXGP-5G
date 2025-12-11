#!/bin/bash
# 総合動作確認スクリプト - 実UEなしバージョン

echo "================================================================"
echo "S1N2 & AMF Implementation Verification (No Real UE Required)"
echo "================================================================"
echo ""
echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# カラー定義
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

pass_count=0
warn_count=0
fail_count=0

check_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_result="$3"

    echo -n "[$test_name] "

    if eval "$test_command"; then
        echo -e "${GREEN}PASS${NC} - $expected_result"
        ((pass_count++))
        return 0
    else
        echo -e "${RED}FAIL${NC} - $expected_result not found"
        ((fail_count++))
        return 1
    fi
}

check_warn() {
    local test_name="$1"
    local test_command="$2"
    local expected_result="$3"

    echo -n "[$test_name] "

    if eval "$test_command"; then
        echo -e "${GREEN}PASS${NC} - $expected_result"
        ((pass_count++))
        return 0
    else
        echo -e "${YELLOW}WARN${NC} - Cannot verify without real UE"
        ((warn_count++))
        return 1
    fi
}

echo "=== 1. Source Code Verification ==="
check_test "1.1 s1n2 UEContextRequest flag" \
    "grep -q 'ue_context_requested = true' /home/taihei/docker_open5gs_sXGP-5G/sXGP-5G/src/s1n2_converter.c" \
    "Flag set to true"

check_test "1.2 NGAP Builder IE implementation" \
    "grep -q 'NGAP_UEContextRequest_requested' /home/taihei/docker_open5gs_sXGP-5G/sXGP-5G/src/ngap/ngap_builder.c" \
    "IE addition code present"

check_test "1.3 AMF ICS gate check logging" \
    "grep -q 'ICS gate check' /home/taihei/docker_open5gs_sXGP-5G/sources/open5gs/src/amf/nas-path.c" \
    "Diagnostic logging implemented"

echo ""
echo "=== 2. Build & Deployment Verification ==="

check_test "2.1 s1n2 container running" \
    "docker inspect s1n2 --format='{{.State.Status}}' 2>/dev/null | grep -q 'running'" \
    "Container is running"

check_test "2.2 s1n2 built today" \
    "[ \"$(docker inspect s1n2 --format='{{.Created}}' | cut -d'T' -f1)\" = \"$(date '+%Y-%m-%d')\" ]" \
    "Container built with latest code"

check_test "2.3 AMF container running" \
    "docker inspect amf-s1n2 --format='{{.State.Status}}' 2>/dev/null | grep -q 'running'" \
    "Container is running"

check_test "2.4 AMF built today" \
    "[ \"$(docker inspect amf-s1n2 --format='{{.Created}}' | cut -d'T' -f1)\" = \"$(date '+%Y-%m-%d')\" ]" \
    "Container built with latest code"

echo ""
echo "=== 3. Runtime Feature Verification ==="

check_test "3.1 s1n2 Handover block enabled" \
    "docker logs s1n2 2>&1 | grep -q 'Handover block feature ENABLED'" \
    "Phase 18.0 features active"

check_test "3.2 s1n2 NGAP send wrapper" \
    "docker logs s1n2 2>&1 | grep -q '\[NGAP\]\[Send\]'" \
    "NGAP instrumentation active"

echo ""
echo "=== 4. Code Flow Verification (Static Analysis) ==="

check_test "4.1 Variable initialization" \
    "grep -A 2 'bool ue_context_requested = true' /home/taihei/docker_open5gs_sXGP-5G/sXGP-5G/src/s1n2_converter.c | grep -q 'printf.*UEContextRequest'" \
    "Logging statement present"

check_test "4.2 Parameter passing" \
    "grep 'build_initial_ue_message.*ue_context_requested' /home/taihei/docker_open5gs_sXGP-5G/sXGP-5G/src/s1n2_converter.c | wc -l | grep -q '[1-9]'" \
    "Parameter passed to builder"

check_test "4.3 Conditional IE addition" \
    "grep -A 2 'if (ue_context_requested)' /home/taihei/docker_open5gs_sXGP-5G/sXGP-5G/src/ngap/ngap_builder.c | grep -q 'ASN_SEQUENCE_ADD'" \
    "IE added to sequence"

echo ""
echo "=== 5. Expected Runtime Behavior (Requires Real UE) ==="

check_warn "5.1 InitialUEMessage log" \
    "docker logs s1n2 2>&1 | grep -q 'UEContextRequest IE will be included'" \
    "Info log when processing InitialUEMessage"

check_warn "5.2 AMF ICS gate check log" \
    "docker logs amf-s1n2 2>&1 | grep -q 'ICS gate check'" \
    "AMF logs ICS decision variables"

check_warn "5.3 AMF ICS selection log" \
    "docker logs amf-s1n2 2>&1 | grep -q 'InitialContextSetupRequest selected'" \
    "AMF decides to send ICS"

echo ""
echo "================================================================"
echo "Test Summary"
echo "================================================================"
echo -e "${GREEN}PASS: $pass_count${NC}"
echo -e "${YELLOW}WARN: $warn_count${NC} (Requires real UE to verify)"
echo -e "${RED}FAIL: $fail_count${NC}"
echo ""

if [ $fail_count -eq 0 ]; then
    echo -e "${GREEN}✅ All critical checks passed!${NC}"
    echo ""
    echo "Implementation Status: READY FOR TESTING"
    echo ""
    echo "Next Steps:"
    echo "  1. Connect real UE and eNB"
    echo "  2. Capture traffic: tcpdump -i br-sXGP-5G -w test.pcap"
    echo "  3. Check logs:"
    echo "     docker logs s1n2 | grep UEContextRequest"
    echo "     docker logs amf-s1n2 | grep 'ICS gate check'"
    echo "  4. Analyze pcap:"
    echo "     tshark -r test.pcap -Y 'ngap.procedureCode == 15' -V | grep UEContextRequest"
    echo "     tshark -r test.pcap -Y 'ngap.procedureCode == 14' -T fields -e frame.number"
    echo ""
else
    echo -e "${RED}❌ Some checks failed. Please review above.${NC}"
    echo ""
fi

exit $fail_count
