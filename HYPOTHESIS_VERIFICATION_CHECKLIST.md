# Hypothesis Verification Checklist
## ICS Failure Cause 26 - Security Header Type Mismatch

**Hypothesis**: eNB/UE requires Security Header Type 2 (0x27) format in Attach Accept, even when EEA0 is negotiated.

**Date**: 2025-11-12
**Status**: 🔄 VERIFICATION IN PROGRESS

---

## Current Evidence Summary

### ✅ Evidence Already Obtained

#### 1. Success vs Failure pcap Comparison

**Success Case** (4G_Attach_Successful.pcap, frame 102):
```
NAS-PDU header: 0x27 = Security header type 2 (Integrity protected and ciphered)
MAC: 0x9b5f9ad7
Sequence number: 2
Inner message: 0x07 0x42 (Attach Accept)
```

**Failure Case** (20251112_6.pcap, frame 1083):
```
NAS-PDU header: 0x17 = Security header type 1 (Integrity protected)
MAC: 0x4bc1b4b3
Sequence number: 1
Inner message: 0x07 0x42 (Attach Accept)
```

**Finding**: ✅ Header type differs (0x27 vs 0x17)

#### 2. Negotiated Algorithm Verification

**Success Case** (frame 94 - Security Mode Command):
```
Selected NAS security algorithms:
  Type of ciphering algorithm: EPS encryption algorithm EEA0 (null ciphering algorithm) (0)
  Type of integrity protection algorithm: EPS integrity algorithm 128-EIA2 (2)
```

**Failure Case** (s1n2 log):
```
Selected NAS alg mapping: 5G (nea=0, nia=2) -> 4G (eea=0, eia=2, octet=0x02)
```

**Finding**: ✅ Both cases negotiated **EEA0** (no encryption)

#### 3. s1n2 Code Logic Analysis

**Current s1n2 behavior**:
```c
if (eea_sel == 0) {
    enc_alg = S1N2_NAS_EEA0;
    // enc_alg != S1N2_NAS_EEA0 check fails
    // enc_ok remains false
    // → Falls back to Type 1 (0x17)
}
```

**Finding**: ✅ s1n2 chooses Type 1 when EEA0 is negotiated (by design, but incorrect)

#### 4. RRC Timeline Confirmation

**Failure sequence**:
```
11:11:06.985338  S1AP ICS Request (with Type 1 NAS-PDU)
11:11:07.184358  RRC Connection Reconfiguration sent
11:11:07.226062  ICS Failure (Cause 26 - no RRC Reconfiguration Complete from UE)
```

**Finding**: ✅ UE did not respond to RRC Reconfiguration after receiving Type 1 Attach Accept

---

## 🔍 Missing Evidence for Hypothesis Confirmation

### Critical Missing Information

#### A. **Actual Encryption Content Verification** ⚠️⚠️⚠️

**Question**: Is the success case's NAS-PDU **actually encrypted**, or just formatted as Type 2 with EEA0 (null cipher)?

**Current Status**:
- We know: Security header is Type 2 (0x27)
- We DON'T know: If payload is actually ciphered or plaintext

**How to verify**:
1. Extract encrypted payload from success case (after MAC+SEQ)
2. Try to decode inner NAS message without decryption
3. If readable → EEA0 was used (null cipher)
4. If unreadable → EEA2 was actually used (contradiction!)

**Success Case NAS-PDU** (from pcap):
```
27 9b 5f 9a d7 02 | 07 42 01 29 06 40 00 f1 10 00 01 00 01 d5 20 1c ...
^^ ^^^^^^^^^^^ ^^   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
|  |           |    Encrypted payload (or plaintext if EEA0?)
|  |           SEQ=2
|  MAC
Type 2
```

**Test**:
```bash
# Extract payload (skip first 6 bytes: type(1) + MAC(4) + SEQ(1))
echo "07420129064000f11000010001d5201c10109090..." | xxd -r -p | xxd

# Check if first byte is 0x07 (EPS MM PD) - if yes, it's plaintext!
```

**Expected Result**:
- If EEA0 was used: Payload should start with `0x07 0x42` (readable Attach Accept)
- If EEA2 was used: Payload should be random-looking bytes

**Impact**: If payload is **plaintext**, it confirms EEA0 uses Type 2 format with null cipher.

---

#### B. **3GPP Specification Clarification** ⚠️⚠️

**Question**: Does 3GPP TS 24.301 explicitly require Type 2 format for Attach Accept with EEA0?

