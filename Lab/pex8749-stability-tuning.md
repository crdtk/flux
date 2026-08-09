# The Tiny Power Nap That Keeps Killing Your GPU

### A graphics card behind a $200 switch chip kept vanishing mid-session. The culprit wasn't heat, or a bad card, or cosmic rays. It was a feature designed to save electricity — and the fix is a lesson in knowing which knobs *not* to turn. Follow along on your own machine: every claim below comes with the command to prove it.

---

It always happens at the worst moment. The model is loading, the fans spin up, and then — nothing. The screen freezes. The logs cough up a single damning line: **Xid 79**, NVIDIA's internal error code (Xid is just "the identifier" of a GPU fault) that translates, with brutal honesty, to *"GPU has fallen off the bus."* The card didn't crash. It didn't overheat. It simply *left*, the way a guest slips out of a party without saying goodbye.

You can catch it in the act:

```bash
sudo dmesg | grep -iE 'Xid|fallen off the bus'   # the confession
nvidia-smi -L                                     # "No devices were found" = it's gone right now
```

Our card — an NVIDIA RTX A4000 — wasn't even plugged into the motherboard directly. It hung off a **PLX PEX 8749**, a palm-sized **PCIe (Peripheral Component Interconnect Express) switch** from Broadcom's PLX line. Think of it as a power strip for data lanes: one fat cable goes *up* to the processor, and the chip fans those lanes *out* to a row of downstream ports. It's how you bolt four graphics cards onto a motherboard meant to hold one. Clever — and a chip with a lot of hidden switches of its own, not all of which should be flipped.

Before you can chase anything, you need the addresses of the players — each device's **BDF (Bus:Device.Function)**:

```bash
lspci -nn | grep -iE 'PLX|PEX|NVIDIA'   # the switch ports and the GPU
lspci -tv                               # the tree: what hangs off what
```

On our rig that shakes out to: GPU at `04:00.0`, its switch port `02:09.0`, the switch's uplink `01:00.0`. Yours will differ — swap them into the commands below.

## The crime scene

The first instinct with a vanishing card is to suspect the obvious: temperature, power, a flaky cable. All reasonable. All wrong, this time. The smoking gun was **ASPM — Active State Power Management**, a thrifty little feature baked into every PCIe link. When the card goes idle, ASPM lets the link tiptoe into a low-power sleep state called **L1**, cutting power draw to save a few watts. Wonderful in a laptop. Murderous here.

Don't take my word for it — every link advertises whether the nap is armed:

```bash
sudo lspci -vv -s 04:00.0 | grep -E 'LnkCtl:'
#   "ASPM L1"        → the nap is armed — this is the trigger
#   "ASPM Disabled"  → ruled out
```

Why does a nap kill the card? Because waking *back up* from L1 takes an electrical handshake to re-synchronize the link. If the physical connection is even slightly marginal — a long cable, a not-quite-perfect seat — that handshake fails. The link doesn't wake. The card, as far as the rest of the computer is concerned, has ceased to exist. Xid 79. Party over.

The kill shot is one register write — clearing the two ASPM-control bits in the link's control register:

```bash
sudo setpci -s 04:00.0 CAP_EXP+0x10.w=0:3   # GPU: ASPM → off, instantly
sudo setpci -s 02:09.0 CAP_EXP+0x10.w=0:3   # and its switch port
```

> ⚠️ **`setpci` is a scalpel, not a fix.** It writes live and *vanishes on reboot* — perfect for testing a hunch, wrong for permanence. Anything you want to keep belongs in the Makefile (`disable-gpu-aspm` in `mk/system/hardening.mk`) or the GRUB (GRand Unified Bootloader) kernel command line.

Run those two writes, re-check `LnkCtl`, and the freezes stop. Case closed?

Not quite. The PEX 8749 isn't *one* link — it's a switchboard of them, and we'd silenced the nap on exactly one line.

## The dials — and the ones that bite back

A switch chip exposes a drawer full of knobs, and the temptation is to yank them all. That's how a working machine becomes a paperweight. So we rate each one like a bomb tech rates a wire: **payoff versus what happens if you cut it.** Each comes with how to *look*, and — where it's safe — how to *touch*.

