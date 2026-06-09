# exone WORKSTATION 4204HE — X299 Dev Workstation

**Serial**: 3182144s001 · **Art. Nr.**: 138345  
**Source**: [shoptools.exone.de](http://www.exone.de/tools/sn/?sn=3182144s001)

---

## Hardware Configuration

| Component | Detail |
|-----------|--------|
| **CPU** | Intel Core i9-10900X 3.70 GHz · 10C/20T · 165W · LGA2066 |
| **Motherboard** | ASUS Prime X299-A II · LGA2066 · X299 · ATX |
| **RAM** | 2× 16GB DDR4-3200 Kingston Fury Beast Black CL16 = 32GB · max 256GB (8× 32GB UDIMM) · 6 slots free |
| **Storage** | Samsung 970 EVO Plus 1TB M.2 NVMe PCIe 3.0 x4 |
| **GPU** | NVIDIA PNY RTX A4000 16GB GDDR6 · PCIe 4.0 · 4× DP 1.4 · 140W |
| **Cooling** | exone AIO 670LS · 120×240×27mm radiator · 2× ADDA 120mm fans |
| **PSU** | be quiet! ATX 600W · 120mm fan |
| **Case** | Fractal Design Define R6 USB-C gunmetal |
| **OS** | Windows 10 Pro 64-bit installed · Windows 11 Pro license (downgrade) |
| **Extras** | DVD-RW LG GH24NSD5 · Molex→8-pin EPS adapter · C13 power cable |

---

## PCIe Topology (i9-10900X)

The i9-10900X provides **44 PCIe 3.0 lanes** from the CPU:
- x16 slot (primary) → RTX A4000 (currently)
- x16 electrical slot (second) — available
- x8 slot — available
- x4 slot — available
- M.2 (PCIe 3.0 x4) → Samsung 970 EVO Plus boot drive

The X299-A II supports PCIe bifurcation up to x8x8x8x8 on the CPU lanes, unlike the E3C256D4I-2T (LGA1200, max x8x4x4). This makes it a candidate host for a PEX88048 switch card without the bifurcation ceiling of the Crucible Stage 1 board.

---

## Role in the Crucible Ecosystem

### Primary: PCIe Switch Validation Platform
The Stage 1 Crucible (E3C256D4I-2T) needs PEX88048 validation before the RTX PRO 6000 Blackwell cards arrive. The X299-A II's wider lane budget and x8x8x8x8 bifurcation make it a safer first test bed for the switch + JMT JHHP1B backplane topology.

### Secondary: Development Host
- 10C/20T CPU handles parallel compile jobs (llama.cpp, model quantisation)
- 32GB DDR4 expandable to 128GB (8× DIMM slots, quad-channel)
- RTX A4000 16GB — sufficient for 7B/13B model development and CUDA kernel work
- Runs Linux alongside Windows for cross-platform build testing

### Tertiary: Water Cooling Learning Platform
The AIO will eventually be replaced with a custom loop, making this the low-risk machine to learn loop assembly, leak testing, and fitting selection before committing to the 4-GPU Crucible loop. The Define R6 has excellent radiator mounting options.

Water block candidates for RTX A4000:
- Bykski N-RTA4000-X — full-cover, PCIe 4.0 A4000 specific
- HEATKILLER IV for A4000 (if available)

### Quaternary: EPYC Stage 2 Management GPU
If the EPYC Genoa build (Stage 2) runs headless, the A4000 can move there as the management/display GPU, freeing all PCIe 5.0 slots for inference GPUs.

---

## Upgrade Path

1. **RAM**: max 256GB (8× 32GB DDR4-3200 UDIMM); currently 32GB (2× 16GB); 6 slots free — add 6× 16GB (~€90–150) for 128GB, or swap to 8× 32GB for 256GB (fits Flash Q4 entirely in RAM)
2. **Storage**: Add WD_BLACK SN8100 or equivalent for model weights once SN8100 moves to OCuLink on Crucible
3. **GPU**: A4000 stays until Crucible Stage 1 is running; optionally swap for a used RTX 3090/4090 for larger local model inference
4. **Cooling**: Replace AIO with custom loop (240mm rad at minimum; Define R6 supports 360mm front)
5. **PEX88048 test**: Install switch card in x16 slot, bifurcate to x8x8, connect two GPU risers — validates topology before Crucible assembly