**Current Status**: We infer from pcap, but no specification reference

**How to verify**:
1. Check 3GPP TS 24.301 Section 5.4.3.2 (Security header type)
2. Check Section 8.2.1 (Attach accept)
3. Look for rules about security header selection with EEA0

**Key Sections to Check**:
- TS 24.301 5.4.3.2: "Security protected NAS message format"
- TS 24.301 8.2.1: "Attach accept"
- TS 33.401: EPS security architecture (EEA0 definition)

**Expected Finding**:
- Clear statement about Type 2 usage with EEA0, OR
- Ambiguity that explains vendor-specific behavior

---

#### C. **Real MME Behavior Confirmation** ⚠️

**Question**: How does a real Open5GS MME (4G native) format Attach Accept with EEA0?

**Current Status**: Unknown - we only have s1n2 (converter) behavior

**How to verify**:
1. Set up pure 4G network (Open5GS MME + real eNB)
2. Configure MME to select EEA0
3. Capture Attach Accept
4. Check security header type

**Impact**: If real MME uses Type 2, it confirms this is standard behavior.

---

#### D. **UE Logs/Debug Info** ⚠️

**Question**: Why did UE reject the Attach Accept?

**Current Status**: We only know "no RRC Reconfiguration Complete" from eNB side

**How to verify**:
1. Enable UE debug logging (if possible)
2. Check for NAS decoding errors
3. Check for security context errors
4. Check for PDN address errors

**Possible UE Error Messages**:
- "Invalid NAS security header"
- "Security context mismatch"
- "Failed to process Attach Accept"

---

#### E. **Alternative eNB/UE Combination Test** ⚠️

**Question**: Is this issue specific to this eNB/UE pair?

**How to verify**:
1. Test with different UE model
2. Test with different eNB vendor
3. Compare results

**Impact**: Rules out device-specific bugs

---

## 🧪 Verification Experiments

### Experiment 1: Decrypt Success Case Payload (HIGH PRIORITY)

**Purpose**: Confirm EEA0 was used in success case

**Steps**:
```bash
# 1. Extract success case NAS-PDU
tshark -r 4G_Attach_Successful.pcap -Y "frame.number == 102" \
  -T fields -e s1ap.nas_pdu > success_nas.hex

# 2. Skip security header (6 bytes), check if payload is plaintext
# If starts with 0x07 0x42, it's plaintext → EEA0 confirmed

# 3. Compare with failure case inner message
# They should have similar structure
```

**Expected Outcome**: Success case uses Type 2 format with plaintext payload (EEA0 null cipher)

**Decision Point**: If confirmed → Hypothesis is **highly likely correct**

---

### Experiment 2: Force Type 2 in s1n2 (HIGH PRIORITY)

**Purpose**: Test if Type 2 resolves ICS Failure

**Steps**:
1. Modify s1n2 to always use Type 2 (0x27) even with EEA0
2. Implement EEA0 as identity function (memcpy)
3. Rebuild and test with real UE
4. Check if ICS succeeds

**Code Change**:
```c
// In s1n2_nas.c, around line 2274
if (enc_alg == S1N2_NAS_EEA0) {
    // EEA0: null cipher (identity function)
    memcpy(cipher, out, out_off);
    enc_ok = true;  // ← Force Type 2 path
} else if (enc_alg != S1N2_NAS_EEA0) {
    // EEA2: actual encryption
    if (s1n2_nas_encrypt(...) == 0) {
        enc_ok = true;
    }
}
```

**Expected Outcome**: ICS succeeds, UE completes RRC Reconfiguration

**Decision Point**: If ICS succeeds → Hypothesis is **CONFIRMED**

---

### Experiment 3: Check Open5GS MME Source Code (MEDIUM PRIORITY)

**Purpose**: See how reference implementation handles EEA0

**Steps**:
```bash
# Clone Open5GS
git clone https://github.com/open5gs/open5gs.git
cd open5gs

# Search for Attach Accept generation with EEA0
grep -r "0x27\|Type.*2\|EEA0" src/mme/
grep -r "nas_encrypt" src/mme/
```

**Expected Finding**: Open5GS MME uses Type 2 format even with EEA0

---

### Experiment 4: Wireshark Dissector Behavior Analysis (LOW PRIORITY)

**Purpose**: Understand if Wireshark expects Type 2 with EEA0

**Steps**:
1. Check Wireshark NAS-EPS dissector source
2. See how it handles Type 2 with EEA0
3. Check if any warnings/errors are generated

