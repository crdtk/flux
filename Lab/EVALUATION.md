# Crucible — Folder Evaluation

## Folder Structure (Reorganized 2026-04-11 by stage)

```
/home/m/Code/hardware/
├── Stage 1 - Memory Reuse/       ← Active build (DDR4 SODIMM workaround)
│   └── ASRock Rack E3C256D4I-2T/
│       └── ASRock Rack E3C256D4I-2T.md
├── Stage 2 - Post-Crisis/        ← Future: DDR5 RDIMM when prices drop
│   └── EPYC Genoa/
│       └── EPYC Genoa Workstation Build.md
├── Archive/                       ← Eliminated options
│   └── ASRock WRX90 WS EVO/
│       └── ASRock WRX90 WS EVO.md
├── References/                    ← Semantic categories (Backup/, Bootstrap/, Case/, Processor/)
├── shared/                        ← Legacy (Workstation Build TSV, WRX90 BOM)
├── CLAUDE.md                      ← Project rules and scope
├── EVALUATION.md                  ← This file
├── ARTICLE.md                     ← Summary article
└── Makefile                       ← Ventoy USB setup
```

---

## Stage 1 - Memory Reuse: ASRock Rack E3C256D4I-2T (ACTIVE — Bench-test passed 2026-04-12)

**Status:** Bench POST verified — CPU + 1 SODIMM + M.2 NVMe + BMC all functional. See `Stage 1 - Memory Reuse/FIRST_BOOT_BASELINE.md` for the known-good baseline. PEX88048 switch + GPU bring-up is the next risk gate.
**Total spent:** ~€1,479 (excluding GPUs)
**Approach:** Cheap mini-ITX server board reusing existing DDR4 SODIMMs, scaling 2→4→8 GPUs via PCIe switch
**Key reference docs:**
- [`Stage 1 - Memory Reuse/E3C256D4I-2T.md`](Stage%201%20-%20Memory%20Reuse/E3C256D4I-2T.md) — 3,014-line motherboard manual (PDF→Markdown)
- [`Stage 1 - Memory Reuse/RISKS.md`](Stage%201%20-%20Memory%20Reuse/RISKS.md) — board-specific gotcha register
- [`Stage 1 - Memory Reuse/BMC.md`](Stage%201%20-%20Memory%20Reuse/BMC.md) — IPMI access, default creds, web UI navigation
- [`Stage 1 - Memory Reuse/FIRST_BOOT_BASELINE.md`](Stage%201%20-%20Memory%20Reuse/FIRST_BOOT_BASELINE.md) — sensor + memory + PCIe + storage snapshot at first POST
- [`RISKS.md`](RISKS.md) — system-wide risk register (power envelope, GPU, switch, etc.)

### Strengths
- **Reuses existing 4× Samsung DDR4 SODIMMs** — saves ~€500-2,500 vs DDR5 ECC RDIMM at crisis prices
- Cheapest motherboard + CPU combo (~€884)
- 4× SODIMM slot (rare for server boards with PCIe expansion)
- IPMI/BMC for headless management
- 2× 10GbE onboard
- Already paid for: mobo, CPU, PSU, case, cooler — committed path

### Weaknesses
- **Mini-ITX = 1 PCIe slot** — requires PEX88048 switch + JMT JHHP1B backplanes
- **20 PCIe 4.0 lanes** (not 5.0) — bandwidth bottleneck for 4 GPUs sharing
- **Untested combo** — no community validation of E3C256D4I-2T + PEX88048 + RTX PRO 6000 Max-Q
- LGA1200 = end-of-life Intel platform, no upgrade path
- 65W CPU is weak for prompt processing (mitigated: GPU-bound workload)
- octo24 currently shows "out of stock" — shipment status uncertain (email sent)

### Build Risk: HIGH
- Every junction (mobo → switch card → SlimSAS cable → backplane → GPU) is unproven for this exact stack
- Mitigation: bench-test mobo + CPU + RAM first (this week), then add 1 cheap GPU before committing to RTX PRO 6000 purchase

