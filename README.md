# The Memory Hole: Sovereign Cache Planning for LLMs at Scale

> "The notification arrived from Dublin on a Tuesday. The figure on the page was €1.2 billion—a sum that successfully downgraded a decade of cross-border infrastructure planning to a rather expensive misunderstanding..."

## The Anatomy of an Outage (Legal, Not Technical)

The infrastructure worked perfectly. Every load balancer from California to Frankfurt was operating within nominal parameters. Latency was low, throughput was at an all-time high, and replication across the Atlantic was happening continuously, automatically, and silently. 

That was the exact problem. 

The Irish Data Protection Commission’s 2023 ruling against Meta proved a paradox: a perfectly optimized global network is, under current EU law, a beautifully engineered liability. While engineering teams were optimizing for millisecond replication across global availability zones, they were unwittingly constructing a pipeline that treated sovereign borders with a level of indifference usually reserved for routine system maintenance.

Standard Contractual Clauses (SCCs) and corporate privacy frameworks held up perfectly—right until a court in Luxembourg decided to read the statute.

### From Network Packets to Token Hashing

Many sprints later, facing their own architecture review, a different team of engineers would remember that Tuesday. They would realize that the legal chasm between European data rights and American compute didn't just apply to trans-Atlantic database replication. It applied directly to the memory arrays of their own Large Language Models.

They had treated the right to erasure as a downstream product concern, handled by a database script. They did not realize it was actually a mathematical property of their inference cache.

This notebook demonstrates **prefix caching** in vLLM applied to a real-world fit-feedback moderation workload. It exposes the hidden compliance liabilities of stateful LLM inference under Digital Services Act (DSA) content moderation obligations and General Data Protection Regulation (GDPR) deletion requirements.

* **Runtime:** T4 GPU (Free Google Colab tier is sufficient)
* **Model:** `Qwen/Qwen2.5-7B-Instruct-AWQ` (~4 GB, optimized for T4)

---

## The Scale of the Constraint

Consider a fashion retail platform processing **22,300,000 fit-feedback comments per year**. Each free-text submission carries three simultaneous legal obligations under continental law:

1. **Content Moderation:** Handled under Digital Services Act (DSA) Article 17 using a persistent corporate policy.
2. **Right to Erasure:** Handled under GDPR Article 17, allowing any reviewer to delete their historical comment at will.
3. **Traceability:** Ensuring every automated moderation decision remains tied to a unique session token for compliance audits.

To support this volume without collapsing under the weight of $O(n^2)$ prefill compute costs, the context must be stratified. The order of tokens determines whether your system runs at near-zero marginal cost or hemorrhages money on redundant GPU cycles.


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
