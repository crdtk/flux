---
name: Workstation Usage, Not Headless
description: The ASRock E3C256D4I-2T build is a workstation with direct keyboard and multiple monitors — not a headless server
type: project
originSessionId: 742e51d0-dbf3-40f5-8c69-aaf265a29e95
---
The ASRock Rack E3C256D4I-2T LLM inference build is a **workstation**, not a headless server.
User sits in front of it with a keyboard and multiple monitors connected directly.

**Why:** Primary user interaction is local, not SSH. The machine needs a full desktop environment
(not Ubuntu Server TTY-only). KDE Plasma or similar is appropriate.

**How to apply:**
- Do NOT recommend Ubuntu Server for this rig
- DO recommend Kubuntu 26.04 LTS (stable Apr 23 2026) or Arch Linux with KDE
- Multiple monitors must be supported — ensure graphics output works (via onboard VGA/BMC or a display-capable GPU)
- BMC VGA on the ASRock E3C256D4I-2T only drives one low-res output via AST2500 — insufficient for multi-monitor workstation use
- The RTX PRO 6000 Max-Q GPUs have display outputs (yes, blower workstation cards have DP outputs) — use these for multi-monitor
