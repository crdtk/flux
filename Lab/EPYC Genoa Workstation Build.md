# EPYC Genoa Workstation Build — Local LLM Inference

## Goal

Run large local LLMs (Kimi-Dev-72B, Qwen3-Coder-480B, DeepSeek-V3.2) at minimum cost in a Berlin apartment. Start with 1 GPU, scale to 3-7 GPUs over time via water cooling.

## Why EPYC Genoa over Threadripper PRO WRX90

| Factor | EPYC 9004 Genoa (SP5) | TR PRO 7000 WRX90 (sTR5) |
|--------|------------------------|---------------------------|
| Multi-GPU Blackwell | Server platform — NVIDIA validates first | **PCIe Gen1 bug, Xid 79 crashes (unresolved as of BIOS 1317, Feb 2026)** |
| DDR5 channels | **12** | 8 |
| DDR5 bandwidth (all populated) | **~460 GB/s** | ~307 GB/s |
| PCIe 5.0 lanes | 128 | 128 |
| Max RAM | **6TB** | 2TB |
| Cheapest 16-core CPU | **EPYC 9124 ~EUR 500-700** | TR PRO 7955WX ~EUR 1,526 |
| coreboot support | Partial (reference boards) | None |
| Water cooling (CPU) | EK-Pro SP5, SilverStone XE360-SP5 | EK, Alphacool (same socket size) |

### WRX90 Blackwell PCIe Issues (as of April 2026)

- Dual RTX PRO 6000 Blackwell on WRX90: PCIe stuck at Gen 1 (2.5GT/s instead of Gen 5)
- Xid 79 "GPU fell off the bus" errors on ASUS WRX90E-SAGE SE + TR PRO 9985WX
- Affects both ASUS and ASRock WRX90 boards
- Root cause: AMD AGESA firmware — only AMD can fix, no ETA
- Sources:
  - https://forum.level1techs.com/t/dual-rtx-pro-6000-blackwell-on-wrx90-pcie-stuck-at-gen-1-anyone-else/242079
  - https://forum.level1techs.com/t/wrx90e-sage-se-tr-pro-9985wx-2x-rtx-pro-6000-blackwell-idle-pcie-dpc-aer-xid-79-gpu-fell-off-the-bus-links-at-gen1-x16/246603

**Single GPU on WRX90 works fine. The bug only affects multi-GPU configurations.**

---

## Motherboard: ASRock Rack GENOAD8X-2T/BCM

- **Form factor:** EEB (12.63" x 13")
- **Socket:** Single SP5 (LGA 6096)
- **CPU support:** AMD EPYC 9005/9004 series
- **RAM:** 8 DIMM slots, DDR5 RDIMM / RDIMM-3DS
- **PCIe slots:** 4x PCIe 5.0/CXL 2.0 x16 + 3x PCIe 5.0 x16 + 1x PCIe 5.0 x8 = **8 slots total**
- **Networking:** Dual 10GbE LAN, BMC/IPMI
- **Price:** ~EUR 800
- **Review:** https://www.servethehome.com/asrock-rack-genoad8x-2t-bcm-review-an-uncomfortably-good-motherboard-amd-epyc-broadcom/

### GPU Capacity

| Cooling | Slot width per GPU | Max GPUs |
|---------|-------------------|----------|
| Air (stock double-slot) | 2 slots | 3-4 |
| **Water (single-slot block)** | **1 slot** | **Up to 7** |

### Reference Build Video

**YANGCOM Korea — 30,000 EPYC + RTX 5090 Workstation Build**
- https://www.youtube.com/watch?v=Zy-x8bCoOAQ
- Uses the **exact same motherboard** (ASRock Rack GENOAD8X-2T/BCM) and **case** (Phanteks Enthoo Pro 2)
- Build specs: AMD EPYC 9634, 512GB DDR5-5600 ECC/REG (8x 64GB Samsung), 4x RTX 5090 32GB, 2x Samsung 990 PRO 4TB, 2x 2000W PSU
- Demonstrates 4x double-width air-cooled GPUs fitting in this board + case combo
- Confirms Phanteks Enthoo Pro 2 has clearance for multi-GPU EEB builds
- Note: uses RTX 5090 (consumer) not RTX PRO 6000 (professional) — different GPU but same physical PCIe form factor and case/board compatibility

---

## GPU: NVIDIA RTX PRO 6000 Blackwell Max-Q