> **📦 What's actually in the drawer?**
> A switch port is, electrically, a PCI-to-PCI bridge, so its knobs sit in three tiers:
>
> - **Standard PCIe registers — one set *per port*, in config space. `lspci`/`setpci` reach all of them:**
>   *Link Control* (`CAP_EXP+0x10`: ASPM, Common-Clock, Retrain, Link-Disable) · *Link Control 2* (`+0x30`: Target Link Speed, de-emphasis) · *Device Control* (`+0x08`: MPS, MRRS, error-reporting enables) · *Slot Control/Caps* (`+0x18`: hot-plug, indicators) · *Bridge Control* (`0x3E`: **Secondary Bus Reset** — the big hammer — plus VGA/ISA forwarding).
> - **Extended capabilities (config space ≥ `0x100`), via `setpci ECAP_*`:** AER (Advanced Error Reporting) · L1 PM Substates · ACS (Access Control Services — governs peer-to-peer and matters for passthrough) · Secondary PCIe (per-lane equalization presets) · Virtual Channel.
> - **Vendor (PLX/Broadcom) registers — the *real* switch internals:** lane/port strapping (the x16-up + 8×x4-down split), SerDes (Serializer/Deserializer) equalization, NT (Non-Transparent) bridging, DMA (Direct Memory Access) engines, performance counters. These live in the switch **EEPROM** and proprietary register space — **no stock Linux CLI**; they need Broadcom's PEX SDK (the `PlxCm` "command monitor").
>
> **The CLI to try the reachable ones:**
> ```bash
> sudo lspci -vv  -s 02:09.0    # decoded: every standard capability + its live value
> sudo lspci -xxxx -s 02:09.0   # raw hex: ALL config space (standard, extended, vendor blob)
> setpci --dumpregs | less      # the register/capability names setpci understands
> sudo setpci -s 02:09.0 CAP_EXP+0x10.w          # read Link Control; append =val:mask to write
> ls /sys/bus/pci/devices/0000:02:09.0/          # sysfs knobs: current_link_speed, reset, remove…
> ```
> Tiers one and two you can read and (carefully) write today. The vendor tier is look-but-don't-touch without the SDK.

**1 — The draft under the door (finish the ASPM job).**
We disabled the nap on the card's port, but the switch's *upstream* link and its siblings are likely still napping. Check them all:

```bash
for p in 01:00.0 02:08.0 02:09.0 02:0a.0 02:10.0; do
  printf '%s ' "$p"; sudo lspci -vv -s $p | grep -o 'ASPM [A-Za-z0-9]*' | head -1
done
```

If the *uplink* (`01:00.0`) still says `ASPM L1`, that's the real danger: when the uplink naps and fumbles its wake, it drops *everything* behind the switch at once — card included. Same death, one floor up. Clearing it costs a couple of idle watts and nothing else. **This is the dial to turn first.**

**2 — The firmware standoff (`pcie_ports=native`).**
Tell the OS "disable ASPM everywhere" and it may just shrug. Here's why:

```bash
cat /proc/cmdline | grep -o 'pcie_aspm=off'     # is the flag even set?
sudo journalctl -k -b | grep '_OSC'             # "not requesting OS control" = firmware owns ASPM
```

That `_OSC` line — the **_OSC (Operating System Capabilities)** handshake — is the firmware saying *"I've got this,"* then not. Overrule it by adding `pcie_ports=native` to the kernel command line; as a bonus it switches on **AER (Advanced Error Reporting)**, the link's black-box recorder:

```bash
sudo dmesg | grep -i aer                                 # error events, once AER is live
sudo lspci -vv -s 04:00.0 | grep -E 'CESta|UESta'        # correctable / uncorrectable counters
# TOUCH: add pcie_ports=native to GRUB_CMDLINE_LINUX_DEFAULT, then `sudo update-grub && reboot`
```

> **Risk: MEDIUM.** You're overruling the firmware — most server boards tolerate it; some repay you with spurious error spam. A reboot to babysit.

**3 — The gearbox (link speed).**
A PCIe link is an automatic transmission: idle it coasts in first gear — Gen1, 2.5 GT/s (gigatransfers per second) — and under load kicks to Gen3, 8 GT/s. Watch it shift:

```bash
cat /sys/bus/pci/devices/0000:04:00.0/current_link_speed   # "2.5 GT/s" idle ↔ "8.0 GT/s" loaded
cat /sys/bus/pci/devices/0000:04:00.0/max_link_speed
sudo lspci -vv -s 04:00.0 | grep -E 'LnkSta:|LnkCtl2:'     # LnkCtl2 = the pinned Target Link Speed
```

You *can* weld it into one gear (`CAP_EXP+0x30.w`, then force a retrain) — but pin it low and you've throttled a firehose to a trickle; pin it high and a marginal link still drops. The shifting is *normal*, not the bug. **Leave it in Drive.**

