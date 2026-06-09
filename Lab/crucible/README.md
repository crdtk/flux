# Phanteks Enthoo Pro 2 — Primary Inference Node

**Case**: Phanteks Enthoo Pro 2 Tempered Glass (PH-ES620PTG_DBK01)  
**Role**: `crucible` — production LLM inference, NFS model weight server  
**Target**: Qwen3.5-397B-A17B Q4 at ~130 tok/s decode

---

## Hardware Inventory

| # | Component | Detail | Status |
|---|-----------|--------|--------|
| 1 | **Motherboard** | ASRock Rack E3C256D4I-2T · Mini-ITX · LGA1200 · Intel C256 · PCIe 4.0 x16 · 4× DDR4 SODIMM · 2× OCuLink · IPMI (AST2500) · 2× 10GbE | DELIVERED |
| 2 | **CPU** | Intel Xeon E-2314 · 4C/4T · 65W · LGA1200 · 20 PCIe 4.0 lanes | DELIVERED |
| 3 | **CPU Cooler** | Jonsbo CR-1400 EVO · 92mm PWM · 180W TDP · LGA1200 | DELIVERED |
| 4 | **RAM** | 2× Samsung M471A2K43BB1-CPB · 16GB DDR4-2133 SODIMM · non-ECC · unbuffered · dual-rank · 1.2V = 32GB · max 128GB (4× 32GB SODIMM) · 2 slots free (2 of 4 owned SODIMMs; other 2 in serval) | OWNED |
| 5 | **Storage — Boot** | Samsung 9100 PRO 8TB · M.2 PCIe 4.0 x4 · S/N: S7YHNJ0YC07013D · FW: 0B2QNXH7 · in M2_1 slot · Manjaro KDE (btrfs) | INSTALLED |
| 6 | **Storage — Models** | WD_BLACK SN8100 8TB · M.2 PCIe 4.0 x8 · S/N: 25437L400188 · FW: 930BRI19 · in ICY DOCK MB111VP-B · currently in PCIE7 (temp) → target: OCuLink via MB705M2P-B + Tekram TK-2U11 | INSTALLED (staging) |
| 7 | **Storage Adapter** | ICY DOCK MB111VP-B · M.2→U.2 PCIe bracket adapter · currently in PCIE7 | OWNED |
| 8 | **Storage Adapter** | ICY DOCK MB705M2P-B · M.2→U.2 converter | OWNED |
| 9 | **OCuLink Adapter** | Tekram TK-2U11 · OCuLink SFF-8611 host adapter | OWNED |
| 10 | **PSU** | be quiet! Dark Power Pro 13 1600W (BN332) · 80+ Titanium · 135mm fan | DELIVERED |
| 11 | **Case** | Phanteks Enthoo Pro 2 Tempered Glass · full tower · dual PSU mount · 11 expansion slots | DELIVERED |
| 12 | **PCIe Switch** | PLX Technology PEX 8749 · 48-lane 18-port Gen 3 · enumerated at 01:00.0 · 8 downstream ports live · PCIe link confirmed on E3C256D4I-2T PCIE7 | INSTALLED ✓ |
| 13 | **GPU Backplanes** | 4× JMT JHHP1B · 2× SFF-8654 8i in → 1× PCIe x16; **1 cable sufficient for x8** · requires PCIe 6-pin power | 2 INSTALLED ✓ · 2 TBD |
| 14 | **SlimSAS Cables** | 4× SFF-8654 8i · 50cm · **1 cable per backplane (x8) — 4 owned = enough for 4 GPUs** | 4 INSTALLED ✓ |
| 15 | **GPUs** | 4× NVIDIA RTX PRO 6000 Blackwell Max-Q · 96GB GDDR7 · 1.8 TB/s · 300W · blower (→ water blocks: Bykski N-RTXPRO6000-SR) | TBD |

---

## Motherboard Specs

- **Board**: ASRock Rack E3C256D4I-2T (Mini-ITX, 6.7" × 6.7")
- **Socket**: LGA1200, Intel C256 chipset
- **RAM**: 4× DDR4 SO-DIMM, Dual Channel, max 128GB, Non-ECC + ECC supported
- **PCIe**: 1× PCIe 4.0 x16
- **M.2**: 1× M.2/M-Key (PCIe 4.0 x4, 2280)
- **Other**: 2× OCuLink SFF-8611 (PCIe 3.0 x4/SATA), 8× SATA, 2× 10GbE (Intel X550-AT2), IPMI (AST2500)
- **BIOS bifurcation**: x16, x8x8, x8x4x4 (x4x4x4x4 not supported — PEX88048 provides GPU fanout instead)