- **VRAM:** 96GB GDDR7
- **TDP:** 300W (vs 600W full WS edition)
- **Interface:** PCIe 5.0 x16
- **Price:** EUR 10,635 (Conrad Electronic, 50 units in stock as of Apr 2026)
- **Conrad URL:** Part# 900-5G153-2200-000, EAN 8592978659561
- **Why Max-Q over WS edition:**
  - Half the power (300W vs 600W) — critical for apartment use
  - Same 96GB VRAM
  - Easier to water cool (single PCB vs multi-PCB on WS edition)
  - ~20% less compute performance — acceptable for inference

### Water Cooling the Max-Q

Confirmed working by r/BlackwellPerformance community member (u/schenkcigars):

| Water Block | Manufacturer | SKU | Result |
|-------------|-------------|-----|--------|
| **HEATKILLER INOX Pro for RTX PRO 6000 Blackwell** | Watercool.de (Germany) | 15689 (GTIN: 4251312607500) | **Working, single-slot** |
| Optimus PC GPU Block | Optimus | — | Also reported working |

- Disassembly described as "really smooth"
- Max-Q preferred over WS edition due to simpler single-PCB design
- **Caution:** Removing cooler likely voids NVIDIA warranty
- Source: https://www.reddit.com/r/BlackwellPerformance/

**Alternative: Air cooling is fine for up to 4 cards.** One user runs 4x air-cooled Max-Q in a Corsair 7000D at <75C. Water cooling is needed for 5+ cards or quiet apartment use.

---

## CPU: AMD EPYC 9124 (or 9224)

- **Cores:** 16C/32T (9124) or 24C/48T (9224)
- **TDP:** 200W
- **Why cheapest is fine:** LLM inference is GPU-bound. CPU handles model loading, tokenization, and orchestration — 16 cores is plenty.
- **Price:** ~EUR 500-700

---

## RAM: 128GB (2x 64GB) DDR5-4800 ECC RDIMM

### The DDR5 ECC RDIMM Shortage (2026)

Global shortage driven by AI demand. DDR5 RDIMM prices up 172% through 2025. Samsung halted new module orders. Relief not expected before 2027.

- Source: https://en.wikipedia.org/wiki/2024%E2%80%932026_global_memory_supply_shortage
- Source: https://wccftech.com/roundup/memory-crisis/

### Where to Source RAM

**Pre-crisis pricing (reference):**
- Caseking Samsung 32GB DDR5-4800 RDIMM: EUR 161/stick (currently OUT OF STOCK)
- Caseking Samsung 64GB DDR5-4800 RDIMM: EUR 1,100/stick (currently OUT OF STOCK)
- Caseking URL: https://www.caseking.de/en/pc-components/memory/ecc-memory

**Crisis pricing (April 2026):**
- Dell configurator: EUR 2,640/stick for 64GB
- GEKKO Computer (Berlin, refurbished): EUR 1,959/stick — overpriced for used parts
- ESUS IT: EUR 1,432/stick (Hynix 64GB) — but SOLD OUT

**Creative sourcing options (ranked by potential savings):**

1. **Taobao/JD.com via buying agent** (Superbuy, CSSBuy) — Chinese surplus at EUR 190-320/stick. Highest savings, requires due diligence on seller authenticity.
2. **Caseking restock alert** — set notification on MESS-016 (32GB) and MESS-015 (64GB). If Samsung restocks at pre-crisis prices, 2x64GB = EUR 2,200.
3. **Component distributors** — Arrow, Avnet, Mouser, Rutronik, DigiKey have separate allocation from retail. Request B2B quote.
4. **Samsung/Micron B2B direct** — contact enterprise sales divisions.
5. **ITAD companies** — Techbuyer (UK), ETB Technologies (UK), AfB (Germany) handle decommissioned data center RAM.
6. **German government surplus** — VEBEG (vebeg.de), Zoll-Auktion (zoll-auktion.de), university IT departments.
7. **Dell spare parts catalog** — Dell P/N AC631819 or AA810298 (64GB DDR5-4800 RDIMM). Separate inventory from configurator.
8. **Buy from a system builder** — MIFCOM, primeLine, Thomas-Krenn, AIME have distributor relationships. System comes with RAM included.

**Recommended approach:** Order system with minimum RAM. Source RAM independently. Install yourself (5-minute DIMM slot job).

### RAM and LLM Performance

| Scenario | Where model runs | Speed |
|----------|-----------------|-------|
| Model fits in VRAM | GPU (1,792 GB/s per card) | **Fast (~50 tok/s for 72B)** |
| Model spills to RAM | Mix of GPU + system RAM | Slow — RAM bandwidth is 6-50x less than VRAM |
| CPU offloading (MoE) | Experts on CPU, attention on GPU | ~3-6 tok/s depending on RAM channels |

