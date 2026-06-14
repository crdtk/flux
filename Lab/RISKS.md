# Crucible — System Risk Register

Project-wide gotchas, severity-sorted by subsystem. Consult this **before** answering any hardware or integration question about this build. Component-specific detail lives in sibling files (linked per section).

## Legend
- 💀 **DAMAGE** — permanent hardware loss if wrong
- 🔴 **BLOCKER** — build won't work until resolved
- 🟡 **PERF / CAP** — works but degraded or capped
- 🟢 **INFO** — operational fact; prevents confusion or time-wasting

---

## Power & electrical envelope

| Risk | Rule | If wrong | Notes |
|---|---|---|---|
| 💀 DAMAGE | Do not swap PSU cables between brands/models even if connectors match. Pinouts vary. | PSU-side short, component damage. | be quiet! DPP13 cables are PSU-specific. |
| 💀 DAMAGE | Verify AC unplugged + `+5VSB` LED off before touching components. | Short risk on standby rails. | Board RISKS §p.12 |
| 🔴 BLOCKER | Berlin apartment: Schuko 16A breaker = 3,680W theoretical, often 2,300W practical (older circuits = 10A). | Breaker trips under load. | Verify circuit rating before full-load test. |
| 🔴 BLOCKER | Dual-PSU builds need Add2PSU / ATX bridge, or the secondary PSU won't turn on with the primary. | Second PSU idle; GPUs unpowered. | Only relevant at Stage 1 → Stage 2 scaling. |
| 🟡 CAP | Planned full load: 4× 300W (Max-Q GPUs) + 65W CPU + ~100W board/drives = **~1,365W**. Single DPP13 1600W is adequate with ~15% headroom. | Tight headroom under transient spikes. | 8-GPU scaling would exceed single-PSU + single-Schuko budget. |
| 🟢 INFO | Heat output ≈ input wattage. 1,365W load = ~4,600 BTU/hr into the room. | Summer operation may need aux cooling. | Berlin apartment thermal planning. |

## CPU & cooling

| Risk | Rule | If wrong | Notes |
|---|---|---|---|
| 💀 DAMAGE | Never power on without CPU cooler mounted and thermal paste applied. | CPU thermal shutdown in seconds; repeated events damage die. | Applies even for "just checking POST" — heatsink must be on. |
| 🔴 BLOCKER | Jonsbo CR-1400 EVO is a 92mm tower — verify **DDR4 SODIMM clearance** on Mini-ITX. SODIMM slots sit near the CPU socket. | Cooler won't mount, or blocks DIMM slots. | Measure before first install. |
| 🟡 CAP | Xeon E-2314 is 4C/4T, 65W, LGA1200 — CPU is **GPU-bound workload bottleneck**, not memory. | Expecting CPU to matter for tok/s — it doesn't. | Documented in ARTICLE.md §"System RAM barely matters". |
| 🟢 INFO | Xeon E-2314 has **no iGPU** — all display comes from the BMC (ASPEED AST2500 VGA). | Expecting HDMI/DP; plugging graphics card for bench test. | Board RISKS §DISPLAY |

## Motherboard (E3C256D4I-2T)

**See `Stage 1 - Memory Reuse/RISKS.md` for the 15-row detailed register.** Critical highlights:

| Risk | Rule | Cross-reference |
|---|---|---|
| 💀 DAMAGE | Don't cross `ATX4PIN1` (signal) with `SATAPWR1` (12V/5V). | Board RISKS §p.21 |
| 💀 DAMAGE | DDR4 SODIMM only; no DDR3/DDR5/UDIMM. Orientation matters. | Board RISKS §p.16 |
| 🟡 CAP | Single DIMM → **`DDR4_A2` or `DDR4_B2`**, not A1/B1 (daisy-chain topology). | Board RISKS §p.16 |

## PCIe switch & fanout (highest project risk)