### Cost vs Capability
- **~€1,500 infrastructure + GPUs** for up to 8× single-slot watercooled GPUs
- Best $/GB-VRAM if it works
- Worst $/GB-VRAM if it doesn't

---

## Archive: ASRock WRX90 WS EVO (RESEARCHED, ELIMINATED)

**Status:** Documentation only, not ordered
**Approach:** Buy a pre-built Threadripper PRO workstation from MIFCOM (Munich) to avoid DDR5 ECC sourcing problems

### Strengths
- **Builder sources RAM** — avoids the DDR5 ECC RDIMM crisis (172% price increase)
- **Pre-validated** by professional system integrator
- **Builder warranty** — single point of contact
- 7× PCIe 5.0 x16 slots — full bandwidth per GPU
- AMD platform (TR PRO 9985WX)
- German vendor (MIFCOM, Munich)

### Weaknesses
- **CRITICAL: PCIe Gen1 bug on multi-GPU Blackwell** (per EPYC Genoa doc)
  - Dual RTX PRO 6000 Blackwell stuck at PCIe Gen 1 (2.5 GT/s)
  - Xid 79 "GPU fell off the bus" errors
  - Affects ASUS and ASRock WRX90 boards
  - Root cause: AMD AGESA firmware, no fix ETA
  - Sources: level1techs forum threads
- **~€39,849 for dual RTX PRO 6000 config** — 25× more expensive than DIY
- 8 channel DDR5 (vs 12 on EPYC Genoa)
- 2TB max RAM (vs 6TB on EPYC)

### Build Risk: HIGH (firmware bug)
**Single GPU works fine. Multi-GPU is broken until AMD fixes AGESA.** Not viable for the user's 2-7 GPU plans.

### Status
**Eliminated by EPYC Genoa research** — same price tier, EPYC has more channels and no firmware bug.

---

## Stage 2 - Post-Crisis: EPYC Genoa (BACKUP PLAN / FUTURE)

**Status:** Documentation complete, components not ordered
**Motherboard:** ASRock Rack GENOAD8X-2T/BCM (~€800-1,227)
**Approach:** Server-grade EPYC 9004/9005 with 8 PCIe 5.0 slots, scale 1→7 GPUs over time

