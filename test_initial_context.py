#!/usr/bin/env python3
"""
Test client to send InitialContextSetupRequest to s1n2-converter
"""

import socket
import time

def send_initial_context_setup_request():
    # Connect to s1n2-converter S1C interface
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        sock.connect(('172.24.0.30', 36412))  # s1n2-converter S1C interface
        print("Connected to s1n2-converter S1C interface")

        # Sample InitialContextSetupRequest (procedure code 9)
        # This is a simplified test message
        initial_context_setup_request = bytes([
            0x00, 0x09,  # Procedure code 9 (InitialContextSetupRequest)
            0x00, 0x2C,  # Message length (44 bytes)

            # Simplified InitialContextSetupRequest content
            0x00, 0x00, 0x00, 0x04,  # IE Count = 4

            # IE 1: MME-UE-S1AP-ID (id=0)
            0x00, 0x00,  # IE ID = 0
            0x40, 0x04,  # Criticality=reject, length=4
            0x00, 0x00, 0x00, 0x01,  # MME-UE-S1AP-ID = 1

            # IE 2: eNB-UE-S1AP-ID (id=8)
            0x00, 0x08,  # IE ID = 8
            0x00, 0x04,  # Criticality=reject, length=4
            0x00, 0x00, 0x00, 0x01,  # eNB-UE-S1AP-ID = 1

            # IE 3: E-RABToBeSetupListCtxtSUReq (id=24)
            0x00, 0x18,  # IE ID = 24
            0x00, 0x10,  # Criticality=reject, length=16
            # E-RAB setup with ID=1, QCI=9, TEID=0x12345678
            0x00, 0x01,  # E-RAB ID = 1
            0x09,        # QCI = 9
            0x00,        # Padding
            0x12, 0x34, 0x56, 0x78,  # UL TEID
            0x0A, 0x00, 0x00, 0x02,  # Transport Layer Address (10.0.0.2)
            0x08, 0x68,  # Transport Port = 2152
            0x00, 0x00,  # Padding

            # IE 4: UESecurityCapabilities (id=107) - simplified
            0x00, 0x6B,  # IE ID = 107
            0x00, 0x04,  # Criticality=reject, length=4
            0x00, 0x01, 0x02, 0x03,  # Security capabilities
        ])

        print(f"Sending InitialContextSetupRequest ({len(initial_context_setup_request)} bytes)...")
        sock.send(initial_context_setup_request)

        # Wait for response
        time.sleep(1)
        response = sock.recv(1024)
        print(f"Received response: {len(response)} bytes")
        if response:
            print("Response hex:", response.hex())

    except Exception as e:
        print(f"Error: {e}")
    finally:
        sock.close()

if __name__ == "__main__":
    send_initial_context_setup_request()
