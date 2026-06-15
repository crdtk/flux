# Crucible — DDR4 SODIMM LLM Inference Rig

A budget local LLM inference workstation built during the 2026 RAM crisis.
Reuses legacy DDR4 SODIMMs (€0 cost) on a Mini-ITX server board with PCIe
switch fanout to 4× RTX PRO 6000 Blackwell Max-Q, targeting Qwen3.5-397B-A17B
at ~120-150 tok/s in a Berlin apartment under 1.5 kW.

The crisis is the heat. The build is what comes out of the crucible.

## Primary References
Consult before answering any hardware question about this build. **Grep these FIRST**, before falling back on generic knowledge.

- **System risk register** (severity-sorted, all subsystems): `RISKS.md`
- **Motherboard manual** (full text, 3,014 lines): `References/Motherboard/E3C256D4I-2T.md`

Severity convention across all RISKS files: 💀 DAMAGE · 🔴 BLOCKER · 🟡 PERF/CAP · 🟢 INFO

## Component References
Check these before asking about specs or compatibility of owned hardware.

- **Motherboard PDF**: `References/Motherboard/E3C256D4I-2T.pdf`
- **Case manual**: `References/Case/ENTHOO-PRO-II/Enthoo_Pro2_Manual_v1.1.pdf`
- **WD_BLACK SN8100 datasheet**: `References/Storage/SN8100/WD_Black_SN8100_Datasheet.pdf`
- **ICY DOCK MB111VP-B** (U.2 PCIe bracket adapter): `References/Storage/MB111VP-B/MB111VP_B_Manual.pdf`
- **ICY DOCK MB705M2P-B** (M.2→U.2 converter, owned): `References/Storage/MB705M2P-B/MB705M2P-B_Manual.pdf`

## Response Style
- Minimal verbosity. Lead with facts, skip preamble.
- Minimal tables — only when comparing specs side-by-side.
- Always include clickable URLs to verify claims.
- Always search for options online (Geizhals, Amazon.de, retailer sites) when recommending components — never guess prices or availability.
- Do not warn about power/cooling/space unless asked — the Phanteks Enthoo Pro 2 with dual PSU handles it.

## Workflow
- **Never give raw bash commands as solutions.** Every repeatable action must be a Makefile target. If a solution requires shell commands, write the target first, then tell the user to run `make <target>`.

## Project Scope
Local LLM inference **workstation** reusing existing DDR4 SODIMMs to offset high memory prices.
User will sit in front of this machine with a keyboard and multiple monitors — **not headless**.
A desktop environment is required. OS choice should favor full desktop (Kubuntu/Arch KDE/etc.)
over Ubuntu Server.

**Silence is a first-class requirement.** This is a home office build in a Berlin apartment.
All cooling decisions must prioritize quiet operation:
- Full custom water loop planned for CPU, all 4 GPUs, and PEX88048 switch chip
- GPU water blocks: Bykski N-RTXPRO6000-SR (Server Edition, ~€280 each) — Max-Q shares PCB with Server Edition
- PSU already chosen for silence: be quiet! Dark Power Pro 13 1600W
- Blower coolers on RTX PRO 6000 Max-Q will be replaced by water blocks — eliminates the loudest noise source

### Fixed Components
- **RAM**: 2x Samsung M471A2K43BB1-CPB — 16GB DDR4-2133 SODIMM, non-ECC, unbuffered, dual-rank, 1.2V = 32GB (2 of the original 4 SODIMMs; the other 2 remain in ServalWS)
- **Motherboard**: ASRock Rack E3C256D4I-2T (ordered 2026-04-07)
- **CPU**: Intel Xeon E-2314 (4C/4T, LGA1200, 20 PCIe 4.0 lanes)
- **GPU (active, bench)**: NVIDIA RTX A4000 (16GB GDDR6, 140W) — current development GPU, behind PLX PEX 8749 bench switch; link training at Gen1 x4, reseating in progress
- **GPU (target, not purchased)**: 4x NVIDIA RTX PRO 6000 Blackwell Max-Q (96GB GDDR7, 1.8 TB/s, 300W, blower) — deferred until PCIe switch path is validated
- **PCIe Slot (PCIE7)**: Currently staging WD_BLACK SN8100 in ICY DOCK MB111VP-B (Reserved for PEX88048 Switch)
- **OCuLink Ports**: Target home for WD_BLACK storage via Tekram TK-2U11 + MB705M2P-B M.2→U.2 converter
- **Storage (Boot)**: Samsung 9100 PRO 8TB (Serial: S7YHNJ0YC07013D)
- **Storage (Models)**: WD_BLACK SN8100 8TB (M.2, currently in ICY DOCK MB111VP-B in PCIE7)
- **Case**: Phanteks Enthoo Pro 2 (full tower, dual PSU mount)

### Key Constraint
The motherboard must accept DDR4 SODIMMs (260-pin, unbuffered, non-ECC) AND provide enough PCIe lanes for 4 GPUs via PCIe switch. This is a very narrow niche — most multi-GPU boards use RDIMM/UDIMM.

### Known Corrections
- Supermicro X11SDW-TP13F series uses RDIMM — **incompatible** with these SODIMMs.
- ASRock Rack E3C256D4I-2T has **4x SODIMM slots** (not 2), max 128GB Non-ECC supported, PCIe 4.0 x16 with bifurcation (x8x8 or x8x4x4 only — no x4x4x4x4), plus **1× M.2 PCIe 4.0 x4** (M2_1, taken by boot drive).
- LGA1200 platform ceiling: no CPU in this family supports x4x4x4x4 bifurcation — PEX88048 switch provides the GPU fan-out the CPU cannot.
- PEX88048 PCIe switch (HighPoint Rocket 1528D or generic) eliminates need for BIOS bifurcation — each GPU gets PCIe 4.0 x8 via JMT JHHP1B backplanes.
- Archive/ASRock WRX90 WS EVO rejected: uses RDIMM, incompatible with SODIMMs.