| Risk | Rule | If wrong | Notes |
|---|---|---|---|
| 💀 DAMAGE | **PEX88048 + RTX PRO 6000 Max-Q + E3C256D4I-2T = fully untested stack.** No community validation exists. | Board or GPU damage on first enumeration. | EVALUATION.md flags this as "Build Risk: HIGH" |
| 💀 DAMAGE | Do **not** commit €42,540 in GPUs before proving the switch enumerates ≥1 GPU. | Massive sunk cost on unworkable path. | Mitigation: bench-test with one cheap GPU (e.g., used RTX 3060) before buying Max-Q cards. |
| 🔴 BLOCKER | BIOS must enumerate downstream devices through the switch. Some BIOSes expose bifurcation requirements even through switch cards. | First GPU doesn't appear in BIOS / OS. | HighPoint Rocket 1528D is known-good; generic PEX88048 cards vary. |
| 🔴 BLOCKER | Resizable BAR may not pass through the switch. Most inference frameworks tolerate but verify early. | GPU shows reduced VRAM or refuses rBAR. | Test with nvidia-smi + dmesg on first boot. |
| 🔴 BLOCKER | **ASPM L1 on the switch's GPU downstream port triggers Xid 79 "GPU fell off the bus"** → recurring hard freeze. Disable with `pcie_aspm=off`. | System locks; `nvidia-smi` → "No devices". Warm reboot does **not** clear Xid 79 + Xid 154 "Reset Required" — needs **cold power cycle** (PSU off ~30s). | Bench 2026-06-14 (A4000 behind PEX 8749). Fix in `mk/system/hardening.mk` → `99-pcie-aspm.cfg`, gated on `HAS_PLX_SWITCH`. |
| 🟡 CAP | Signal integrity degrades with long SlimSAS cables at PCIe 4.0 x8. Use reputable brand + correct length. | Link drops to Gen3 or Gen2. | Buy proper 3M / Molex cables, not Ali-cheap. |
| 🟡 CAP | Bench switch is actually a **PLX PEX 8749 (Gen3)**, not the planned PEX88048 (Gen4). Test GPU enumerated at **Gen1 x4 (2.5 GT/s)** vs its Gen3 x16 cap — link trained all the way down. | Severe bandwidth cap + instability; Gen1 fallback = marginal physical link (extends row above). | Reseat GPU + backplane/OCuLink cabling. Bench 2026-06-14. |
| 🟡 CAP | Switch firmware may need update for newer GPU models. Vendor tool typically required. | GPU ID not recognized by switch. | Check HighPoint firmware changelog before flashing. |

## GPU (RTX PRO 6000 Blackwell Max-Q)

| Risk | Rule | If wrong | Notes |
|---|---|---|---|
| 💀 DAMAGE | Don't energize a GPU with an unseated PCIe edge. | Lane damage on switch or GPU. | Always seat fully before power-on. |
| 🔴 BLOCKER | **Max-Q variant is 300W**, not 600W like non-Max-Q. Thermal and power planning based on 300W TDP. | Under-provisioning for 600W assumption wastes cooling / over-provisioning wastes PSU budget. | Verify part number on invoice: `RTX PRO 6000 Max-Q` vs `RTX PRO 6000`. |
| 🟡 CAP | Power connector: 12V-2×6 (new spec, 2024+) or 12VHPWR (older). Verify PSU cable + GPU side match. | Mechanical fit issue or derated operation. | be quiet! DPP13 1600W ships with 12V-2×6 cables; verify compatibility with Max-Q. |
| 🟢 INFO | Driver branch: NVIDIA **datacenter (TRD) driver**, not GeForce/Game Ready. CUDA 12.6+ recommended for Blackwell. | Use gaming driver → unsupported warnings, suboptimal MoE performance. | Verify kernel version 6.8+ for Blackwell module compatibility. |
| 🟢 INFO | Each Max-Q is blower-cooled → ejects heat out the rear I/O. Stack of 4 in sequence = back of case runs hot. | Airflow planning assumes heat distribution, but it all comes out one end. | Rear exhaust fan strategy matters more than front intake. |

## Storage

| Risk | Rule | If wrong | Notes |
|---|---|---|---|
| 🟡 CAP | Samsung 9100 PRO is **PCIe 5.0**, but E-2314 + C256 cap at **PCIe 4.0 x4**. Drive runs at ~8 GB/s instead of ~14 GB/s. | Paid for PCIe 5.0 bandwidth you can't use. | Drive transfers cleanly to Stage 2 EPYC Genoa where PCIe 5.0 is native. |
| 🟡 CAP | OCuLink ports are **PCIe 3.0 x4** (not 4.0). Any U.2/NVMe via OCuLink caps at ~4 GB/s. | Expecting NVMe speeds from OCuLink-attached storage. | Board RISKS §PERF CAP |
| 🟢 INFO | Board's single M.2 slot (M2_1) handles OS + model cache. OCuLink + SATA remain for backup / archive storage. | Thinking you need multiple M.2 slots for a single system. | One fast M.2 + one SATA/OCuLink backup bay is the design. |

## Case & airflow (Phanteks Enthoo Pro 2 TG)