---

## PCIe Architecture

```
ASRock E3C256D4I-2T PCIE7 (x16)
       │
  PLX Technology PEX 8749 (48-lane, 18-port, PCIe Gen 3)
  10b5:8749 rev ca — no BIOS bifurcation needed
       │
  ┌────┴─────────────────────────────────────────┐
  │ upstream 01:00.0                             │
  │                                              │
  │  02:08.0 ──── 1 cable ──► JHHP1B #1 ──► GPU 1  (PCIe x8)        │
  │  02:09.0 ──── 1 cable ──► JHHP1B #2 ──► GPU 2  (A4000 ✓ x8)    │
  │  02:0a.0 ──── 1 cable ──► JHHP1B #3 ──► GPU 3  (PCIe x8)        │
  │  02:0b.0 ──── 1 cable ──► JHHP1B #4 ──► GPU 4  (PCIe x8)        │
  └──────────────────────────────────────────────┘

  Each JHHP1B: 1× SFF-8654 8i → PCIe x8 (confirmed); 2× SFF-8654 8i → PCIe x16 (max)
  1× PCIe 6-pin power required per backplane
  Currently: 2 of 4 backplanes owned · 4 cables owned (enough for 4 backplanes at x8)
```

---

## PCIe Slot Assignment

| Slot | Component | Notes |
|------|-----------|-------|
| PCIE7 (x16) | PLX Technology PEX 8749 switch card | Enumerated at 01:00.0 · 8 downstream ports live ✓ |
| M2_1 | Samsung 9100 PRO 8TB | Boot drive, permanently occupied |
| OCuLink 1 | Tekram TK-2U11 + MB705M2P-B + SN8100 | Target state: model weights at PCIe 3.0 x4 |
| OCuLink 2 | Free | Future: SATA breakout or second NVMe |

## PCIe Switch Test — 2026-05-30

### Stage 1 — Switch enumeration (no backplane power)

**Result: PASS.** PLX Technology PEX 8749 fully enumerated on first boot. All 8 downstream buses empty — backplanes connected but missing PCIe 6-pin power.

### Stage 2 — Full path validation with RTX A4000 + SN8100 (2026-05-30)

**Result: PASS.** GPU and NVMe enumerated through switch after connecting PCIe 6-pin power to each JHHP1B backplane.

```
PCIe topology:
[CPU] → 00:01.0 → [01:00.0 PEX8749 upstream]
                       ├─ 02:08.0 → [bus 03] empty
                       ├─ 02:09.0 → [bus 04] empty
                       ├─ 02:0a.0 → [bus 05] empty
                       ├─ 02:0b.0 → [bus 06] 06:00.0 NVIDIA RTX A4000 (GA104GL) ✓
                       │                      06:00.1 NVIDIA GA104 HD Audio ✓
                       ├─ 02:10.0 → [bus 07] empty
                       ├─ 02:11.0 → [bus 08] empty
                       ├─ 02:12.0 → [bus 09] 09:00.0 WD SN8100 8TB via MB111VP-B ✓
                       └─ 02:13.0 → [bus 0a] empty
```

**Confirmed:**
- Chip: PLX PEX 8749 (48-lane, 18-port, PCIe Gen 3) — `10b5:8749 rev ca`
- GPU path: CPU → PEX8749 → JHHP1B backplane → RTX A4000 — full enumeration, NVIDIA NovaCore driver loaded
- NVMe path: CPU → PEX8749 → JHHP1B backplane → MB111VP-B → SN8100 — enumerated
- No AER errors, no link training failures
- **Root cause of initial failure:** JHHP1B backplane requires a PCIe 6-pin power connector; SFF-8654 cables carry signals only, not power

**Switch path validated. RTX PRO 6000 Blackwell Max-Q will enumerate the same way.**

### Stage 3 — 1-cable validation (2026-05-30)

**Result: PASS.** Disconnected 1 of 2 SFF-8654 cables from the A4000 backplane. A4000 re-enumerated cleanly at `02:09.0 → bus 04` — same GPU, different downstream port, x8 link.