### Strengths
- **No WRX90 PCIe Gen1 bug** — server platform, NVIDIA validates first
- **12-channel DDR5** = ~460 GB/s bandwidth (vs 307 on WRX90)
- **8 PCIe 5.0 x16 slots** — direct GPU mounting, no switch card needed
- **6TB max RAM** (future-proof)
- Cheapest 16-core CPU at ~€500-700 (EPYC 9124)
- Validated by [YANGCOM Korea build](https://www.youtube.com/watch?v=Zy-x8bCoOAQ) on same mobo + Phanteks Enthoo Pro 2
- Native PCIe 5.0 x16 to every GPU = best inference performance
- 7-GPU watercool path documented

### Weaknesses
- **DDR5 ECC RDIMM crisis** — ~€2,500-5,000 for 128GB (vs €0 reusing existing SODIMMs)
- **EEB form factor** — bigger case requirement
- ~€16,000-19,000 Phase 1 (single GPU) vs ~€1,500 for E3C256D4I-2T infrastructure
- No DDR4 SODIMM reuse possible

### Build Risk: LOW
- Proven platform (server-grade)
- Reference build exists (YANGCOM Korea)
- Native PCIe 5.0 to every slot, no switches/adapters

### Status: BACKUP PLAN
If the E3C256D4I-2T build fails (PEX88048 doesn't enumerate GPUs, signal integrity issues, etc.), this is the fallback. The Phanteks Enthoo Pro 2 and PSU are reusable. CPU + mobo + RAM would need to be replaced at higher cost.

---

## Decision Tree

```
Current path: ASRock Rack E3C256D4I-2T (€1,479 spent)
│
├── If POST + GPU enumeration works → continue, scale to 4-8 GPUs
│
├── If PEX88048 doesn't enumerate GPUs:
│   ├── Try HighPoint Rocket 1528D (better firmware) — €650
│   └── If still fails → fall back to EPYC Genoa
│
└── If signal integrity issues (PCIe drops to Gen3/Gen2):
    └── Acceptable if tok/s targets met; otherwise EPYC Genoa
```

## Reusable Across Builds

These survive a switch from E3C256D4I-2T to EPYC Genoa:
- **Phanteks Enthoo Pro 2 TG** (€175)
- **be quiet! DPP13 1600W** (€393)
- **Jonsbo CR-1400 EVO** — only if EPYC uses LGA1200/115x compatible mounting (it doesn't, SP5 socket)
- 4× Samsung SODIMMs — useless on EPYC (DDR5 only)
- **Xeon E-2314** — useless on EPYC (LGA1200 only)

**Sunk cost if switching to EPYC: ~€887** (mobo + CPU + cooler + RAM that doesn't transfer)

---

## What's Missing

### For `Stage 1 - Memory Reuse/`
- [x] **Bench test results (post-arrival)** — completed 2026-04-12, captured in `FIRST_BOOT_BASELINE.md`. POST passes; CPU detected, DIMM trains at DDR4-2133, NVMe enumerated, BMC fully functional, all voltage rails within 2% of nominal, idle temps healthy (CPU 26°C, PCH 51°C, MB 32°C).
- [x] **Memory QVL verification** — Samsung `M471A2K43BB1-CPB` confirmed working in `DDR4_A2` at native 2133 MHz on this board. (Required correct slot — see board RISKS for DDR4 daisy-chain caveat.)
- [x] **Power button wiring resolved** — initial mistake was plugging case bundle into `ITX_AUX_PANEL1` (#11 server aux) instead of `PANEL1` (#12 front panel). Now documented as a BOOT BLOCK in board RISKS.
- [x] **Samsung 9100 PRO 8TB NVMe installed** — enumerated on M.2_1 (CPU-direct PCIe lane), drive firmware `0B2QNXH7`, runs at PCIe 4.0 x4 (platform cap; drive's PCIe 5.0 capability unused on this board).
- [ ] BIOS screenshots (PCIe bifurcation menu, OCuLink mode toggle) — pending entry into BIOS via iKVM
- [ ] PEX88048 switch card purchase decision (HighPoint Rocket 1528D vs generic)
- [ ] First GPU bench-test through the PCIe switch (use cheap test GPU before committing to RTX PRO 6000 Max-Q purchase — highest project risk per RISKS)
- [ ] PCIe enumeration test results with first GPU
- [ ] tok/s benchmarks once running with full GPU complement
- [x] **Storage subsystem expansion** — WD_BLACK SN8100 8TB arrived and verified 2026-04-22. Serial 25437L400188. Health OK. Ready for model weights.
- [ ] BIOS screenshots (PCIe bifurcation menu, OCuLink mode toggle) — pending entry into BIOS via iKVM

### Key Insight: EK PCI Bracket Pass-Through
The [EK PCI Bracket](https://www.amazon.de/dp/B0CKZJ82PM) (~EUR 40) integrates 2x G1/4 ports
+ cable hole in 1 slot. This frees up an entire PCI slot vs the old assumption of 2 slots
for water in/out. Critical for the Phase 3 EPYC migration (7 GPU + 3 hot-swap + water in 11 slots).

### For `Stage 2 - Post-Crisis/EPYC Genoa/`
- [ ] DDR5 ECC RDIMM sourcing strategy (which option won)
- [ ] Final motherboard decision (GENOAD8X-2T/BCM vs alternatives)
- [ ] PSU selection (the EPYC doc still suggests 850W which is undersized for 7 GPUs)
- [ ] Update with Corsair WS3000 3000W PSU as new option
- [ ] EK PCI Bracket Pass-Through integration for 7 GPU + 3 hot-swap layout

### For `Archive/ASRock WRX90 WS EVO/`
- [ ] Mark as DEPRECATED — PCIe Gen1 bug unresolved as of Apr 2026
- [ ] Leave for reference only, do not pursue
