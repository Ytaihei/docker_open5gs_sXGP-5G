#!/bin/bash
# analyze_5g_flow.sh - Automated 5G Registration Flow Analysis

PCAP_FILE="$1"

if [ -z "$PCAP_FILE" ]; then
    echo "Usage: $0 <pcap_file>"
    exit 1
fi

if [ ! -f "$PCAP_FILE" ]; then
    echo "Error: File not found: $PCAP_FILE"
    exit 1
fi

echo "=========================================="
echo "  5G/4G Registration Flow Analysis"
echo "=========================================="
echo "File: $PCAP_FILE"
echo ""

# 1. InitialUEMessage (Registration Request)
echo "【1】InitialUEMessage (Registration Request):"
# Check both S1AP (4G) and NGAP (5G)
INITIAL_UE_NGAP=$(tshark -r "$PCAP_FILE" -Y "ngap.procedureCode == 15" 2>/dev/null | wc -l)
INITIAL_UE_S1AP=$(tshark -r "$PCAP_FILE" -Y "s1ap.procedureCode == 12" 2>/dev/null | wc -l)
INITIAL_UE=$((INITIAL_UE_NGAP + INITIAL_UE_S1AP))
if [ "$INITIAL_UE" -gt 0 ]; then
    echo "  ✓ Found $INITIAL_UE InitialUEMessage(s) (NGAP: $INITIAL_UE_NGAP, S1AP: $INITIAL_UE_S1AP)"
    if [ "$INITIAL_UE_NGAP" -gt 0 ]; then
        tshark -r "$PCAP_FILE" -Y "ngap.procedureCode == 15" -T fields -e frame.number -e frame.time_relative -e ip.src -e ip.dst 2>/dev/null | head -5 | while read line; do
            echo "    Frame (NGAP): $line"
        done
    fi
    if [ "$INITIAL_UE_S1AP" -gt 0 ]; then
        tshark -r "$PCAP_FILE" -Y "s1ap.procedureCode == 12" -T fields -e frame.number -e frame.time_relative -e ip.src -e ip.dst 2>/dev/null | head -5 | while read line; do
            echo "    Frame (S1AP): $line"
        done
    fi
else
    echo "  ✗ No InitialUEMessage found"
fi
echo ""

# 2. Authentication Request/Response
echo "【2】Authentication Request/Response:"
# Check both 4G (nas-eps) and 5G (nas-5gs)
# For 5G, check NGAP DownlinkNASTransport/UplinkNASTransport with Info column
AUTH_REQ_5G=$(tshark -r "$PCAP_FILE" -Y "ngap.procedureCode == 4" -T fields -e _ws.col.Info 2>/dev/null | grep -i "authentication request" | wc -l)
AUTH_RES_5G=$(tshark -r "$PCAP_FILE" -Y "ngap.procedureCode == 46" -T fields -e _ws.col.Info 2>/dev/null | grep -i "authentication response" | wc -l)
AUTH_REQ_4G=$(tshark -r "$PCAP_FILE" -Y "s1ap.procedureCode == 11" -T fields -e _ws.col.Info 2>/dev/null | grep -i "authentication request" | wc -l)
AUTH_RES_4G=$(tshark -r "$PCAP_FILE" -Y "s1ap.procedureCode == 13" -T fields -e _ws.col.Info 2>/dev/null | grep -i "authentication response" | wc -l)
AUTH_REQ=$((AUTH_REQ_5G + AUTH_REQ_4G))
AUTH_RES=$((AUTH_RES_5G + AUTH_RES_4G))
echo "  Authentication Request: $AUTH_REQ (5G: $AUTH_REQ_5G, 4G: $AUTH_REQ_4G)"
echo "  Authentication Response: $AUTH_RES (5G: $AUTH_RES_5G, 4G: $AUTH_RES_4G)"
echo ""

# 3. Security Mode Command/Complete
echo "【3】Security Mode Command/Complete:"
# Check both 4G (nas-eps) and 5G (nas-5gs)
# For 5G, check NGAP messages with Info column containing security mode
SMC_5G=$(tshark -r "$PCAP_FILE" -Y "ngap.procedureCode == 4" -T fields -e _ws.col.Info 2>/dev/null | grep -i "security mode command" | wc -l)
SM_COMPLETE_5G=$(tshark -r "$PCAP_FILE" -Y "ngap.procedureCode == 46" -T fields -e frame.number -e _ws.col.Info 2>/dev/null | grep -i "security mode complete" | wc -l)
SMC_4G=$(tshark -r "$PCAP_FILE" -Y "s1ap.procedureCode == 11" -T fields -e _ws.col.Info 2>/dev/null | grep -i "security mode command" | wc -l)
SM_COMPLETE_4G=$(tshark -r "$PCAP_FILE" -Y "s1ap.procedureCode == 13" -T fields -e _ws.col.Info 2>/dev/null | grep -i "security mode complete" | wc -l)

# For encrypted Security Mode Complete, check UplinkNASTransport without specific Info (encrypted)
# Frame 75 shows "UplinkNASTransport" only, meaning it's encrypted
ENCRYPTED_UPLINK_5G=$(tshark -r "$PCAP_FILE" -Y "ngap.procedureCode == 46" -T fields -e frame.number -e _ws.col.Info 2>/dev/null | grep "UplinkNASTransport$" | wc -l)
if [ "$ENCRYPTED_UPLINK_5G" -gt 0 ] && [ "$SM_COMPLETE_5G" -eq 0 ]; then
    # Likely encrypted Security Mode Complete
    SM_COMPLETE_5G=$ENCRYPTED_UPLINK_5G
fi