| Risk | Rule | If wrong | Notes |
|---|---|---|---|
| 🔴 BLOCKER | 4 stacked GPUs on backplanes = heat stacking. **Aggressive front intake + top exhaust required.** | Throttling under sustained inference load. | Blower GPUs eject rearward; pull air in front, out top/rear. |
| 🟡 CAP | **Consumer case front I/O exceeds server board's internal headers.** Board has 1× USB 3.2 Gen1 19-pin header; case supplies 2× 19-pin + 1× Type-E + 1× HD Audio + 1× D-RGB. Only 2 of 4 front Type-A ports work; USB-C, audio, D-RGB all dead. | Expecting all front I/O to work on a server Mini-ITX. | Board manual §p.7 layout, §p.20 headers. Plug one 19-pin cable to `USB3_3_4`; tuck the rest away. |
| 🟡 CAP | **No front-panel drive bays.** Backup drive access requires rear-side-panel removal OR rear PCI-slot-bracket mount. | Expecting optical-drive-bay ergonomics for drive swap. | Discussed in Backup section of build log. |
| 🟢 INFO | Dual-PSU mount available — useful if scaling to 7+ GPUs in Stage 2 or splitting PSU duties. | Not needed for Stage 1 single-PSU budget. | — |

## Firmware & software

| Risk | Rule | If wrong | Notes |
|---|---|---|---|
| 🔴 BLOCKER | BMC defaults to DHCP + **`admin / admin`** credentials. Change password before network exposure. | BMC on open network = remote console, remote power, remote media. Trivial to compromise. | First-boot task. Board RISKS §p.55 |
| 🟡 CAP | **WiFi injection only works on NetworkManager-based live ISOs** (Kubuntu/Debian/Mint). Arch's archiso uses `iwd` + `systemd-networkd` — the injected `.nmconnection` file is ignored. | Expecting WiFi auto-connect to work on Arch live boot. | Ventoy **persistence** still works for Arch per Ventoy docs, but WiFi must be set up manually via `iwctl` on first boot. |
| 🟡 CAP | Linux kernel **6.8+** for full Blackwell + Max-Q support. | Older kernels → missing features, suboptimal performance. | Kubuntu 25.10 / 26.04 beta both ship ≥6.8. Verified at USB build time. |
| 🟡 CAP | **CUDA 12.6+** required for Blackwell compute capability. | `nvcc` compile failures, missing kernels for new ops. | Install from NVIDIA directly; distro packages lag. |
| 🟢 INFO | vLLM + expert parallelism is the target inference stack for Qwen3.5-397B-A17B MoE. | Rolling your own inference — loses perf; vLLM handles MoE routing. | ARTICLE.md §Software |

## Makefile / tooling

| Risk | Rule | If wrong | Notes |
|---|---|---|---|
| 🔴 BLOCKER | **`.PRECIOUS` must protect downloaded ISOs.** Without it, GNU Make deletes intermediate files (multi-GB ISOs in `~/Downloads/`) when a downstream rule (rsync to USB) fails. | Hours of re-downloading after a transient USB write error. | Fixed with `.PRECIOUS: $(DOWNLOADS_DIR)/%` above the download pattern rule. Discovered when a 4.5 GB Manjaro ISO was auto-deleted after an rsync I/O error. |

## Operational & budget

| Risk | Rule | If wrong | Notes |
|---|---|---|---|
| 💀 DAMAGE | **Staged bring-up, not all-at-once.** Order: mobo + CPU + 1 DIMM → add DIMMs → first GPU via switch → second GPU → 4 GPUs. | Fault diagnosis becomes "what of these 20 new components broke" vs "this one new one". | Document what works at each stage. |
| 💀 DAMAGE | Stage 1 sunk cost if PCIe switch path fails: **~€887** (mobo + CPU + cooler + SODIMMs don't transfer to EPYC). Case + PSU + 9100 PRO do transfer. | Committing €44k before proving the €887 critical path works. | Bench test is the single highest-value hour in this build. |
| 🔴 BLOCKER | **Verify one cheap test GPU enumerates via the PEX88048 switch** before purchasing any RTX PRO 6000. | Same as above — discovered on €10,635/card instead of €300/card. | Used RTX 3060 / 3070 for test; sell after. |
| 🟡 CAP | Total Stage 1 budget: **~€44,374** (€42,540 = GPUs, ~€1,834 = everything else). Budget surprises here would wreck the project economics. | — | EVALUATION.md §Stage 1 |
| 🟢 INFO | Stage 2 fallback (EPYC Genoa) is documented. PSU + case + 9100 PRO reuse, mobo + CPU + DDR4 SODIMMs sunk. | — | `Stage 2 - Post-Crisis/EPYC Genoa Workstation Build.md` |

---

## Update rules
1. Add rows when new risks surface during bench-test / assembly / bring-up.
2. Keep rows one-line; push detail to component manuals or build logs via `§` references.
3. Preserve severity ordering on edit (💀 → 🔴 → 🟡 → 🟢 within each section).
4. If a section grows past ~10 rows, split it into a dedicated file (like `Stage 1 - Memory Reuse/RISKS.md` did for the motherboard) and leave a pointer.
5. When in doubt about a risk level, default to the higher severity.
