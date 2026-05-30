---
name: LGA1200 PCIe Bifurcation Ceiling
description: LGA1200 platform limits, bifurcation riser options, and why PEX88048 is the correct GPU fan-out solution
type: reference
originSessionId: 742e51d0-dbf3-40f5-8c69-aaf265a29e95
---
## Platform ceiling: LGA1200 bifurcation max is x8x8 / x8x4x4

No LGA1200 CPU (including higher-end E-2336, E-2378, E-2388G) supports x4x4x4x4. This is a CPU PCIe controller limitation, not a BIOS setting. All Xeon E-2300 series share the same ceiling.

x4x4x4x4 requires AMD AM4 (X570/B550), AM5 (X670E), Intel Z690/Z790, or Xeon Scalable (LGA4677) — none of which exist on a server board that also accepts DDR4 SODIMMs. The SODIMM constraint locks the build into LGA1200.

**The PEX88048 switch is the correct solution** — it provides the downstream fan-out (x8x8x8x8 or x4x4x4x4 per GPU) that the CPU platform cannot do natively. This was a known consequence of the SODIMM-first constraint, not a gap in CPU choice.

## E-2314 CPU selection rationale

Recommended in an earlier session for:
- Cheapest Xeon E-2300 for LGA1200
- Same 20 PCIe 4.0 lanes as pricier E-2300s
- 65W TDP — helps stay under 1.5 kW apartment budget
- CPU is not the LLM inference bottleneck (GPUs do all the work)
- No iGPU needed (dedicated GPUs)

A step up (E-2336, 6C/12T, 65W) would cost ~€50-80 more but has identical bifurcation limitations.

## Bifurcation riser option (if needed alongside PEX88048)

To share PCIE7 between PEX88048 (GPUs) and MB111VP-B (SN8100), a dumb bifurcation riser splitting x16→2×x8 works with BIOS set to x8x8:

- **JMT PCIe 4.0 x16→2×x8**: [Amazon.de B0BHNPKCL5](https://www.amazon.de/JMT-Erweiterungskarte-PCIe-Bifurcation-Abstand-Netzteil-SATA/dp/B0BHNPKCL5) ~€25-40
- **XT-XINTE PCIe 4.0 x16→2×x8**: [Amazon.de B0B779K216](https://www.amazon.de/-/en/XT-XINTE-Expansion-Split-Bifurcation-Supply/dp/B0B779K216) ~€25-40

Both are identical hardware — no onboard switch chip, rely on mobo BIOS bifurcation, two standard PCIe x8 physical slots, require CPU 4-pin aux power.

Trade-off: PEX88048 gets x8 upstream (instead of x16), halving host↔GPU bandwidth. Acceptable for inference (weights load once into VRAM).

TECKEEN PH43 x8+x4+x4 variant: NOT suitable — the x4 outputs are M.2, not standard PCIe slots; MB111VP-B needs a standard PCIe slot.