SMC=$((SMC_5G + SMC_4G))
SM_COMPLETE=$((SM_COMPLETE_5G + SM_COMPLETE_4G))
echo "  Security Mode Command: $SMC (5G: $SMC_5G, 4G: $SMC_4G)"
echo "  Security Mode Complete: $SM_COMPLETE (5G: $SM_COMPLETE_5G, 4G: $SM_COMPLETE_4G)"

if [ "$SM_COMPLETE" -gt 0 ]; then
    echo "  Checking for NAS Message Container (piggybacking)..."
    # For piggybacking, the Registration Request should be in the Security Mode Complete
    # Check if any UplinkNASTransport after Security Mode Complete contains Registration Request
    NAS_CONT_5G=$(tshark -r "$PCAP_FILE" -Y "ngap.procedureCode == 46" -T fields -e _ws.col.Info 2>/dev/null | grep -i "registration request" | wc -l)
    NAS_CONT_4G=$(tshark -r "$PCAP_FILE" -Y "s1ap.procedureCode == 13" -T fields -e _ws.col.Info 2>/dev/null | grep -i "attach request" | wc -l)
    NAS_CONT=$((NAS_CONT_5G + NAS_CONT_4G))
    if [ "$NAS_CONT" -gt 0 ]; then
        echo "  ★★★ NAS Message Container FOUND! (Registration Request piggybacked) ★★★"
        echo "      (5G: $NAS_CONT_5G, 4G: $NAS_CONT_4G)"
    else
        echo "  ✗ No NAS Message Container found (Registration Request NOT piggybacked)"
        echo "      Note: Security Mode Complete may be encrypted (cannot verify piggybacking)"
    fi
fi
echo ""

# 4. InitialContextSetupRequest (Registration Accept)
echo "【4】InitialContextSetupRequest (Registration Accept):"
# Check both NGAP (5G) and S1AP (4G)
INITIAL_CTX_NGAP=$(tshark -r "$PCAP_FILE" -Y "ngap.procedureCode == 14" 2>/dev/null | wc -l)
INITIAL_CTX_S1AP=$(tshark -r "$PCAP_FILE" -Y "s1ap.procedureCode == 9" 2>/dev/null | wc -l)
INITIAL_CTX=$((INITIAL_CTX_NGAP + INITIAL_CTX_S1AP))
if [ "$INITIAL_CTX" -gt 0 ]; then
    echo "  ✓✓✓ SUCCESS! Found $INITIAL_CTX InitialContextSetupRequest(s)"
    echo "      (NGAP: $INITIAL_CTX_NGAP, S1AP: $INITIAL_CTX_S1AP)"
    echo "  This means AMF/MME accepted the Registration/Attach Request!"
    if [ "$INITIAL_CTX_NGAP" -gt 0 ]; then
        tshark -r "$PCAP_FILE" -Y "ngap.procedureCode == 14" -T fields -e frame.number -e frame.time_relative 2>/dev/null | head -3 | while read line; do
            echo "    Frame (NGAP): $line"
        done
    fi
    if [ "$INITIAL_CTX_S1AP" -gt 0 ]; then
        tshark -r "$PCAP_FILE" -Y "s1ap.procedureCode == 9" -T fields -e frame.number -e frame.time_relative 2>/dev/null | head -3 | while read line; do
            echo "    Frame (S1AP): $line"
        done
    fi
else
    echo "  ✗ No InitialContextSetupRequest found"
    echo "  This means AMF/MME has NOT accepted the Registration/Attach Request yet"
fi
echo ""

# 5. Error Messages
echo "【5】Error Messages:"
ERROR_IND_NGAP=$(tshark -r "$PCAP_FILE" -Y "ngap.procedureCode == 15" 2>/dev/null | wc -l)
ERROR_IND_S1AP=$(tshark -r "$PCAP_FILE" -Y "s1ap.procedureCode == 15" 2>/dev/null | wc -l)
ERROR_IND=$((ERROR_IND_NGAP + ERROR_IND_S1AP))
if [ "$ERROR_IND" -gt 0 ]; then
    echo "  ✗ Found $ERROR_IND ErrorIndication(s) (NGAP: $ERROR_IND_NGAP, S1AP: $ERROR_IND_S1AP)"
    if [ "$ERROR_IND_NGAP" -gt 0 ]; then
        tshark -r "$PCAP_FILE" -Y "ngap.procedureCode == 15" -T fields -e frame.number -e ngap.cause 2>/dev/null | head -5
    fi
    if [ "$ERROR_IND_S1AP" -gt 0 ]; then
        tshark -r "$PCAP_FILE" -Y "s1ap.procedureCode == 15" -T fields -e frame.number -e s1ap.cause 2>/dev/null | head -5
    fi
else
    echo "  ✓ No error messages"
fi
echo ""

# 6. Summary
echo "=========================================="
echo "  Summary"
echo "=========================================="
if [ "$INITIAL_CTX" -gt 0 ]; then
    echo "Result: ✓✓✓ TEST PASSED ✓✓✓"
    echo "The Registration/Attach procedure completed successfully!"
    echo "AMF/MME sent InitialContextSetupRequest (Registration/Attach Accept)"
elif [ "$SM_COMPLETE" -gt 0 ] && [ "$NAS_CONT" -eq 0 ]; then
    echo "Result: ✗ TEST FAILED (Missing piggybacking)"
    echo "Security Mode Complete was sent, but WITHOUT piggybacked Registration/Attach Request"
    echo "This is the bug we're trying to fix!"
elif [ "$SMC" -gt 0 ] && [ "$SM_COMPLETE" -eq 0 ]; then
    echo "Result: ? TEST INCONCLUSIVE"
    echo "Security Mode Command was sent, but no response from UE yet"
else
    echo "Result: ? TEST INCONCLUSIVE"
    echo "Insufficient data to determine registration status"
fi
echo "=========================================="