**Rule: Adding a GPU beats adding RAM for speed, every time.** Buy minimum RAM needed for OS + model loading. Don't overspend on RAM channels if the model fits in VRAM.

---

## Water Cooling Components

| Component | Product | Est. Price |
|-----------|---------|------------|
| CPU block | EK-Pro CPU WB SP5 | ~EUR 200-300 |
| CPU AIO (simpler) | SilverStone XE360-SP5 (360mm) | ~EUR 150-200 |
| GPU block (per card) | HEATKILLER INOX Pro (Watercool.de, SKU 15689) | ~EUR 200-300 |
| GPU block (alt) | Optimus PC RTX PRO 6000 Block | ~EUR 200-300 |
| Radiator | 360mm or 420mm per component | ~EUR 50-80 each |
| Pump/res | D5 pump + reservoir combo | ~EUR 150-200 |
| Fittings + tubing | Soft or hard tubing | ~EUR 100-200 |

EK: https://www.ekwb.com/news/ek-pro-line-now-covers-amd-socket-sp5-with-new-cpu-water-blocks/
Watercool.de: German company, ships within EU.

---

## Estimated Build Cost

### Phase 1: Single GPU (start here)

| Component | Selection | Price |
|-----------|-----------|-------|
| CPU | Cheapest EPYC 9004/9005 ≥16C (e.g. 9124 new ~EUR 600, or 9224 refurb ~EUR 129) | ~EUR 129-600 |
| Motherboard | ASRock GENOAD8X-2T/BCM | ~EUR 1,227 |
| GPU | 1x RTX PRO 6000 Max-Q (Conrad) | EUR 10,635 |
| GPU water block | HEATKILLER INOX Pro | ~EUR 250 |
| CPU cooler | SilverStone XE360-SP5 AIO | ~EUR 175 |
| RAM | 128GB (2x 64GB) DDR5 ECC RDIMM | ~EUR 2,500-5,000 |
| Storage | 2TB NVMe Gen4 | ~EUR 200 |
| PSU | 850-1000W 80+ Gold or Titanium | ~EUR 150-250 |
| Case | Phanteks Enthoo Pro 2 Server Edition | ~EUR 160-200 |
| Loop parts (fittings, rad, pump) | Custom loop | ~EUR 400 |
| **Total** | | **~EUR 15,826-18,935** |

### PSU Sizing Guide

PSUs are most efficient at 50-80% load. Buy for your current config, upgrade when adding GPUs.

| GPUs | System Power | PSU Needed | Upgrade Action |
|------|-------------|------------|----------------|
| 1x Max-Q | ~590W | **850-1000W (Phase 1)** | Included |
| 2x Max-Q | ~890W | 1,000-1,200W | Maybe swap PSU |
| 3x Max-Q | ~1,190W | 1,400W | Swap PSU |
| 4x Max-Q | ~1,490W | 1,600W | Swap PSU |
| 5-7x Max-Q | ~1,790-2,390W | Dual PSU setup | Dual PSU adapter + 2nd PSU |

### Expansion Path

| Phase | GPUs | Total VRAM | Added Cost | Models You Can Run |
|-------|------|-----------|------------|-------------------|
| 1 | 1x | 96GB | Included | Kimi-Dev-72B (Q8), Qwen3-Coder-30B |
| 2 | 2x | 192GB | +EUR 10,935 | Llama 405B (Q4) |
| 3 | 3x | 288GB | +EUR 10,935 | **Qwen3-Coder-480B (Q4)** |
| 4 | 4x | 384GB | +EUR 10,935 | DeepSeek-V3.2 (Q4) |
| 5-7 | 5-7x | 480-672GB | +EUR 10,935 each | Future frontier models, higher precision |

GPU cost per card: EUR 10,635 (Conrad) + EUR 250 (water block) = **EUR 10,885 per GPU added.**

---

## LLM Capability Matrix (Single GPU, 96GB VRAM)

| Model | Size | Quantization | VRAM | Fits? | tok/s | Use Case |
|-------|------|-------------|------|-------|-------|----------|
| Qwen3-Coder-30B-A3B | 30B (3B active) | FP16 | ~35GB | Yes | ~60+ | Good coding agent |
| **Kimi-Dev-72B** | 72B | Q4 | ~36GB | **Yes** | **~50-60** | **Strong Claude Code alternative** |
| Kimi-Dev-72B | 72B | Q8 | ~72GB | Yes | ~40 | Better quality |
| Llama 4 70B | 70B | Q4 | ~35GB | Yes | ~50 | General purpose |
| Qwen3-Coder-480B | 480B (35B active) | Q4 | ~276GB | No — need 3 GPUs | — | Best open-source coder |
| DeepSeek-V3.2 | 671B (37B active) | Q4 | ~350GB | No — need 4 GPUs | — | Best open reasoning |

