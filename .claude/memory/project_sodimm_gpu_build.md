---
name: SODIMM GPU Build
description: Local LLM inference build — 4x RTX PRO 6000 Max-Q via PCIe switch on ASRock E3C256D4I-2T with DDR4 SODIMMs
type: project
originSessionId: 742e51d0-dbf3-40f5-8c69-aaf265a29e95
---
Goal: maximize LLM inference tok/s (target: Qwen3.5-397B-A17B Q4 at ~130 tok/s) while reusing 4x Samsung M471A2K43BB1-CPB (16GB DDR4-2133 SODIMM, non-ECC, 1.2V).

**Why:** DDR5 is expensive; system RAM barely matters for GPU inference — the model lives in VRAM. Reusing existing SODIMMs saves ~EUR 500+.

**Silence requirement:** Home office build in Berlin apartment — quiet operation is a first-class goal alongside inference performance. Full custom water loop planned.

**Architecture:**
- Mobo: ASRock Rack E3C256D4I-2T (Mini-ITX, LGA1200, 4x SODIMM, PCIe 4.0 x16)
- CPU: Intel Xeon E-2314 (4C/4T, cheapest LGA1200 — same 20 PCIe 4.0 lanes as E-2388G)
- GPU: 4x NVIDIA RTX PRO 6000 Blackwell Max-Q (96GB GDDR7, 1.8 TB/s, 300W each)
- PCIe expansion: HighPoint Rocket 1528D or generic PEX88048 switch card (no BIOS bifurcation needed) → 4x SlimSAS 8i → 2x JMT JHHP1B backplanes (2 GPU slots each, PCIe 4.0 x8 per GPU)
- Case: Phanteks Enthoo Pro 2 (dual PSU, large radiator capacity: top 420mm + front 420mm + bottom 360mm)
- Cooling: Full custom water loop — CPU + 4× GPU + PEX88048 chip
- GPU water blocks: Bykski N-RTXPRO6000-SR (Server Edition block, correct for Max-Q PCB) ~€280/each → €1,120 for 4; Alphacool ES Server Edition ~€400/each as alternative
- Total VRAM: 384 GB → fits Qwen3.5-397B-A17B Q4 (222 GB) with 162 GB spare for KV cache