**4 — The envelope size (MPS / MRRS).**
Data crosses in packets — **TLPs (Transaction Layer Packets)** — and **MPS (Maximum Payload Size)** / **MRRS (Maximum Read Request Size)** set how big each envelope is. Mismatch them across a switch and you get torn packets and exactly the flakiness we're hunting:

```bash
sudo lspci -vv -s 04:00.0 | grep -E 'DevCtl:|MaxPayload|MaxReadReq'   # must agree end-to-end
```

Ours read a consistent 256 bytes. The trap is greed — cranking the size up (`pci=pcie_bus_perf`) invites errors through a marginal switch. **It's fine. Don't touch it.**

**5 — The analog black art (equalization / de-emphasis).**
At Gen3, signal integrity over a cable lives and dies by the transmitter's **equalization** — waveform tuning measured in decibels of "de-emphasis." You can read it, but not safely rewrite it:

```bash
sudo lspci -vv -s 02:09.0 | grep -iE 'de-emphasis|LnkSta2|Equalization'   # LOOK only
```

Changing it means the Broadcom/PLX **SDK (Software Development Kit)** and an **EEPROM (Electrically Erasable Programmable Read-Only Memory)** reflash. Open-heart surgery, not a knob. **Lab-only.**

**6 — The rest of the bench (hot-plug, re-strapping).**
A phantom "device removed" signal *could* masquerade as Xid 79 — so check whether the port even does hot-plug:

```bash
sudo lspci -vv -s 02:09.0 | grep -i 'SltCap:'   # ours: "HotPlug- Surprise-" → nothing to do
```

Ours doesn't. Re-strapping the switch to wider lanes lives back in that EEPROM (vendor tool, HIGH risk). Out of scope.

## The verdict

The thrill of a switch chip is the dozen things to fiddle with. The discipline is doing almost none of them. **One move wins on payoff-to-peril: extend the ASPM shut-off to *every* port on the PEX 8749, not just the card's** — closing the upstream trapdoor, the very mechanism that bit us first. Pair it, if you're brave and watching the reboot, with native control for error visibility. Everything else is a speed regression or a soldering-iron-grade firmware job — and the boring fix that actually mattered was reseating the cable until the signal came clean.

The card was never broken. The chip was never broken. A feature meant to save electricity was quietly assassinating a workstation — and the cure was knowing the difference between the dial that helps and the eleven that don't.

---

### Cheat sheet: the dials, rated

| # | The dial | What you'd gain | Risk | Verdict |
|---|----------|-----------------|------|---------|
| 1 | Disable ASPM on **all** switch ports | Closes the upstream-sleep trapdoor (last Xid 79 path) | LOW | ✅ Do it |
| 2 | `pcie_ports=native` | Native link control + AER error visibility | MEDIUM | ⚠️ Brave reboot |
| 3 | Pin link speed (gearbox) | Stops gear-shift retraining | MEDIUM + bandwidth tax | 🟡 Hold |
| 4 | MPS / MRRS (envelope size) | — (already sane at 256 B) | LOW; HIGH if raised | 🟡 Leave |
| 5 | Tx equalization / de-emphasis | Could rescue a marginal link | HIGH (EEPROM/SDK) | ❌ Vendor tool only |
| 6 | Re-strap widths / hot-plug | More per-port bandwidth | HIGH / N-A | ❌ Out of scope |

---

### When it's already on fire: the 60-second triage

1. **Confirm** — `sudo dmesg | grep -iE 'Xid 79|Xid 154'`. `79` = fell off; `154` = won't self-recover.
2. **Recover** — Xid 154 needs a **cold power cycle** (PSU — Power Supply Unit — off ~30 s). A warm `reboot` just re-wedges it.
3. **Suspect** — `sudo lspci -vv -s 02:09.0 | grep LnkCtl`. `ASPM L1`? That's your cause.
4. **Override** — still `ASPM L1` after `pcie_aspm=off`? Firmware owns it (`journalctl -k -b | grep _OSC`) → use `setpci` (#1) or `pcie_ports=native` (#2), and don't forget the uplink `01:00.0`.
5. **Physical** — ASPM off but `current_link_speed` stuck at 2.5 GT/s under load, or `CESta/UESta` counters climbing? Reseat or swap the cable.
6. **Verify** — all ports `ASPM Disabled`, `systemctl is-active disable-gpu-aspm.service`, and `dmesg | grep -c 'Xid 79'` reads `0` after a long load test.

---

*No probes were energized writing this — it's the plan, risk-rated, awaiting the "go." On approval: extend the ASPM shut-off across all PEX 8749 ports (in `mk/system/hardening.mk`), and log the upstream-sleep gap in the risk register, `Lab/RISKS.md`.*
