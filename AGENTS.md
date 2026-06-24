# Crucible — Agent Instructions

## Primary reference files

Consult in this order before answering hardware questions:

1. **`CLAUDE.md`** — project overview, fixed components, constraints, known corrections
2. **`RISKS.md`** (at `Lab/RISKS.md`) — severity-sorted risk register, update rules
3. **`Lab/crucible/README.md`** — full hardware inventory, PCIe topology, first-boot baseline, BMC reference, storage subsystem
4. **`References/Motherboard/E3C256D4I-2T.md`** — motherboard manual (3014 lines)

## Makefile conventions

- Every repeatable action is a Makefile target. **Never give raw bash as a solution** — write the target first, then tell the user to run `make <target>`.
- `make` or `sudo make` → runs the system setup flow (root: `sudo make system`, user: `make user`).
- `make clean && make` wipes and rebuilds provisioned state.
- The Makefile enforces a constitution (Makefile:4-57). Key rules enforced by pre-commit hook (`check-makefile.py`):
  - No `sudo` in recipes (branch at parse time with `IS_ROOT` gate)
  - No nested `$(MAKE)`
  - Dependents declared before prerequisites
- Feature gating: `HAS_PLX_SWITCH`, `HAS_BMC`, `COMPUTE_CAPABLE`, `SN8100_PRESENT` are sensed at parse time.

## Makefile style

- Keep it simple. Prefer `lspci` one-liners over sysfs shell loops — `lspci` is the PCI specialist (Principle XII). Resort to sysfs only when `lspci` lacks the data you need.
- Split monolithic `$(shell ...)` commands into separate named variables — one discovery per variable, compose the final result from them. E.g. `PLX_UPSTREAM`, `PLX_DOWNSTREAMS`, `PLX_GPU` → `PLX_ASPM_TARGETS`.

## PCIe switch path (highest project risk)

- Bench card: **PLX PEX 8749** (48-lane, 18-port, PCIe Gen 3, `10b5:8749 rev ca`) in PCIE7.
- Target: **PEX88048** via HighPoint Rocket 1528D (PCIe Gen 4).
- **ASPM L1 on switch GPU downstream triggers Xid 79 "GPU fell off the bus"** → fix: `mk/system/hardening.mk` clears L1 bits at boot via `disable-gpu-aspm.service`. Gated on `HAS_PLX_SWITCH`.
- **Xid 154 "Reset Required"** needs cold power cycle (PSU off ~30s) — warm reboot does not clear.
- Detailed register walkthrough in `Lab/pex8749-stability-tuning.md` — standard PCIe caps via `setpci`/`lspci`, vendor registers need Broadcom's PEX SDK (`PlxCm`).

## Demo notebook

- `demos/prefix-caching/prefix_caching_demo.ipynb` — runs on Colab/Kaggle free T4 GPU.
- Targets: `make colab-upload`, `make kaggle-run`, `make demo-notebook`.
- Dependencies: `uv` venv at `.venv/bin/python3`, TurboQuant Jupyter kernel.

## Key labs

| Directory | Contents |
|-----------|----------|
| `Lab/crucible/` | Primary inference node — full build log, PCIe test stages, BMC, risk register |
| `Lab/forge/` | X299 dev workstation (PEX switch validation platform) |
| `Lab/pex8749-stability-tuning.md` | Debug guide: ASPM, link tuning, `setpci` register walk |
| `Lab/RISKS.md` | Single source of truth for project risks (severity sorted) |

## Pre-commit hooks

- `.claude/hooks/check-makefile.py` — validates Makefile constitution (sudo in recipes, nested MAKE, dependency ordering). Runs on every file write to Makefile/`.mk` files.

## Staged bring-up

**Do not energize all at once.** Order: mobo + CPU + 1 DIMM → add DIMMs → first GPU via switch → second GPU → 4 GPUs. Validate PEX switch with one cheap GPU before purchasing RTX PRO 6000 Blackwell Max-Q cards.

## Critical motherboard gotchas

- Single DIMM → `DDR4_A2` or `DDR4_B2` (daisy-chain topology), not A1/B1.
- Front-panel goes on `PANEL1` (#12), not adjacent `ITX_AUX_PANEL1` (#11).
- Board has **no 24-pin ATX** — uses bundled 24-to-4 adapter → `ATX4PIN1`.
- CPU must have fan on `FAN1` with tach signal or board halts POST.
- BMC takes 30–60s to boot after PSU power. Default `admin / admin`.
