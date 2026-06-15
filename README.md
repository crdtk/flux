# Crucible

Local LLM inference rig for the 2026 RAM crisis. Planned: four RTX PRO 6000 Blackwell Max-Q GPUs (96 GB GDDR7 each, 384 GB total) through a PEX88048 PCIe switch, on a Mini-ITX board with DDR4 SODIMMs — the only board in this niche. Target: Qwen3.5-397B-A17B at 120–150 tok/s in a Berlin apartment under 1.5 kW. GPUs not yet purchased; PCIe switch path under bench validation.

---

## Prefix caching demo

[`demos/prefix-caching/prefix_caching_demo.ipynb`](demos/prefix-caching/prefix_caching_demo.ipynb)

Runs on Colab free tier (T4). Shows how vLLM's block-hash prefix caching eliminates prefill for shared context, why review order and dynamic-content placement determine cache hit rate, and what INT4 KV quantization buys in terms of context capacity.

```bash
make colab-upload    # push + open in Colab
make demo-notebook   # open locally in Jupyter
```

The notebook is self-contained: first run installs vllm and restarts the kernel; second Run All executes all cells.

---

## Lab automation (`mk/`)

The `mk/` directory provisions the hardware this rig runs on. Every repeatable action is a Makefile target — no raw shell commands.

| Module | What it sets up |
|---|---|
| `mk/system/` | Networking (10GbE, WAN failover), storage (NVMe, OCuLink), CUDA drivers, PCIe switch |
| `mk/user/` | KDE desktop, VS Code, AI CLI tools, Jupyter kernel |
| `mk/display.mk` | Multi-monitor layout, plasmoid config |
| `mk/clean.mk` | Wipe provisioned state for a clean re-run |

```bash
sudo make system   # root-level provisioning
make user          # user-space setup (no sudo)
```

---

## Hardware

| Component | Part |
|---|---|
| Motherboard | ASRock Rack E3C256D4I-2T (4x SODIMM, PCIe 4.0 x16 bifurcation) |
| CPU | Intel Xeon E-2314 (LGA1200, 20 PCIe 4.0 lanes) |
| RAM | 2x Samsung M471A2K43BB1-CPB — 32 GB DDR4-2133 SODIMM |
| GPU (active) | NVIDIA RTX A4000 (16 GB GDDR6, 140 W) — current development GPU |
| GPU (target) | 4x NVIDIA RTX PRO 6000 Blackwell Max-Q (96 GB GDDR7, 300 W) — not yet purchased; deferred until PCIe switch path validated |
| PCIe switch | PEX88048 via HighPoint Rocket 1528D — target; bench-testing with PLX PEX 8749 (Gen3 substitute), link currently training at Gen1 x4 (reseating GPU + backplane cabling in progress) |
| Storage (boot) | Samsung 9100 PRO 8 TB (M.2) |
| Storage (models) | WD_BLACK SN8100 8 TB (OCuLink via Tekram TK-2U11) |
| Case | Phanteks Enthoo Pro 2 |
| PSU | be quiet! Dark Power Pro 13 1600W |
| Cooling | Full custom water loop — CPU + 4 GPUs + PEX88048 |

See [`RISKS.md`](RISKS.md) for the full risk register (thermal, electrical, firmware, PCIe).
