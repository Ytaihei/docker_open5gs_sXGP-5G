# Testing Results

## 2025年9月2日 - End-to-End Connectivity Test Results

### 4G LTE Configuration ✅
- **Core Network**: Open5GS 4G (local source build)
- **RAN**: SRS LTE eNB + UE (ZMQ-based simulation)
- **Connection Status**: Full attachment successful
- **IP Address**: 192.168.100.2 assigned to UE
- **Tunnel Interface**: tun_srsue created successfully
- **Internet Connectivity**: 
  - ping 8.8.8.8: **SUCCESS** (0% packet loss, avg 1.87ms)
  - ping 1.1.1.1: **SUCCESS** (0% packet loss)

### 5G SA Configuration ✅
- **Core Network**: Open5GS 5G SA (local source build)
- **RAN**: SRS RAN gNB + UE (ZMQ-based simulation)
- **Connection Status**: Full attachment and PDU session establishment
- **IP Address**: 192.168.100.2 assigned to UE
- **Tunnel Interface**: tun_srsue created successfully
- **Internet Connectivity**:
  - ping 8.8.8.8: **SUCCESS** (0% packet loss, avg 2.03ms)
  - ping 1.1.1.1: **SUCCESS** (0% packet loss, avg 2.57ms)

### Technical Achievements
1. **Local Source Builds**: Successfully deployed Open5GS and SRS RAN from source code
2. **End-to-End Connectivity**: Verified complete data path from UE to Internet
3. **Dual Mode Support**: Both 4G LTE and 5G SA configurations working
4. **ZMQ Simulation**: RF simulation using ZeroMQ for gNB-UE communication
5. **Docker Orchestration**: Full containerized deployment with proper networking

### Key Configuration Fix for 5G
- **Issue**: SRS RAN gNB crypto worker assertion failure
- **Solution**: Removed HAL configuration section (DPDK not supported in build)
- **Result**: Stable 5G gNB operation and successful UE attachment

### Network Architecture Validated
```
Internet (8.8.8.8, 1.1.1.1)
    ↑
   UPF (User Plane Function)
    ↑ N3/N6 interface
   SMF (Session Management Function)
    ↑ N4 interface  
   AMF (Access and Mobility Function)
    ↑ N2 interface
   gNB (5G Base Station) / eNB (4G Base Station)
    ↑ Radio interface (ZMQ simulation)
   UE (User Equipment)
```

### Subscriber Configuration
- **IMSI**: 001011234567895
- **Authentication Key (K)**: 8baf473f2f8fd09487cccbd7097c6862
- **Operator Key (OP)**: 11111111111111111111111111111111
- **AMF**: 8000
- **Status**: Successfully registered in MongoDB

This validates the complete integration of local source builds with full end-to-end connectivity for both 4G and 5G mobile networks.