```
PCIe topology (1-cable test):
[CPU] → 00:01.0 → [01:00.0 PEX8749 upstream]
                       ├─ 02:08.0 → [bus 03] empty
                       ├─ 02:09.0 → [bus 04] 04:00.0 NVIDIA RTX A4000 ✓  ← 1 cable only
                       ├─ 02:0a.0 → [bus 05] empty
                       ├─ 02:0b.0 → [bus 06] empty
                       ...
```

**Confirmed:** JHHP1B operates at PCIe x8 with a single SFF-8654 8i cable.  
**Implication:** 4 switch connectors × 1 cable each = 4 backplanes = **4 GPUs at x8 — with cables already owned.**

### 4-GPU Expansion Checklist

| Step | Action | Status |
|------|--------|--------|
| 1 | PEX8749 switch enumerated in PCIE7 | ✓ done |
| 2 | JHHP1B powered (PCIe 6-pin) + 1 SFF-8654 cable → A4000 confirmed (x8) | ✓ done |
| 3 | 1-cable x8 operation validated — 4 owned cables = enough for 4 GPUs | ✓ done |
| 4 | Buy 2× more JHHP1B backplanes (no new cables needed) | pending |
| 5 | Connect all 4 backplanes: 1 cable + 6-pin power each | pending |
| 6 | Seat 4× RTX PRO 6000 Blackwell Max-Q, connect PCIe power to each | pending |
| 7 | Cold reboot → `make test-pex` → confirm 4 GPUs across 4 downstream buses | pending |

---

## Scaling Path

| Phase | GPUs | PSU config | VRAM | Est. tok/s (Qwen3.5 Q4) |
|-------|------|-----------|------|--------------------------|
| Phase 1 | 2× Max-Q (blower) | 1× DPP13 1600W (665W, 42% load) | 192 GB | ~80 |
| Phase 2 | 4× Max-Q (blower) | 1× DPP13 1600W (1300W, 81% load) | 384 GB | ~130–150 |
| Phase 3 | 8× Max-Q (water blocks) | 2× DPP13 1600W (2400W, 75% each) | 768 GB | ~250+ |
| Future | 7× Max-Q + EPYC Genoa | 2× DPP13 1600W | 672 GB | ~220+ |

---

## Case Layout

**Phase 1–2 (current build, blower GPUs):**

```
Back panel (Phanteks Enthoo Pro 2 TG — 11 slots):
  ┌──────────────────┐
  │ [V1] [V2] [V3]   │ ← 3 vertical slots: free / future water passthrough
  │──────────────────│
  │ [H1 ═══════════] │
  │ [H2 ═══════════] │ ← 8 horizontal slots: GPUs on JMT backplanes
  │ [H3 ═══════════] │   Phase 1: 2 dual-slot blower GPUs
  │ [H4 ═══════════] │   Phase 2: 4 dual-slot blower GPUs
  │ [H5 ═══════════] │
  │ [H6 ═══════════] │
  │ [H7 ═══════════] │
  │ [H8 ═══════════] │
  │──────────────────│
  │ [D1] [D2] [D3]   │ ← 3 slots: dual-system bracket (or 2nd PSU mount)
  └──────────────────┘
```

**Phase 3 — EPYC Genoa migration (7 GPUs + 3 hot-swap SATA + water cooling):**

```
Back panel (EPYC GENOAD8X-2T/BCM — 8 native PCIe 5.0 slots):
  ┌─────────────────────────────────────┐
  │ [V1] EK PCI Pass-Through (1 slot,   │ ← 1 EK bracket = 2× G1/4 ports
  │      water IN + OUT + cable hole)   │   in + out in single slot opening
  │ [V2] StarTech S25SLOTR #1 (passive) │ ← hot-swap SATA SSD (no PCIe lanes)
  │ [V3] StarTech S25SLOTR #2 (passive) │ ← hot-swap SATA SSD (no PCIe lanes)
  │─────────────────────────────────────│
  │ [H1] GPU 1 (water block, single-slot)│
  │ [H2] GPU 2                           │
  │ [H3] GPU 3                           │
  │ [H4] GPU 4 (RTX PRO 6000 Max-Q)      │ ← 7× at PCIe 5.0 x16 each
  │ [H5] GPU 5                           │   on EPYC GENOAD8X-2T/BCM
  │ [H6] GPU 6                           │
  │ [H7] GPU 7                           │
  │ [H8] StarTech S25SLOTR #3 (passive)  │ ← hot-swap SATA SSD (no PCIe lanes)
  └─────────────────────────────────────┘
  All 11 slots used: 7 GPUs + 3 SATA hot-swap + 1 water passthrough.
  Front: 1× G1/4 drain port for water loop fill/drain.
```

