# flux

Home AI lab — infrastructure automation, hardware documentation, and inference
demos across three nodes: `crucible` (inference), `forge` (dev), `serval`
(orchestration / daily driver).

## Nodes

| Node | Machine | Role |
|------|---------|------|
| `crucible` | ASRock Rack E3C256D4I-2T · Xeon E-2314 | LLM inference, NFS model server |
| `forge` | exone X299 dev workstation | Build, experiment |
| `serval` | System76 Serval WS | Always-on: API gateway, monitoring, model sync, daily driver |

Hardware inventory, PCIe topology, milestone log: [`Lab/<node>/README.md`](Lab/)

## Provisioning

```sh
sudo make        # system — hardening, NVIDIA drivers, CUDA, desktop apps
make             # user — Claude CLI, SSH keys, shell completion
make references  # download product PDFs into References/ (gitignored)
```

The root `Makefile` runs on any node. Targets gate themselves on hardware:
CUDA installs only when an SM ≥ 75 GPU is present; storage mounts only when
the SN8100 label is visible.

## Demos

| Demo | Path | What it does |
|------|------|--------------|
| llama.cpp | `demos/llamacpp/` | Build and run llama.cpp inference stack |
| TurboQuant | `demos/turboquant/` | Quantisation benchmark — vLLM, Locust, Spark pipeline |

## Repo Layout

```
Makefile              Ubuntu provisioning (hardening, CUDA, apps)
demos/
  llamacpp/           llama.cpp inference stack
  turboquant/         TurboQuant quantisation demo
Lab/
  crucible/           Primary inference node
  forge/              X299 dev workstation
  serval/             System76 Serval WS
References/           Product docs (gitignored — fetch with: make references)
  Motherboard/        E3C256D4I-2T manual + PDF
  Case/               Phanteks Enthoo Pro 2 manual
  Storage/            SN8100 datasheet, ICY DOCK adapters
Archive/              Rejected alternatives (ASRock WRX90, EPYC Genoa)
scripts/
  merge.py            Syncthing dedup — hardlink by SHA-256 across devices
RISKS.md              System risk register (severity-sorted, all subsystems)
CLAUDE.md             AI assistant context and reference file paths
```