**Kimi-Dev-72B on a single GPU is the best starting point** — tops SWE-bench, patches real codebases autonomously, fits in 96GB with room to spare.

---

## Comparison to Alternatives

| | EPYC DIY (this build) | Dell Precision 7960 | DIY WRX90 |
|---|---|---|---|
| Price (1 GPU, 128GB) | **~EUR 16-19k** | ~EUR 24,600 | ~EUR 16-20k but can't get RAM |
| Multi-GPU Blackwell | **Server platform, likely stable** | **Dell-validated** | **Bugged (PCIe Gen1)** |
| Max GPUs (water cooled) | **7** | 4 | 7 (if PCIe bug fixed) |
| GPU vendor lock | **None — buy from Conrad** | Dell-approved or risk warranty | None |
| RAM sourcing | Must source yourself or use builder | Dell handles it | Must source yourself |
| Warranty | Parts only (or builder warranty) | **Dell ProSupport 3yr on-site** | Parts only |
| Noise (apartment) | Quiet with water cooling | Quiet (tower) | Quiet with water cooling |
| Future GPU expansion cost | **EUR 10,885/GPU (Conrad + block)** | ~EUR 15,306/GPU (Dell) | EUR 10,885/GPU |

---

## Where to Buy (EU)

### Components

| Component | Vendor | URL | Notes |
|-----------|--------|-----|-------|
| RTX PRO 6000 Max-Q | **Conrad Electronic** | Part# 900-5G153-2200-000 | EUR 10,635, 50 in stock, free shipping |
| HEATKILLER GPU block | **Watercool.de** | SKU 15689 | German company |
| GENOAD8X-2T/BCM | smicro.eu | https://smicro.eu/asrock-rack-genoad8x-2t-bcm-1 | EU seller |
| GENOAD8X-2T/BCM | Amazon.de | Search GENOAD8X-2T | |
| EPYC 9124 CPU | Amazon.de / Geizhals.de | Search EPYC 9124 | Compare prices |
| SilverStone XE360-SP5 | Amazon / specialist retailers | | SP5 360mm AIO |
| EK-Pro SP5 block | EKWB.com | https://www.ekwb.com | For custom loop |

### Pre-built (builder handles RAM)

| Builder | Location | URL | Notes |
|---------|----------|-----|-------|
| **AIME** | Germany (Munich area) | https://www.aime.info/en/ | GPU rack servers, EPYC Genoa |
| **Thomas-Krenn** | Germany (Bavaria) | https://www.thomas-krenn.com/en/ | Silent towers, 24hr EU shipping |
| **MIFCOM** | Germany (Munich) | https://www.mifcom.de | Custom builds, water cooling on request |
| **primeLine Solutions** | Germany | https://www.primeline-solutions.com/de/ | Custom workstations, consultation |
| **RECT / Coreto** | Germany | https://www.rect.coreto-europe.com/en/ | EPYC tower configs |
| **Broadberry** | UK, ships EU | https://www.broadberry.com | CyberStation XL: "ultra quiet", up to 3 GPUs |

---

## Berlin Apartment Constraints

| Constraint | Limit | This Build |
|------------|-------|------------|
| Standard Schuko outlet | 3,680W (16A x 230V) | 1 GPU: ~600W, 4 GPUs: ~1,400W — OK |
| Noise | Livable (<35 dB) | Water-cooled: achievable |
| Heat output to room | 300W per GPU | 1 GPU = space heater, 4 GPUs = sauna in summer |
| Physical space | Tower on/under desk | EEB full tower fits under desk |

---

## Decision Checklist

- [ ] Choose: DIY EPYC build vs pre-built from builder (AIME/Thomas-Krenn/MIFCOM)
- [ ] Source RAM: set Caseking restock alerts, contact Arrow/Avnet, or let builder source
- [ ] Order motherboard (GENOAD8X-2T/BCM)
- [ ] Order EPYC 9124 CPU
- [ ] Order 1x RTX PRO 6000 Max-Q from Conrad (EUR 10,635)
- [ ] Order HEATKILLER INOX Pro GPU block from Watercool.de
- [ ] Order CPU cooler (AIO for simplicity, or block for full custom loop)
- [ ] Order case, PSU, storage, loop components
- [ ] Build, install Ubuntu 24.04, install Ollama, run Kimi-Dev-72B
- [ ] Evaluate: is 1 GPU (96GB) sufficient for your coding workflows?
- [ ] If not: add GPUs from Conrad + water blocks, one at a time
