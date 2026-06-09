# Building the Best Open Claude Code Alternative for Maximum tok/s During the 2026 RAM Crisis

**A budget LLM inference rig that sidesteps the DDR5 ECC RDIMM shortage by reusing legacy DDR4 SODIMMs.**

---

## The Problem

In April 2026, anyone wanting to run a frontier open-source LLM locally faces a brutal market:

- **DDR5 ECC RDIMM prices up 172%** since mid-2025 ([Wikipedia](https://en.wikipedia.org/wiki/2024%E2%80%932026_global_memory_supply_shortage))
- **128 GB DDR5 ECC RDIMM costs €2,500-5,000** at retail ([Caseking out of stock, Dell at €2,640/stick](https://www.caseking.de/en/pc-components/memory/ecc-memory))
- **Samsung halted new module orders** — Q3 2026 production ramp at the earliest
- **Multi-GPU server boards (EPYC, WRX90, Xeon W) all require RDIMM** — no consumer escape hatch
- **NVIDIA RTX PRO 6000 Blackwell Max-Q sells for €10,635/card** at Conrad Electronic

The conventional answer — "buy a Threadripper PRO workstation with 256 GB DDR5 ECC and four GPUs" — costs **~€40,000**. Most independent developers can't justify that.

So how cheap can you build a Claude Sonnet/Opus-class local coding assistant in a Berlin apartment?

---

## The Key Insight: System RAM Barely Matters

LLM inference is **GPU-VRAM-bandwidth-bound**, not system-RAM-bound:

| Resource | Bandwidth | Role in inference |
|----------|-----------|-------------------|
| RTX PRO 6000 Max-Q VRAM | **1,800 GB/s** | Where the model lives, where decode reads happen |
| EPYC Genoa 12-channel DDR5 RDIMM | 460 GB/s | Idle 95% of the time |
| WRX90 8-channel DDR5 RDIMM | 307 GB/s | Idle 95% of the time |
| Consumer 2-channel DDR5 UDIMM | 102 GB/s | Idle 95% of the time |
| **Legacy DDR4-2133 SODIMM (dual-channel)** | **34 GB/s** | **Idle 95% of the time — fine** |

The model loads from disk to VRAM **once** (~30 seconds for a 70B Q4). After that, decode reads happen entirely from VRAM. System RAM only handles tokenization, OS, and the inference scheduler — workloads that idle a 4-core CPU.

**Conclusion:** The RAM crisis is irrelevant if you have GPU VRAM. Buy fast GPUs and the cheapest possible system RAM.

---

## The Build: Reusing 4× DDR4-2133 SODIMMs

I had four Samsung M471A2K43BB1-CPB modules (16 GB DDR4-2133 SODIMM, non-ECC, 1.2V) lying around from a decommissioned mobile workstation. **Total cost: €0.**

The challenge: find a motherboard that:
1. Accepts DDR4 unbuffered non-ECC SODIMMs (260-pin)
2. Provides PCIe 4.0 x16 for a PCIe switch card
3. Supports IPMI for headless management
4. Costs under €700

After eliminating Supermicro X11SDW (uses RDIMM despite the compact form factor), the answer was the **[ASRock Rack E3C256D4I-2T](https://www.asrockrack.com/general/productdetail.asp?Model=E3C256D4I-2T)** — a Mini-ITX server board with **4× DDR4 SODIMM slots, 1× PCIe 4.0 x16, IPMI, dual 10GbE**, for €492 at Senetic.

This is essentially the only off-the-shelf board on the German market combining DDR4 SODIMM with PCIe 4.0 server features.

---

## Architecture: One PCIe Slot, Four GPUs

A Mini-ITX board has one PCIe x16 slot. Four GPUs need eight slots' worth of physical mounting + lanes. The trick: a **PCIe switch**.

```
ASRock Rack E3C256D4I-2T
    │ PCIe 4.0 x16
    ▼
HighPoint Rocket 1528D (or generic PEX88048 card)
Broadcom PEX88048 PCIe 4.0 switch
    │ 4× SlimSAS 8i (SFF-8654) outputs
    ▼
2× JMT JHHP1B backplanes (each: 2 SlimSAS 8i in → 2 PCIe x16 slots out, x8 electrical)
    │
    ▼
4× NVIDIA RTX PRO 6000 Blackwell Max-Q (96 GB GDDR7, 1.8 TB/s, 300W)
```

**Why a PCIe switch instead of bifurcation?**

- BIOS bifurcation (x8x8 / x8x4x4) requires the CPU to enumerate multiple devices from one slot. Server boards often only expose limited bifurcation modes.
- A PCIe switch (PEX88048, like in the [HighPoint Rocket 1528D](https://www.highpoint-tech.com/product-page/rocket-1528d)) presents itself as **one device** to the BIOS. It internally fans out the lanes. **No BIOS bifurcation support needed.**
- The switch also provides hot-plug support, which matters for adding/removing GPUs during testing.

**Why PCIe 4.0 x8 per GPU is enough:**

LLM decode communication between GPUs (during tensor parallelism) is small — a few KB of activations per layer. The bottleneck is GPU memory bandwidth, not the inter-GPU link. PCIe 4.0 x8 = 16 GB/s per GPU is generous for this workload.

---

## The Right Model: Qwen3.5-397B-A17B (MoE)

| Model | Total Params | Active/token | Q4 Size | Fits 4× 96GB? | Strength |
|-------|--------------|-------------|---------|---------------|----------|
| **Qwen3.5-397B-A17B** | **397B** | **17B** | **222 GB** | **Yes (162 GB spare)** | Best Claude Code alternative |
| DeepSeek-V3.2 | 685B | 37B | 380 GB | Barely (4 GB spare) | Slightly stronger reasoning |
| GLM-5 | 744B | 40B | 410 GB | No | — |
| Llama 70B | 70B | 70B (dense) | 38 GB | Yes (1 GPU) | Older, smaller, faster but weaker |

**Why Qwen3.5-397B-A17B wins for this hardware:**

- **MoE architecture:** Only **17B parameters activate per token** (out of 397B total)
- **Decode reads only active weights:** ~9.4 GB per token at Q4, vs 38 GB for a dense 70B model
- **Result: 4× faster than a 70B dense model on the same hardware**
- **Quality:** Approaches Claude Sonnet 4.5 on coding/reasoning benchmarks ([bitdoze comparison](https://www.bitdoze.com/best-open-source-llms-claude-alternative/))
- **Fits comfortably:** 222 GB in 384 GB total VRAM leaves 162 GB for KV cache (long context)

---

## tok/s Estimates

GPU specs: 4× RTX PRO 6000 Blackwell Max-Q at 1.8 TB/s memory bandwidth each. PCIe interconnect: PCIe 4.0 x8 per GPU via the PEX88048 switch.

| Workload | Strategy | Estimated tok/s |
|----------|----------|-----------------|
| Qwen3.5-397B Q4 batch=1 decode | 4-way expert parallelism | **~120-150** |
| Qwen3.5-397B Q4 prefill | Compute-bound, all GPUs | ~800-1,200 |
| Llama 70B Q4 single GPU | No multi-GPU overhead | ~33 |
| DeepSeek-V3.2 Q3 | 4-way expert parallelism | ~80-100 |
| Llama 405B Q4 | 4-way TP | ~16 |

**Cross-reference:** [4× DGX B10 nodes (273 GB/s each) achieve 37-94 tok/s](https://forums.developer.nvidia.com/t/qwen3-5-397b-a17b-int4-autoround-4-x-db10-node-updated-results-37-94-tok-s/362368) on the same model. Our GPUs have **6.6× more memory bandwidth per card**. Scaling linearly and discounting for PCIe 4.0 x8 overhead vs NVLink: **~120-150 tok/s realistic.**

---

## Total Cost Comparison

| Approach | Mobo + CPU | RAM | Case + PSU | PCIe expansion | GPUs (4×) | **Total** |
|----------|-----------|-----|-----------|---------------|-----------|-----------|
| **This build (E3C256D4I-2T)** | €884 | **€0 (owned)** | €567 | ~€383 (generic) | €42,540 | **~€44,374** |
| EPYC Genoa DIY | €1,800 | €2,500-5,000 | €567 | €0 (native slots) | €42,540 | €47,407-49,907 |
| WRX90 (broken) | €2,675 | €2,500-5,000 | €567 | €0 (native slots) | €42,540 | €48,282-50,782 |
| **MIFCOM pre-built TR PRO** | — | — | — | — | — | **€39,849 (2 GPUs only)** |

**The real savings: ~€2,500-5,000 in RAM costs and €1,200 in motherboard differential**, by reusing existing DDR4 SODIMMs and accepting a less elegant Mini-ITX + PCIe switch setup.

---

## Why This Works (and Why It Almost Doesn't)

### Why it works

1. **GPU VRAM bandwidth dominates LLM inference.** Everything else is supporting infrastructure.
2. **MoE models read only active weights per token.** A 397B MoE behaves like a fast 17B model during decode while having the world knowledge of a 397B dense model.
3. **PCIe switches eliminate motherboard slot constraints.** A single x16 host connection fans out to 8 downstream devices, decoupling GPU count from motherboard PCIe layout.
4. **Legacy DDR4 SODIMMs are essentially free** if you have them. Buying them new at ~€30/16GB stick is also far cheaper than DDR5 ECC RDIMM.

### Why it almost doesn't

1. **The PEX88048 + RTX PRO 6000 combination is untested.** No community has validated GPU enumeration through an NVMe-class PCIe switch with workstation cards. Mitigation: bench test with one cheap GPU first before committing to four €10,635 cards.
2. **Mini-ITX physical layout requires custom backplane mounting.** The JMT JHHP1B boards aren't designed as drop-in GPU backplanes.
3. **Resizable BAR may not work** through some PCIe switches. Most inference frameworks tolerate this, but it's a risk.
4. **No vendor support.** When something fails, you're alone on Reddit and Level1Techs forums.

---

## What We'd Recommend If You're Doing This Today

### If you have legacy DDR4 SODIMMs (or can buy them cheaply)

Build the ASRock Rack E3C256D4I-2T setup. **~€1,500 in infrastructure (excluding GPUs)**. Highest risk, lowest cost. Best $/GB-VRAM if it works.

### If you don't have DDR4 SODIMMs and the RAM crisis hits you full price

Wait for **EPYC Genoa with refurb/surplus DDR5 RDIMM** from ITAD vendors (Techbuyer UK, AfB Germany). The [ASRock Rack GENOAD8X-2T/BCM](https://www.servethehome.com/asrock-rack-genoad8x-2t-bcm-review-an-uncomfortably-good-motherboard-amd-epyc-broadcom/) gives you **8× native PCIe 5.0 x16 slots, 12-channel DDR5, no PCIe switch needed**, with the same 4-7 GPU scaling path. ~€16,000-19,000 for Phase 1 (1 GPU).

### Avoid

**WRX90 with multi-GPU Blackwell.** PCIe stuck at Gen1, Xid 79 crashes, AMD AGESA bug with no fix ETA ([Level1Techs thread](https://forum.level1techs.com/t/dual-rtx-pro-6000-blackwell-on-wrx90-pcie-stuck-at-gen-1-anyone-else/242079)). Single GPU works fine. 2+ GPUs do not.

---

## The Stack, Summarized

**Hardware (ordered, ~€1,479 + GPUs):**
- ASRock Rack E3C256D4I-2T (€592, octo24)
- Intel Xeon E-2314 4C/4T LGA1200 (€292, Jacob Elektronik)
- 4× Samsung M471A2K43BB1-CPB 16 GB DDR4-2133 SODIMM (€0, owned)
- be quiet! Dark Power Pro 13 1600W Titanium (€393, Mindfactory)
- Phanteks Enthoo Pro 2 Tempered Glass (€175, Caseking)
- Jonsbo CR-1400 EVO 92mm tower cooler (€28, Caseking)
- *Pending:* HighPoint Rocket 1528D or generic PEX88048 switch card (~€220-650)
- *Pending:* 2× JMT JHHP1B PCIe 4.0 backplanes (~€63)
- *Pending:* 4× SFF-8654 8i cables (~€100)
- *Pending:* 4× NVIDIA RTX PRO 6000 Blackwell Max-Q (€42,540 at Conrad)

**Software:**
- Ubuntu 24.04 LTS
- vLLM with expert parallelism for MoE
- Qwen3.5-397B-A17B Q4 ([Unsloth GGUF](https://huggingface.co/unsloth/Qwen3.5-397B-A17B-GGUF) or [NVIDIA NVFP4](https://huggingface.co/nvidia/Qwen3.5-397B-A17B-NVFP4))
- Continue.dev / Aider for coding workflow

**Expected output: ~120-150 tok/s on Qwen3.5-397B at Q4.** That's roughly Claude Sonnet 4.5 quality at zero per-token cost, in a Berlin apartment, drawing under 1,500W from a single Schuko outlet.

---

## Final Word

The 2026 RAM crisis isn't going away until Q3 2026 production ramps. But the RAM crisis only matters if you actually need RAM. For GPU-bound LLM inference, **you don't.**

The trick is recognizing where the bottleneck actually is, and refusing to pay €5,000 for memory that will sit idle 95% of the time. Reuse what you have. Spend the savings on GPUs. Pick MoE models that exploit your VRAM efficiently.

The result: **a Claude Code alternative running 397B parameters at ~120-150 tok/s, for the cost of the GPUs alone.**

---

## Sources

### Hardware
- [ASRock Rack E3C256D4I-2T official](https://www.asrockrack.com/general/productdetail.asp?Model=E3C256D4I-2T)
- [NVIDIA RTX PRO 6000 Blackwell Max-Q datasheet](https://www.nvidia.com/content/dam/en-zz/Solutions/products/workstations/professional-desktop-gpus/rtx-pro-6000-max-q/workstation-datasheet-blackwell-rtx-pro-6000-max-q-nvidia-3519233.pdf)
- [HighPoint Rocket 1528D PEX88048 switch](https://www.highpoint-tech.com/product-page/rocket-1528d)
- [Phanteks Enthoo Pro 2 manual](https://phanteks.com/manuals/Enthoo_Pro2_Manual_v1.1.pdf)
- [Samsung M471A2K43BB1-CPB SODIMM](https://semiconductor.samsung.com/dram/module/sodimm/m471a2k43bb1-cpb/)

### Models
- [Qwen3.5-397B-A17B HuggingFace](https://huggingface.co/Qwen/Qwen3.5-397B-A17B)
- [Unsloth GGUF quantizations](https://huggingface.co/unsloth/Qwen3.5-397B-A17B-GGUF)
- [Best open-source Claude alternatives 2026](https://www.bitdoze.com/best-open-source-llms-claude-alternative/)
- [Qwen3.5 benchmarks on 4× DGX B10](https://forums.developer.nvidia.com/t/qwen3-5-397b-a17b-int4-autoround-4-x-db10-node-updated-results-37-94-tok-s/362368)

### Memory crisis
- [2024-2026 global memory shortage (Wikipedia)](https://en.wikipedia.org/wiki/2024%E2%80%932026_global_memory_supply_shortage)
- [DDR5 prices in Germany hit 4.4× July 2025 levels](https://videocardz.com/newz/ddr5-prices-in-germany-hit-4-4x-july-2025-levels-even-ddr3-memory-price-keeps-rising)
- [DDR5 RDIMM vs UDIMM technical differences (ATP)](https://www.atpinc.com/blog/DDR5-dimm-types-rdimm-vs-udimm-for-server-platform)

### Alternative builds
- [WRX90 PCIe Gen1 Blackwell bug (Level1Techs)](https://forum.level1techs.com/t/dual-rtx-pro-6000-blackwell-on-wrx90-pcie-stuck-at-gen-1-anyone-else/242079)
- [ASRock Rack GENOAD8X-2T/BCM review (ServeTheHome)](https://www.servethehome.com/asrock-rack-genoad8x-2t-bcm-review-an-uncomfortably-good-motherboard-amd-epyc-broadcom/)
- [YANGCOM Korea 4× RTX 5090 EPYC build](https://www.youtube.com/watch?v=Zy-x8bCoOAQ)

### German retailers
- [Geizhals price comparison](https://geizhals.de)
- [Caseking (Berlin)](https://www.caseking.de)
- [Mindfactory](https://www.mindfactory.de)
- [Jacob Elektronik](https://www.jacob.de)
- [Conrad (RTX PRO 6000 Max-Q stock)](https://www.conrad.de)

---

*Build status as of 2026-04-09: Mobo, CPU, PSU, case, cooler ordered. PEX88048 switch + JMT backplanes + GPUs pending. First POST expected this week.*