**Key parts for Phase 3:**
- [StarTech S25SLOTR](https://www.amazon.de/StarTech-com-5-Zoll-SATA-Wechsellrahmen-f%C3%BCr-PC-Erweiterungssteckplatz/dp/B002MWDRD6) (~€30–40) — purely mechanical bracket, bolts into slot opening for physical mounting only; no PCIe lanes needed
- [EK PCI Bracket Pass-Through](https://www.amazon.de/dp/B0CKZJ82PM) (~€40) — 2× G1/4 ports + cable hole in one slot opening; saves 2 slots vs separate in/out

---

## Storage Subsystem

```
Tier 1: M2_1 — PCIe 4.0 x4 (CPU-direct)
  └── Samsung 9100 PRO 8TB — boot, OS, active model                ~7 GB/s

Tier 2: OCuLink 1 — PCIe 3.0 x4 (PCH)
  └── WD_BLACK SN8100 8TB — model weight rotation                  ~3.5 GB/s
      (via MB705M2P-B M.2→U.2 + MB111VP-B rear hot-swap tray)

Tier 3: OCuLink 2 — 4× SATA 6Gb/s (PCH, BIOS set to SATA mode)
  └── OCuLink→4× SATA breakout (Supermicro CBL-SAST-0933)          ~550 MB/s/drive
      ├── Rear PCI bracket hot-swap (ICY DOCK MB839SP-B)
      └── 2× internal SSD mirror (btrfs RAID1 backup)
```

---

## OCuLink Hot-Swap

Rear-accessible NVMe hot-swap using the motherboard OCuLink port (PCIe 3.0 x4). Drive slides in/out from the rear PCI bracket — no tools, no case opening.

**Signal chain:**
```
M.2 NVMe SSD
    ↓ (tool-less insertion)
ICY DOCK MB705M2P-B (M.2 → U.2 converter, 2.5" form factor)
    ↓ (slides into tray)
ICY DOCK MB111VP-B (U.2 hot-swap tray, PCIe card bracket)
    ↓
CableCC SF-056 (OCuLink → PCIe x16/x4 adapter, SATA-powered)
    ↓ (OCuLink cable)
OCU1 — BIOS: PCIe mode (Advanced → PCH Storage Configuration)
```

**BOM:**

| Part | Price | Link |
|------|-------|------|
| ICY DOCK MB111VP-B | €136.89 | [Amazon.de](https://www.amazon.de/-/en/ICY-DOCK-EZConvert-MB705M2P-B-converter/dp/B0C53QZDQT) · [product page](https://global.icydock.com/product_350.html) |
| ICY DOCK MB705M2P-B | €44.90 | [Amazon.de](https://www.amazon.de/ICY-DOCK-EZConvert-MB705M2P-B-Konverter/dp/B07V5LH28N) · [product page](https://global.icydock.com/product_172.html) |
| CableCC SF-056 | €26.04 | [Amazon.de](https://www.amazon.de/dp/B0BP1ZWHHV) · [product page](https://www.cablecc.com/oculink-sff8612-sff8611-to-pcie-pciexpress-16x-4x-adapter-with-sata-power-port-for-mainboard-graphics-card-p-5167.html) |
| OCuLink cable (SFF-8612, ~30cm) | ~€15 | Amazon.de |
| **Infrastructure total** | **~€223** | one-time, reusable across drives |

**Performance:** PCIe 3.0 x4 · ~3,500 MB/s read · 222 GB model load ~55 s · hot-plug supported

**Samsung 990 Pro 4TB ordered 2026-04-18** (PCIe 4.0 · 7450/6900 MB/s rated · capped at ~3,940 MB/s on OCuLink PCIe 3.0 x4)

### Test log

**2026-05-05 — CableCC SF-056 via OCuLink: FAILED**

```
SN8100 (WD_BLACK 8TB) → MB705M2P-B → MB111VP-B → CableCC SF-056 → OCU1 (PCIe mode)
```

Result: "Card present, no link" — PCIe link training failure. Drive not detected by OS.

Ruled out:
- ✓ BIOS OCuLink mode: confirmed PCIe before test
- ✓ MB111VP-B: works in PCIE7 direct slot
- ✓ SN8100: healthy, verified in PCIE7 direct slot

Unknown: whether fault is the OCuLink cable or the SF-056 adapter. CableCC SF-056 returned to Amazon 2026-05-07 (defective / no PCIe link).

**Next step:** test with a replacement OCuLink cable (30–50cm, SFF-8612 both ends) before concluding adapter is faulty.

---

## BMC / IPMI Reference

ASPEED AST2500 BMC on the E3C256D4I-2T. Out-of-band management: remote power, iKVM, sensors, firmware flash — independent of CPU/OS state.

### Network identity (observed 2026-04-12)

| Field | Value |
|-------|-------|
| Web UI | `https://192.168.178.23` |
| IPv4 | `192.168.178.23` (DHCP, FRITZ!Box) |
| IPv6 | `fd73:ff12:9fb8:0:9e6b:ff:fe47:2834` |
| MAC | `9C:6B:00:47:28:34` (ASRock OUI) |

Rediscover if DHCP lease changes:
```sh
sudo arp-scan --localnet | grep -iE '9c:6b:00|00:1b:78'
```
Or: FRITZ!Box → Heimnetz → Netzwerk → Netzwerkverbindungen → look for ASRock MAC.

### Credentials

- Factory default: `admin / admin` — **change on first access**
- Current password: stored in password manager (not committed)
- Change path: Configuration → Users

### Firmware versions (first boot, 2026-04-12)

| Component | Version |
|-----------|---------|
| BMC Firmware | `3.02.00` |
| BIOS Firmware | `3.04` |
| Intel SPS Firmware | `6.0.3.604` |
| CPU Microcode | `0000005e` |

### Power-on sequence

1. PSU AC on → +5VSB → BMC cold boot starts
2. ~30–60 s → green BMC heartbeat LED blinks at ~1 Hz
3. BMC reachable (web UI, IPMI-over-LAN port 623)
4. CPU stays **off** until explicit power-on (case button or BMC → Remote Control → Power On)

### Quick reference

```
PSU on → BMC boots (~30-60s) → find IP (arp-scan / FRITZ!Box)
  → https://<IP> → login admin/admin → CHANGE PASSWORD
  → Remote Control → Power On Server
  → Remote Control → iKVM → watch POST
  → DEL/F2 for BIOS, or OS install via Virtual Media
```

### ipmitool examples

```sh
sudo apt install ipmitool
ipmitool -I lanplus -H 192.168.178.23 -U admin -P '<password>' chassis power status
ipmitool -I lanplus -H 192.168.178.23 -U admin -P '<password>' sdr
ipmitool -I lanplus -H 192.168.178.23 -U admin -P '<password>' chassis power on
```

### Troubleshooting

| Symptom | Likely cause | Check |
|---------|-------------|-------|
| BMC heartbeat LED not blinking | +5VSB not reaching BMC | Verify PSU connected, ATX4PIN1 + ATX12V2 seated |
| Heartbeat blinks, web UI unreachable | IPMI LAN cable or wrong subnet | arp-scan, confirm cable link LED |
| Web UI login fails | Firmware reset or account locked | Unplug AC 30 s, replug, wait for heartbeat, retry |
| iKVM shows black screen | CPU not running | Verify power status shows "On"; check CPU fan |
| `chassis power on` does nothing | BMC locked state | Clear via Remote Control → Chassis Identify Command |

---

## First-Boot Baseline

**Date:** 2026-04-12  
**State:** CPU + 1 DIMM + M.2 NVMe + BMC + POST complete

### Sensors (all within spec)

**Voltage rails:**

| Rail | Reading | Nominal |
|------|---------|---------|
| 3VSB | 3.36 V | 3.30 V |
| 5VSB | 5.05 V | 5.00 V |
| VCORE | 0.91 V | VID-dependent (idle Xeon E-2300) |
| VCCM | 1.19 V | 1.20 V (DDR4 VDD) |
| VPPM | 2.54 V | 2.50 V (DDR4 VPP) |
| BAT | 2.88 V | 3.00 V (replace if <2.5 V) |
| 12V | 11.9 V | 12.00 V |

**Temperatures:** CPU 26 °C · PCH 51 °C (normal by design) · MB 32 °C  
**Fans:** FAN1 1300 RPM (Jonsbo CR-1400 EVO)

### Memory (first boot — single DIMM)

| Slot | Physical | Size | Manufacturer | Serial | Part | Speed |
|------|---------|------|-------------|--------|------|-------|
| DDR4_A2 | **Enabled** | 16384 MB | Samsung | 980EEF34 | M471A2K43BB1-CPB | 2133 MHz |
| DDR4_A1/B1/B2 | Absent | — | — | — | — | — |

Single-channel mode. For dual-channel: add second SODIMM to **DDR4_B2** (not DDR4_B1).

### PCIe enumeration

- **2× Intel X550 10GbE** (VID 0x8086 / DID 0x1563) — both ports detected
- **Samsung 9100 PRO on M2_1** (0x144D:0xA810) — NVMe mass storage, Bus 0 (CPU-direct)
- PCIE7 empty at this point

### Wiring gotcha

Front-panel bundle was in **ITX_AUX_PANEL1 (#11, server aux)** instead of **PANEL1 (#12, front-panel)**. Both are 9-pin, physically adjacent, similar silkscreen. Power button did nothing until moved to PANEL1. Now in the risk register.

### Milestone log

| Date | Milestone |
|------|-----------|
| 2026-04-12 | First POST · all sensors within spec |
| 2026-04-12 | X550 LAN_1 (`enp59s0`, MAC `80:fa:5b:25:3b:3c`) link-tested — 0.03 ms RTT, zero loss · driver: `ixgbe` |
| 2026-04-18 | Manjaro KDE installed to 9100 PRO 8TB (nvme1n1, btrfs) · hostname `crucible` · SSH up |
| 2026-04-22 | WD_BLACK SN8100 8TB added (nvme0n1) · firmware 930BRI19 · 26.9 °C · unformatted |

### Storage snapshot (2026-04-22)

| Drive | Model | Serial | FW | Temp | Status |
|-------|-------|--------|-----|------|--------|
| nvme1n1 | Samsung 9100 PRO 8TB | S7YHNJ0YC07013D | 0B2QNXH7 | 34.9 °C | Boot (btrfs) |
| nvme0n1 | WD_BLACK SN8100 8TB | 25437L400188 | 930BRI19 | 26.9 °C | Unformatted |

### Baseline drift thresholds

| Reading | Investigate if |
|---------|---------------|
| VCORE | >1.4 V sustained or <0.7 V |
| 12V | <11.4 V or >12.6 V |
| CPU Temp | >85 °C under load, >40 °C idle |
| PCH Temp | >75 °C sustained |
| BAT | <2.5 V |
| FAN1 RPM | 0 RPM with CPU running |
| Any DIMM → Absent | Re-seat; check socket pins |
| M2_1 disappears | Re-seat NVMe; check BIOS NVMe detection toggle |

### Still to verify

- [ ] Add second SODIMM to DDR4_B2, verify dual-channel detection
- [ ] Add third/fourth SODIMMs (DDR4_A1 + DDR4_B1), verify 2DPC at 2133 MHz
- [x] Install PEX88048 switch card in PCIE7, verify BIOS enumeration — 2026-05-30
- [ ] Connect case fans to FAN2 and FAN3
- [x] First GPU enumeration via PCIe switch — RTX A4000 confirmed at 06:00.0 — 2026-05-30

---

## Risk Register

| Risk | Rule | If wrong | Source |
|------|------|----------|--------|
| 💀 **DAMAGE** | Do not cross-connect **ATX4PIN1** (signal) with **SATAPWR1** (12V/5V). Pinouts differ. | Permanent motherboard damage. | p.21 §2.8 |
| 💀 **DAMAGE** | DDR4 SODIMM slots accept **only DDR4 260-pin SODIMM**. Never force DDR3, DDR5, or 288-pin UDIMM. | Permanent motherboard + DIMM damage. | p.16 §2.5 |
| 💀 **DAMAGE** | DIMM orientation: key notch matches slot tab. Do not force. | Permanent motherboard + DIMM damage. | p.16 §2.5 |
| 💀 **DAMAGE** | Unplug AC before installing/removing components. Verify **+5VSB LED** is off. | Electrical short risk. | p.12 §2.2 |
| 🔴 **BOOT BLOCK** | CPU fan **must** be wired to `FAN1` with tach signal. | Board halts POST with no error message. | p.7 §1.4, p.20 §2.8 |
| 🔴 **BOOT BLOCK** | Two 9-pin headers: `PANEL1` (#12, front-panel) and `ITX_AUX_PANEL1` (#11, server aux). Case bundle goes on **`PANEL1`**. They're adjacent and nearly identical. | Power button does nothing; BMC works but CPU stays off. | p.7 §1.4, p.20 §2.8 |
| 🔴 **BOOT BLOCK** | Board has **no 24-pin ATX**. Use bundled 24-to-4 adapter → `ATX4PIN1` + 8-pin EPS → `ATX12V2`. | No power-on. | p.25 §2.9 |
| 🟡 **PERF** | **Single DIMM → DDR4_A2 or DDR4_B2** (not A1/B1). DDR4 daisy-chain: populate far slot first. | Signal integrity issue; may fail memory training. | p.16 §2.5 |
| 🟡 **PERF** | **Dual DIMM → DDR4_A2 + DDR4_B2** for dual-channel. | Runs single-channel; half memory bandwidth. | p.16 §2.5 |
| 🟡 **PERF CAP** | M2_1 and PCIE7 are PCIe 4.0 max. No PCIe 5.0 on this platform. | PCIe 5.0 cards negotiate down to 4.0. Not damaging. | p.2 §1.2 |
| 🟡 **PERF CAP** | OCuLink ports (OCU1, OCU2) are **PCIe 3.0 x4** or **4× SATA 6Gb/s**. Not PCIe 4.0. | PCIe 4.0 NVMe via OCuLink negotiates down to 3.0. | p.2 §1.2 |
| 🟢 **TIMING** | BMC (AST2500) takes **30–60 s** to boot after PSU power. Heartbeat LED blinks when ready. | Mistaking slow BMC boot for dead board. | General |
| 🟢 **DISPLAY** | **VGA output comes from the BMC**, not the CPU. Xeon E-2314 has no iGPU. | Expecting HDMI/DP from CPU. | p.9 §1.6, p.11 §1.7 |
| 🟢 **DEFAULTS** | IPMI LAN: DHCP by default. Login `admin / admin`. Change immediately. | Default creds on exposed BMC. | p.55 §3.4.1 |
| 🟢 **BIFURCATION** | PCIE7 supports x16 / x8x8 / x8x4x4 only. **Max 3 GPUs without PCIe switch.** PEX88048 required for 4 GPUs. | Assuming 4 GPUs work without the switch. | p.18 §2.6 |
| 🟢 **HOT PLUG** | PCIE7 Hot Plug Disabled; OCU1+OCU2 Hot Plug Enabled. OCU1 Mode must be **PCIe** (not SATA) for NVMe to enumerate. | SN8100 invisible if OCU1 Mode left at SATA default. | Advanced → PCH Storage Configuration |
| 🟢 **HDLED** | HDLED on PANEL1 is PCH-driven. M2_1 is CPU-direct → NVMe activity on M2_1 likely does **not** blink the front HDD LED. | Mistaking dark HDLED for a wiring fault. | p.11 block diagram |
| 🟢 **MEMORY MAX** | Max 32 GB per SODIMM × 4 slots = **128 GB**. Max 2933 MHz at 1DPC; **2133 MHz at 2DPC (all 4 slots filled)**. | Expecting higher speeds with 4 DIMMs. | p.2 §1.2 |

**Legend:** 💀 DAMAGE — permanent hardware loss · 🔴 BOOT BLOCK — won't POST · 🟡 PERF — reduced capability · 🟢 INFO — prevents confusion

**PCIe switch risks:**
1. ~~PEX88048 + GPU enumeration: untested with workstation GPUs~~ — **VALIDATED 2026-05-30**: RTX A4000 enumerated cleanly via PEX8749 → JHHP1B path, NVIDIA driver loaded, no AER errors
2. Resizable BAR: PCIe switch may block large BAR; most inference frameworks work without it
3. Signal integrity: long path (mobo → switch → cable → backplane → GPU) may degrade to Gen3; still sufficient for inference — link stable on A4000
4. ~~No community validation: this exact combo is untested~~ — **path confirmed working**

---

## Order Log

| Date | Item | Order | Amount |
|------|------|-------|--------|
| 2026-04-07 | ASRock Rack E3C256D4I-2T | octo24.com #105904 | €591.89 |
| 2026-04-07 | Intel Xeon E-2314 | Jacob Elektronik JE12860878 | €292.18 |
| 2026-04-07 | Jonsbo CR-1400 EVO | Caseking CKDEB2C-10341119 | €27.89 |
| 2026-04-07 | Phanteks Enthoo Pro 2 TG | Caseking CKDEB2C-10341115 | €174.89 |
| 2026-04-07 | be quiet! DPP13 1600W | Mindfactory #20279081 | €392.80 |
| 2026-04-18 | Samsung 990 Pro 4TB (OCuLink model cache) | Amazon | €499.00 |

**Infrastructure total (excl. GPUs, switch, cables, 990 Pro):** ~€1,479

### Cost summary

| Category | Generic switch | HighPoint switch |
|----------|---------------|-----------------|
| Mobo + CPU + cooler | €929 | €929 |
| Case + PSU | €542 | €542 |
| PCIe expansion (switch + backplanes + cables) | €383 | €813 |
| **Infrastructure total** | **~€1,854** | **~€2,284** |

---

## Performance Estimates

### 4× RTX PRO 6000 Max-Q (96GB GDDR7, 1.8 TB/s each)

| Model | Quant | Size | GPUs needed | Est. tok/s (decode) |
|-------|-------|------|-------------|---------------------|
| Qwen3.5-397B-A17B (MoE, 17B active) | Q4 | 222 GB | 4 (162 GB spare) | ~130–150 |
| DeepSeek-V3.2 (MoE, 37B active) | Q3 | ~285 GB | 4 | ~80–100 |
| Llama 70B | Q4 | 38 GB | 1 | ~33 |
| Llama 70B | FP16 | 140 GB | 2 | ~24 |
| Llama 405B | Q4 | 220 GB | 3–4 | ~16 |

**Why MoE wins on this hardware:** MoE models only read active parameters per token (17B of 397B for Qwen3.5). At Q4: ~9.4 GB read per token vs 38 GB for a dense 70B. A 397B MoE model runs ~4× faster than a 70B dense model.

---

## Key Links

- ASRock Rack E3C256D4I-2T: https://www.asrockrack.com/general/productdetail.asp?Model=E3C256D4I-2T
- Geizhals listing: https://geizhals.de/asrock-rack-e3c256d4i-2t-a2645752.html
- RTX PRO 6000 Max-Q: https://www.nvidia.com/en-us/products/workstations/professional-desktop-gpus/rtx-pro-6000-max-q/
- RTX PRO 6000 Max-Q datasheet: https://www.nvidia.com/content/dam/en-zz/Solutions/products/workstations/professional-desktop-gpus/rtx-pro-6000-max-q/workstation-datasheet-blackwell-rtx-pro-6000-max-q-nvidia-3519233.pdf
- HighPoint Rocket 1528D: https://www.highpoint-tech.com/product-page/rocket-1528d
- HighPoint at SCAN UK: https://www.scan.co.uk/products/highpoint-rocket-1528d-nvme-switch-adapter-8x-u2-u3-nvme-ssds-via-4x-slimsas-sff-8654-ports-pcie-gen
- JMT JHHP1B backplane: https://www.amazon.com/JMT-SlimSAS-PCIe4-0-Adapter-Graphics/dp/B0CW1RRH9Q
- Qwen3.5-397B-A17B: https://huggingface.co/Qwen/Qwen3.5-397B-A17B
- Samsung M471A2K43BB1-CPB: https://semiconductor.samsung.com/dram/module/sodimm/m471a2k43bb1-cpb/
- ICY DOCK MB111VP-B: https://global.icydock.com/product_350.html
- ICY DOCK MB705M2P-B: https://global.icydock.com/product_172.html
- ICY DOCK MB705M2P-B review (ServeTheHome): https://www.servethehome.com/icy-dock-ezconvert-mb705m2p-b-review-m-2-to-u-2-nvme-ssd-adapter/
- CableCC SF-056: https://www.cablecc.com/oculink-sff8612-sff8611-to-pcie-pciexpress-16x-4x-adapter-with-sata-power-port-for-mainboard-graphics-card-p-5167.html
- EK PCI Bracket Pass-Through: https://www.amazon.de/dp/B0CKZJ82PM
- StarTech S25SLOTR (passive hot-swap bracket): https://www.amazon.de/StarTech-com-5-Zoll-SATA-Wechsellrahmen-f%C3%BCr-PC-Erweiterungssteckplatz/dp/B002MWDRD6
- Supermicro CBL-SAST-0933 (OCuLink to 4× SATA): https://store.supermicro.com/us_en/supermicro-50cm-oculink-to-4-sata-cable-cbl-sast-0933.html
- Future EPYC board — ASRock Rack GENOAD8X-2T/BCM: https://www.asrockrack.com/general/productdetail.asp?Model=GENOAD8X-2T%2FBCM