**Build status (as of 2026-04-24):**
- [INSTALLED + BENCH-TESTED ✓] ASRock Rack E3C256D4I-2T — POST passes; baseline captured in `Stage 1 - Memory Reuse/FIRST_BOOT_BASELINE.md`. Firmware: BMC 3.02.00, BIOS 3.04, SPS 6.0.3.604.
- [INSTALLED + BENCH-TESTED ✓] Intel Xeon E-2314 — detected, idles at 0.91 V VCORE / 26°C with Jonsbo CR-1400 EVO
- [INSTALLED + BENCH-TESTED ✓] 2x Samsung M471A2K43BB1-CPB in DDR4_A2+B2 — 32GB total, dual-channel at 2133 MHz (added 2026-04-26)
- [INSTALLED + RUNNING ✓] Samsung 9100 PRO 8TB (nvme1n1) in M2_1 — **Manjaro KDE installed 2026-04-18**; btrfs root; 34.9°C idle SMART temp; 5 POH
- [INSTALLED + TESTED ✓] WD_Black SN8100 8TB (nvme0n1) — delivered 2026-04-22, installed + SMART verified (26.9°C, 1 POH, disk OK); currently unformatted; staging in hot-swap bay or direct PCIe slot
- [INSTALLED ✓] ICY DOCK MB111VP-B hot-swap tray + MB705M2P-B M.2→U.2 converter + CableCC SF-056 OCuLink→PCIe adapter — delivered 2026-04-22/23 (CableCC at neighbor Suri). Eligible for return until 2026-05-07.
- [INSTALLED + WIRED] be quiet! Dark Power Pro 13 1600W PSU; case Phanteks Enthoo Pro 2 TG; CPU cooler Jonsbo CR-1400 EVO
- [ARRIVING TODAY 2026-04-24] RJ45 flat door/window feed-through cable (Good Connections, €10.70) — for permanent ethernet routing
- [DELIVERED 2026-04-20] Klein Tools VDV226-107 RJ45 crimper
- [PENDING — MISSING] SFF-8612 ↔ SFF-8612 OCuLink cable ~50cm (~€15) — required to connect MB111VP-B via OCU1; without it MB111VP-B must sit in PCIE7
- [PENDING] Add SODIMMs 3-4 (4-DIMM at 2133 MHz, 64GB total)
- [PENDING] PEX88048 switch card — [eBay.de #146916609438](https://www.ebay.de/itm/146916609438) ~€210; hardware-switchable modes: Mode 1=2×x16, **Mode 2=4×x8** ← use this for 4 GPUs, Mode 3=8×x4; KALEA-INFORMATIQUE Amazon.de €589.90 hardcoded x4 stock (avoid); HighPoint Rocket 1528D ~€650 (overkill)
- [PENDING] 2x JMT JHHP1B backplanes — Amazon, ~€31.25 each
- [PENDING] 4x SFF-8654 8i cables (50cm) — Amazon, ~€25 each
- [OWNED] 3 remaining Samsung M471A2K43BB1-CPB 16GB DDR4-2133 SODIMM (1 already installed)
- [PENDING — gating] First test GPU (cheap RTX 3060/3070) → verify PEX88048 enumerates a single GPU before committing to 4× RTX PRO 6000 Max-Q purchase (~€42,540)

**Networking (as of 2026-05-05, switched to Linksys as intermediate router):**
- Topology: Internet → FritzBox → Linksys WAN → Linksys LAN → crucible + laptop enp59s0
- Laptop WiFi (wlp62s0): 192.168.178.25 via FritzBox (internet)
- Linksys subnet: 192.168.1.0/24 (DHCP reservations set but Linksys is flaky — loses DHCP after power cycle)
- BMC: `192.168.1.100` (MAC `9C:6B:00:47:28:34`) — only reachable when PSU plugged in + rear switch ON
- Crucible host: `192.168.1.102` — SSH via `ssh crucible` (~/.ssh/config HostName = 192.168.1.102)
- **Static IPs needed**: Linksys consumer firmware unreliable; set static IPs on crucible interfaces to stop depending on DHCP
- BMC has no hostname in DHCP by default (ASRock Rack ASPEED AST2500 doesn't send hostname)

**Build runtime references:**
- Network/IPMI: BMC at `10.42.0.24` (DHCP via laptop shared, MAC `9C:6B:00:47:28:34`), login admin/admin (change immediately)
- Risk registers: `RISKS.md` (project-wide), `Stage 1 - Memory Reuse/RISKS.md` (board-specific)
- Manual (PDF→MD): `Stage 1 - Memory Reuse/E3C256D4I-2T.md` (3,014 lines, grep-able)
- BMC reference: `Stage 1 - Memory Reuse/BMC.md`

**Storage layout (as of 2026-05-05):**
- M2_1 (only M.2 slot): Samsung 9100 PRO 8TB — boot drive, cannot be displaced
- PCIE7: WD_BLACK SN8100 8TB via MB111VP-B + MB705M2P-B — temporary; MUST vacate when PEX88048 arrives
- OCuLink path for SN8100: FAILED (link training failure — "card present, no link"). Diagnostic log:
  - ✓ BIOS OCuLink ports confirmed set to PCIe mode (not SATA) before test
  - ✓ MB111VP-B (hot-swap tray) works correctly in PCIE7 direct slot
  - ✓ SN8100 drive itself is good (verified in direct PCIe slot)
  - ✗ MB111VP-B failed when connected via OCuLink-to-PCIe adapter card (cablecc SF-056) plugged into OCuLink port
  - ❓ Unknown which component is broken: the OCuLink cable, the SF-056 adapter card, or both
  - SF-056 return window: 2026-05-07 — DO NOT return before testing with a known-good OCuLink PCIe cable
  - Next test: replace the OCuLink cable first (cheapest, ~€15). If still fails → SF-056 adapter is suspect
- Enthoo Pro 2 has 1× 5.25" bay built-in (secured by 3 PSU screws from top); optional PH-ODDBAY_01 adds a second

**Known corrections:**
- Supermicro X11SDW-TP13F uses RDIMM — incompatible with these SODIMMs
- ASRock E3C256D4I-2T has 4x SODIMM (not 2), max 128GB, Non-ECC supported (confirmed via Geizhals)
- PEX88048 PCIe switch eliminates need for BIOS bifurcation support
- LGA1200 bifurcation ceiling: x8x8 / x8x4x4 only — no x4x4x4x4 on ANY LGA1200 CPU (see reference_lga1200_bifurcation.md)
- E3C256D4I-2T has only ONE M.2 slot (M2_1) — no room for SN8100 in M.2
- Mobo manual path: `Plan/Stage 1 - SODIMM Constrained/E3C256D4I-2T.md`
