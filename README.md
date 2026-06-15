# The Cost of Luxembourg: Automated EU Data Sovereignty for Distributed Systems

> "Many data transfers later, facing a €1.2 billion fine from Ireland's Data Protection Commission, Meta's leadership would remember the decade when someone decided that EU user data and American servers were an infrastructure detail, not a regulatory question..."

## The Architecture of a Fine

The 2023 ruling by the European Data Protection Board (EDPB) wasn't just a legal milestone; it was a structural indictment of modern cloud architecture. For two decades, engineering organizations built distributed systems under a simple assumption: network latency matters, but geographic borders do not. 

When user data flows seamlessly from a frontend client to an AWS cluster in `us-east-1`, it is a marvel of modern infrastructure. It is also, as courts in Luxembourg have repeatedly ruled, a potential compliance failure.

Standard Contractual Clauses (SCCs) are no longer a blanket shield. If your application handles European Union citizens' personal data (PII) and cross-border replication happens silently at the database layer, you aren't just taking on technical debt—you are taking on sovereign liability.

**[Project Name]** was built to turn regulatory constraints into structural invariants. It treats data sovereignty not as an afterthought handled by legal teams via annual audits, but as a hard engineering primitive.

---

## The Core Invariant: Geometry Over Topology

Most compliance tools operate at the application layer, using post-hoc logging, auditing, or reactive database queries to flag violations after the data has already crossed an ocean. 

This project operates at the routing and storage layer, enforcing **Geographic Data Invariants**. By intercepting data flows before serialization, it guarantees that:

* **Strict Regional Isolation:** EU user payloads are mathematically restricted from entering non-compliant regions without explicit, cryptographic consent tokens.
* **Zero-Knowledge Cross-Border Sync:** While global metadata can be synchronized for global availability, actual user identities are tokenized and decoupled at the boundary.
* **Deterministic Sovereignty Routing:** Built-in middleware for Next.js, Go, and FastAPI that dynamically routes requests based on real-time geolocation and sovereign headers.

---

## Quick Start: Drawing the Borders

Add the compliance proxy to your existing cluster configuration to enforce physical boundaries on your network traffic.

### 1. Install the Middleware
```bash
pip install sovereignty-core
```

Local LLM inference platform for validating EU-regulated workloads before cloud spend. Primary use case: content moderation at fashion e-commerce scale — 22M+ moderation events/year, where GDPR Article 17 (right to erasure) and DSA Article 17 (audit logging) are architectural constraints that shape inference cost, not legal afterthoughts. Hardware target: 4× RTX PRO 6000 Blackwell Max-Q (96 GB GDDR7 each, 384 GB total) through a PEX88048 PCIe switch, targeting Qwen3.5-397B-A17B at 120–150 tok/s under 1.5 kW. Built on the only DDR4 SODIMM board in the multi-GPU niche — reusing existing memory during the 2026 RAM crisis. GPUs deferred; PCIe switch under bench validation.

---

## Prefix caching for EU-regulated content moderation

[`demos/prefix-caching/prefix_caching_demo.ipynb`](demos/prefix-caching/prefix_caching_demo.ipynb)

Models vLLM prefix caching architecture for a content moderation platform serving a 100K-SKU fashion catalog. Runs on Colab or Kaggle (T4). What each experiment measures:

- **Prefix hierarchy**: three-layer block-hash chain — DSA policy prefix (stable, always a cache hit) → per-SKU review corpus (stable until GDPR erasure) → session audit token + comment (always cold). Token placement order is the architectural decision; the notebook quantifies the consequence of getting it wrong.
- **GDPR Art. 17 erasure cost**: removing a reviewer's data invalidates the cached prefix for all co-reviewers of that SKU. At 0.1% monthly erasure rate across 100K SKUs, models the GPU re-warm cost and projects annual infrastructure impact.
- **DSA Art. 17 audit token placement**: session token placed before vs. after the review corpus. Wrong placement eliminates all prefix cache hits. Computes annual GPU-hours wasted at platform scale.
- **Catalog-scale cache planning**: INT4 KV bytes per SKU prefix, hot-tier VRAM capacity on T4 vs. target hardware, Zipf-distributed traffic model (20% of SKUs absorb 80% of requests).
- **KV quantization**: INT4 breakeven — VRAM recovered vs. precision cost at 100K-SKU scale.

```bash
make colab-upload    # push + open in Colab
make kaggle-run      # push to Kaggle, poll, download output
make demo-notebook   # run locally in Jupyter
```

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