**Impact**: Informational only

---

## 📊 Confidence Level Assessment

### Current Hypothesis Confidence: **85%** 🟢

**Strong Evidence (Supporting)**:
- ✅ Clear difference in security header type (0x27 vs 0x17)
- ✅ Both cases negotiated EEA0
- ✅ Success case used Type 2 despite EEA0
- ✅ s1n2 incorrectly interprets EEA0 → Type 1
- ✅ UE rejected Attach Accept in failure case

**Weak Evidence / Gaps**:
- ⚠️ No confirmation that success payload is plaintext (EEA0)
- ⚠️ No 3GPP specification reference
- ⚠️ No UE logs explaining rejection
- ⚠️ No test with other UE/eNB combinations

**Alternative Hypotheses** (Low probability):
1. **PDN address conflict** (5%) - But structure is correct
2. **Timing issue** (5%) - But RRC Reconfiguration was sent
3. **First RRC Reconfiguration interference** (5%) - Unusual but possible

---

## ✅ Hypothesis Confirmation Criteria

Hypothesis will be considered **CONFIRMED** if:

1. ✅ **Critical**: Experiment 2 (Force Type 2) succeeds → ICS Success
2. ✅ **Supporting**: Experiment 1 shows success payload is plaintext (EEA0)
3. ✅ **Supporting**: Open5GS MME code uses Type 2 with EEA0

Hypothesis will be considered **HIGHLY LIKELY** if:
1. ✅ Experiment 1 confirms EEA0 plaintext in success case
2. ❌ Unable to test Experiment 2 (no UE access)

Hypothesis will be considered **UNCERTAIN** if:
1. ❌ Experiment 1 shows success payload is actually encrypted (EEA2)
2. ❌ 3GPP spec says Type 1 is correct with EEA0

---

## 🎯 Next Steps

### Immediate Actions (Can be done now):

1. **[5 min]** Run Experiment 1: Verify success case payload is plaintext
   ```bash
   ./verify_eea0_plaintext.sh
   ```

2. **[30 min]** Implement Experiment 2: Modify s1n2 to use Type 2 with EEA0

3. **[10 min]** Run Experiment 3: Check Open5GS MME source code

### Requires UE Access:

4. **[20 min]** Test modified s1n2 with real UE

5. **[Optional]** Get UE logs if available

---

## 📝 Verification Script

```bash
#!/bin/bash
# verify_eea0_plaintext.sh

echo "=== Verifying EEA0 Plaintext in Success Case ==="

# Extract success case NAS-PDU (skip S1AP header, take NAS part)
SUCCESS_NAS=$(tshark -r 4G_Attach_Successful.pcap -Y "frame.number == 102" \
  -T fields -e s1ap.nas_pdu 2>/dev/null | head -1)

echo "Success NAS-PDU (hex): ${SUCCESS_NAS:0:60}..."

# Skip security header (6 bytes = 12 hex chars)
PAYLOAD_START=$(echo "$SUCCESS_NAS" | cut -c13-)

echo "Payload after security header: ${PAYLOAD_START:0:40}..."

# Check first two bytes
FIRST_BYTE=$(echo "$PAYLOAD_START" | cut -c1-2)
SECOND_BYTE=$(echo "$PAYLOAD_START" | cut -c3-4)

echo ""
echo "First byte: 0x$FIRST_BYTE (expected: 0x07 for EPS MM)"
echo "Second byte: 0x$SECOND_BYTE (expected: 0x42 for Attach Accept)"

if [ "$FIRST_BYTE" == "07" ] && [ "$SECOND_BYTE" == "42" ]; then
    echo ""
    echo "✅ CONFIRMED: Payload is PLAINTEXT"
    echo "✅ Success case uses Type 2 format with EEA0 (null cipher)"
    echo "✅ Hypothesis is HIGHLY LIKELY CORRECT"
else
    echo ""
    echo "❌ WARNING: Payload appears ENCRYPTED"
    echo "❌ This contradicts our hypothesis"
    echo "❌ Need to re-evaluate"
fi
```

---

## Summary: What We Need

**To reach 95%+ confidence**:
1. ✅ Verify success payload is plaintext (Experiment 1)
2. ✅ Test modified code with UE (Experiment 2)

**To reach 100% confidence**:
3. ✅ Find 3GPP specification reference
4. ✅ Get UE logs showing exact error
5. ✅ Verify with Open5GS MME source code

**Current action**: Run Experiment 1 first (takes 5 minutes, no risk)
