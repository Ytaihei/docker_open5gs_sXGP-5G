#!/usr/bin/env python3
"""
S1N2 UEContextRequest Test Script
過去のpcapからS1AP InitialUEMessageを抽出してs1n2に送信し、
生成されるNGAPメッセージを確認する
"""

import socket
import subprocess
import time
import sys

def extract_s1ap_initial_ue_message(pcap_file):
    """pcapからS1AP InitialUEMessageを抽出"""
    print(f"[INFO] Extracting S1AP InitialUEMessage from {pcap_file}...")

    # tsharkでS1AP InitialUEMessage (procedureCode=12) を抽出
    cmd = [
        'tshark',
        '-r', pcap_file,
        '-Y', 's1ap.procedureCode == 12',
        '-T', 'fields',
        '-e', 'frame.number',
        '-e', 'sctp.payload_proto_id',
        '-e', 's1ap'
    ]

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        lines = result.stdout.strip().split('\n')

        if not lines or not lines[0]:
            print("[ERROR] No S1AP InitialUEMessage found in pcap")
            return None

        # 最初のInitialUEMessageを使用
        frame_num, ppid, s1ap_hex = lines[0].split('\t')
        print(f"[INFO] Found InitialUEMessage in frame {frame_num}")
        print(f"[INFO] PPID: {ppid}")
        print(f"[INFO] S1AP hex length: {len(s1ap_hex)} characters")

        # hexをbytesに変換
        s1ap_bytes = bytes.fromhex(s1ap_hex.replace(':', ''))
        return s1ap_bytes

    except subprocess.CalledProcessError as e:
        print(f"[ERROR] tshark failed: {e}")
        return None
    except Exception as e:
        print(f"[ERROR] Failed to extract: {e}")
        return None

def send_to_s1n2(s1ap_message, host='172.24.0.30', port=36412):
    """s1n2にS1APメッセージを送信（SCTP）"""
    print(f"[INFO] Connecting to s1n2 at {host}:{port}...")

    # 注意: PythonのsocketはデフォルトでSCTPをサポートしていない
    # 実際のテストにはsctptoolsやnetcat-sctpが必要
    print("[WARN] Direct SCTP send from Python requires sctp module")
    print("[INFO] Saving message to file for manual send...")

    with open('/tmp/s1ap_initial_ue_message.bin', 'wb') as f:
        f.write(s1ap_message)

    print(f"[INFO] S1AP message saved to /tmp/s1ap_initial_ue_message.bin ({len(s1ap_message)} bytes)")
    print("\n[NEXT STEP] Send manually with:")
    print(f"  docker exec s1n2 nc -u {host} {port} < /tmp/s1ap_initial_ue_message.bin")
    print("  OR")
    print("  Use sctp_test or socat for SCTP")

    return True

def analyze_ngap_output():
    """s1n2のログからNGAP出力を解析"""
    print("\n[INFO] Checking s1n2 logs for NGAP output...")

    cmd = ['docker', 'logs', '--tail', '50', 's1n2']
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        logs = result.stdout

        # UEContextRequestに関するログを探す
        for line in logs.split('\n'):
            if 'UEContextRequest' in line or 'InitialUEMessage' in line:
                print(f"  {line}")

        # HEXダンプを探す
        if '[HEX]' in logs or 'InitialUEMessage(dynamic)' in logs:
            print("\n[SUCCESS] Found NGAP InitialUEMessage in logs!")
            return True
        else:
            print("\n[WARN] No NGAP InitialUEMessage found yet")
            return False

    except Exception as e:
        print(f"[ERROR] Failed to check logs: {e}")
        return False

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 test_s1n2_uecontextrequest.py <pcap_file>")
        print("Example: python3 test_s1n2_uecontextrequest.py log/20251108_10.pcap")
        sys.exit(1)

    pcap_file = sys.argv[1]

    print("=" * 70)
    print("S1N2 UEContextRequest Test")
    print("=" * 70)

    # Step 1: pcapからS1APメッセージを抽出
    s1ap_msg = extract_s1ap_initial_ue_message(pcap_file)
    if not s1ap_msg:
        print("[FAIL] Could not extract S1AP message")
        sys.exit(1)

    # Step 2: s1n2に送信（ファイル保存のみ）
    if not send_to_s1n2(s1ap_msg):
        print("[FAIL] Could not prepare message for sending")
        sys.exit(1)

    print("\n" + "=" * 70)
    print("MANUAL STEPS REQUIRED:")
    print("=" * 70)
    print("1. Start tcpdump to capture NGAP:")
    print("   docker exec s1n2 tcpdump -i any -w /tmp/test_capture.pcap port 38412 &")
    print("")
    print("2. Send the S1AP message (requires SCTP tools)")
    print("   # This is complex - see alternative methods below")
    print("")
    print("3. Check s1n2 logs:")
    print("   docker logs s1n2 | grep -A 10 'InitialUEMessage'")
    print("")
    print("=" * 70)

if __name__ == '__main__':
    main()
