# The Memory Hole: Sovereign Cache Planning for LLMs at Scale

> "Many sprints later, facing a €1.2 billion fine, the engineers would remember that afternoon when someone decided the right to erasure was a product concern, not a property of the cache."

## The Architecture of a Fine

Every Large Language Model request arrives twice: once as computation, once as memory. 

In high-throughput inference engines like vLLM, **Prefix Caching** hashes incoming context in blocks of 16 tokens, chaining each block cryptographically to the previous one. If a hash matches on a subsequent request, the system skips the expensive $O(n^2)$ prefill phase and jumps straight to token generation. The cache remembers. 

But modern platforms do not operate in a legal vacuum. The European Union's General Data Protection Regulation (GDPR) demands that systems forget, granting users the absolute right to erasure. 

When these two realities collide in a production cluster—where user data is baked into cached KV pairs to optimize inference latency—compliance ceases to be a product feature. It becomes a hard engineering invariant at the storage layer. Failure to decouple stable policy from mutable personal data does not just degrade performance; it creates a structural liability that compounds until it surfaces in a regulatory audit.

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
