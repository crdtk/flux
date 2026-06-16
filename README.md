# The Cache Must Forget

Many data transfers later, facing a €1.2 billion fine from Ireland's Data Protection Commission, Meta's leadership would remember the decade when someone decided that EU user data and American servers were an infrastructure detail, not a regulatory question. At that time the platform was becoming global: data centers in Oregon and North Carolina, engineering in Menlo Park, hundreds of millions of European users whose messages and photographs and behavioral profiles crossed the Atlantic with every interaction. The transfers happened continuously, automatically, at a scale that made them invisible. Safe Harbor was in place, then Privacy Shield, then Standard Contractual Clauses — each one a legal instrument the company believed was adequate, each one later ruled insufficient. It was not the only fine. By then, European regulators had issued more than two thousand eight hundred penalties, accumulating over six billion euros across the continent. The largest came from Ireland — the same jurisdiction Meta had chosen for its tax treaties and its reputation for light-touch regulation, the same authority that other European regulators had long criticized for moving too slowly. It had not been moving slowly. It had been building a case. The world was so recent that many things lacked enforcement, and in order to discover their cost it was necessary for a court in Luxembourg to rule.

The fine was announced in May 2023. The legal basis was GDPR Article 46 — international transfers without adequate safeguards. The Court of Justice of the European Union had already ruled in 2020 that American surveillance law created access rights no contractual clause could override. Meta had continued the transfers anyway. The remediation order required not only payment but cessation of new transfers and deletion of EU user data already processed unlawfully. The compliance infrastructure that followed — data localization, architectural separation, legal restructuring across jurisdictions — cost more than the fine. That cost is now a line item in every AI product roadmap operating in Europe, whether or not the engineering team has named it yet.

The right to erasure is not a legal footnote. It is a cache invalidation event with a measurable GPU cost. The audit trail is not a reporting requirement; it is a token whose position in the prompt determines whether an inference system wastes thousands of GPU-hours annually or none. Content moderation at platform scale is not a policy document; it is a shared prefix that must be computed once and reused across twenty-two million requests per year, or paid for again at each one. These are engineering decisions. They have regulatory consequences. The sequence in which an organization discovers this — in a planning session or in an enforcement order — is the only variable still open.

Crucible is a local LLM inference platform for validating EU-regulated workloads before cloud spend. The demo runs on a free GPU. The hardware is in the lab.

[`demos/prefix-caching/prefix_caching_demo.ipynb`](demos/prefix-caching/prefix_caching_demo.ipynb) runs five experiments against a fashion retail content moderation platform: 22M fit-feedback comments per year, GDPR Article 17 right-to-erasure obligations, DSA Article 17 audit logging requirements. The notebook opens with Joy Hansen — a reviewer whose post-pregnancy measurements are now held in a server — and follows what happens when she asks for them back. Three things emerge from the measurement. The Erasure Penalty: one deletion changes one fingerprint and invalidates every cached request built on that reviewer's profile, priced at platform scale. The Alignment: DSA Article 17 and the cache's mathematical structure arrived at the same architectural answer by entirely independent reasoning, which means getting the audit token placement wrong is not a trade-off between legal caution and performance — it is a simultaneous loss on both. The Regulatory Pincer: moving the session identifier outside the prompt solves the placement problem and creates a harder one, where GDPR Article 17 and DSA Article 17 both apply to the same audit rows with opposite requirements. No schema resolves this. The notebook runs on Colab or Kaggle, free tier, T4 GPU.

```bash
make colab-upload    # push + open in Colab
make kaggle-run      # push to Kaggle, poll, download output
make demo-notebook   # run locally in Jupyter
```

The full article: [`demos/prefix-caching/miller_article.md`](demos/prefix-caching/miller_article.md)

---

## Hardware

The inference rig is built on the narrowest constraint in the multi-GPU niche: a board that accepts DDR4 SODIMMs and provides enough PCIe lanes for four high-end GPUs through a switch. Most server boards in this category use RDIMMs. The ASRock Rack E3C256D4I-2T does not. The target configuration holds 384 GB GDDR7 across four GPUs, sufficient to run Qwen3.5-397B-A17B at 120–150 tokens/second under 1.5 kW. The GPU order is deferred until the PCIe switch path is validated under load.

| Component | Part |
|---|---|
| Motherboard | ASRock Rack E3C256D4I-2T (4× SODIMM, PCIe 4.0 x16 bifurcation) |
| CPU | Intel Xeon E-2314 (LGA1200, 20 PCIe 4.0 lanes) |
| RAM | 2× Samsung M471A2K43BB1-CPB — 32 GB DDR4-2133 SODIMM |
| GPU (active) | NVIDIA RTX A4000 (16 GB GDDR6, 140 W) — current development GPU |
| GPU (target) | 4× NVIDIA RTX PRO 6000 Blackwell Max-Q (96 GB GDDR7, 300 W) — deferred until PCIe switch validated |
| PCIe switch | PEX88048 via HighPoint Rocket 1528D — bench-testing with PLX PEX 8749, link at Gen1 x4 (reseating in progress) |
| Storage (boot) | Samsung 9100 PRO 8 TB (M.2) |
| Storage (models) | WD_BLACK SN8100 8 TB (OCuLink via Tekram TK-2U11) |
| Case | Phanteks Enthoo Pro 2 |
| PSU | be quiet! Dark Power Pro 13 1600W |
| Cooling | Full custom water loop — CPU + 4 GPUs + PEX88048 |

---

## Lab automation (`mk/`)

Every repeatable action is a Makefile target — no raw shell commands.

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

See [`RISKS.md`](RISKS.md) for the full risk register (thermal, electrical, firmware, PCIe).
