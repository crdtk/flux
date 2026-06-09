# Crucible — DDR4 SODIMM LLM Inference Rig

Budget local LLM inference workstation built during the 2026 RAM crisis.
Reuses legacy DDR4 SODIMMs (€0 cost) on a Mini-ITX server board with a PCIe
switch providing 4× PCIe x8 GPU slots.
Berlin apartment build — silence first-class, target under 1.5 kW.

## Hardware

| Component | Detail | Status |
|-----------|--------|--------|
| **Motherboard** | ASRock Rack E3C256D4I-2T · Mini-ITX · LGA1200 · 4× DDR4 SODIMM · PCIe 4.0 x16 · 2× OCuLink · IPMI | INSTALLED |
| **CPU** | Intel Xeon E-2314 · 4C/4T · 65 W · LGA1200 | INSTALLED |
| **RAM** | 2× Samsung M471A2K43BB1-CPB · 16 GB DDR4-2133 SODIMM = 32 GB (4 slots, 2 free) | INSTALLED |
| **PCIe switch** | PLX Technology PEX 8749 · 48-lane 18-port Gen 3 · validated 2026-05-30 | INSTALLED ✓ |
| **GPU backplanes** | 4× JMT JHHP1B · 1× SFF-8654 8i per backplane → PCIe x8 · 2 installed | 2 INSTALLED ✓ |
| **Storage — boot** | Samsung 9100 PRO 8TB · M.2 PCIe 4.0 x4 · M2_1 · Manjaro KDE (btrfs) | INSTALLED |
| **Storage — models** | WD_BLACK SN8100 8TB · M.2 PCIe 4.0 x8 · staging in PCIE7, target OCuLink | INSTALLED |
| **PSU** | be quiet! Dark Power Pro 13 1600W · 80+ Titanium | INSTALLED |
| **Case** | Phanteks Enthoo Pro 2 TG · full tower · dual PSU mount | INSTALLED |

Full inventory, PCIe topology, milestone log, and risk register: [`Lab/crucible/README.md`](Lab/crucible/README.md)

## Quick Start

```sh
sudo make             # system provisioning — hardening, drivers, apps, CUDA
make                  # user setup — Claude, SSH keys, shell completion
make references       # download product PDFs to References/ (gitignored)
make -C demos/llamacpp    # build llama.cpp inference stack
make -C demos/turboquant  # run TurboQuant quantization demo
```

## Repo Layout

```
Makefile              Ubuntu provisioning — hardening, CUDA, desktop apps
demos/
  llamacpp/           llama.cpp inference stack
  turboquant/         TurboQuant quantization demo (vLLM, Locust, Spark)
Lab/
  crucible/           Primary inference node — hardware log, PCIe tests, risk register
  forge/              exone X299 dev workstation
  serval/             System76 Serval WS — orchestration, API gateway, daily driver
References/           Product docs — download with: make references
  Motherboard/        E3C256D4I-2T manual + PDF, ASUS Prime X299-A II
  Case/               Phanteks Enthoo Pro 2 manual
  Storage/            SN8100 datasheet, ICY DOCK MB111VP-B + MB705M2P-B manuals
Archive/              Rejected alternatives — ASRock WRX90 (RDIMM), EPYC Genoa build
scripts/
  merge.py            Syncthing dedup — hardlink incoming/<device>/<folder>/ into merged/
RISKS.md              System risk register (all subsystems, severity-sorted)
CLAUDE.md             AI assistant context and component reference paths
```

