# TurboQuant Fit Recommendation Demo

> **The core insight:** A BERT encoder runs in 5 ms and turns a customer's 3-year return history into a
> 500-token structured profile. The LLM only ever sees that profile — not the raw history. More history
> means *higher-confidence* structured data, which means *fewer* tokens for the LLM, not more.
> TurboQuant then compresses the LLM's KV cache 5× so the remaining decode step fits in 450 ms,
> synchronous with a page load.

---

## The business problem

Returns cost fashion retailers 20–30% of revenue. Most platforms today show the same size chart to every
customer. A customer who has returned the same Levi's cut three times for the same reason — thighs too
tight — should never be shown that cut again without a clear warning and an alternative.

The challenge is doing this in real-time, at the point of purchase, for every customer, across a catalogue
of thousands of items with different cuts, fits, and brand conventions.

---

## Architecture

```
Customer: "too tight in thighs, waist was perfect"
              ↓
         ┌────────────┐
         │    BERT    │  5 ms · GPU or CPU
         │  (encoder) │  structured extraction
         └────────────┘
              ↓
  {region: thigh,  direction: too_tight, confidence: 0.97}
  {region: waist,  direction: correct,   confidence: 0.95}
              ↓
         ┌────────────┐
         │  Routing   │  1 ms
         │ classifier │  clear signal or complex case?
         └─────┬──────┘
          ↓           ↓
    standard (95%)  complex (5%)
        ↓                 ↓
  ┌──────────┐     ┌──────────────────────┐
  │  lookup  │     │  DeepSeek-R1 + TQ    │
  │  table   │     │  incremental KV      │
  │   2 ms   │     │       450 ms         │
  └──────────┘     └──────────────────────┘

Average latency: 2ms × 0.95 + 450ms × 0.05 ≈ 25 ms
Fast enough to be synchronous with page load.
```

---

## What BERT extracts

Each return text becomes a structured signal that accumulates into a profile:

| Return text | BERT output |
|---|---|
| "too tight in thighs" | `{region: thigh, fit: -1}` |
| "waist fit perfectly" | `{region: waist, fit: 0}` |
| "runs large overall" | `{region: global, fit: +1}` |
| "narrow in the shoulders" | `{region: shoulder, fit: -1}` |

Aggregated over 47 purchases, a customer profile emerges:

```
thigh_width:      wide    (8 returns, confidence: 0.91)
waist_hip_ratio:  0.78    (derived from kept vs returned)
shoulder_width:   narrow  (3 returns, confidence: 0.74)
preferred_rise:   mid     (inferred from kept items)
```

**The LLM never sees the 47 raw returns.** It reasons over this ~500-token summary. A customer with
10 returns and one with 100 returns send the same size context to the LLM — but the 100-return
customer's profile has higher confidence scores, so the LLM's answer is more decisive.

---

## When the LLM is actually needed

**BERT handles (95%):** clear, unambiguous signal

- "too tight" / "too large" / "runs small" / "perfect fit"
- Lookup table, 2 ms, no GPU required

**LLM needed (5%):** ambiguous or cross-brand reasoning

- *"fits my waist but I can't button it after lunch"*
- *"bought both M and L — the M looks better but L is more comfortable"*
- *"first time buying this brand, not sure about European sizing"*
- *"I'm between sizes and this is a structured blazer"*

The routing classifier is itself a fine-tuned BERT. It decides whether the LLM spend is justified.

---

## From batch job to real-time retention tool

This is where the system becomes a product. The difference is whether you recompute or extend.

**The naive pipeline (too slow):**

```
Customer submits return: "too tight in thighs"
    ↓  100ms   feedback parsed and appended to history
    ↓ 8,000ms  full re-inference over 50k-token history
    ↓  100ms   recommendation pushed to UI
────────────────────────────────────────────────────
Total: ~8 seconds   ← user has already closed the tab
```

**The incremental KV pipeline:**

The customer's existing history didn't change — only one new item was appended.
If you store the compressed KV states from prior inference:

```
Existing 50k history:  KV already computed and stored (TQ-compressed)
New return item:       ~250 tokens → compute only this delta
Re-run attention:      fast forward pass over cached states

New compute:  250 tokens instead of 50,000
Complexity:   O(new tokens) instead of O(context length)
```

```
Customer submits return: "too tight in thighs"
    ↓   50ms   BERT extracts {item: Levi's 501, issue: thighs, direction: tight}
    ↓   30ms   appended to TQ-compressed KV store (append-only log)
    ↓  150ms   delta inference: 250 new tokens + attention over cached KV
    ↓  150ms   speculative decode → "Based on your return of Levi's 501..."
    ↓   50ms   push to UI
────────────────────────────────────────────────────────────────────────────────
Total: ~430ms   ← recommendation appears before they close the return screen
```

Sub-500 ms is the threshold where it feels like the UI responded to you, not like a job ran.

**What this changes for the business:**

| | Without incremental KV | With incremental KV + TQ |
|---|---|---|
| Recommendation update | Nightly batch job | While customer is on the return screen |
| Customer sees | Updated suggestion tomorrow | *"Since you found these too tight in the thighs, customers with similar profiles prefer the 34W 30L or the relaxed fit in your usual size"* — before they close the tab |
| Product role | Logistics tool | Retention tool |

**The architecture:**

```
                    ┌─────────────────────────┐
Customer action ───▶│  Feedback Service       │
                    │  BERT parse + structure  │
                    └────────────┬────────────┘
                                 │ structured event
                    ┌────────────▼────────────┐
                    │  TQ KV Store            │
                    │  append-only log        │◀─── cold precompute
                    │  per-customer, indexed  │     at login / page load
                    └────────────┬────────────┘
                                 │ delta (~2 KB per interaction)
                    ┌────────────▼────────────┐
                    │  Recommendation Engine  │
                    │  delta inference only   │
                    │  + speculative decode   │
                    └────────────┬────────────┘
                                 │
                    ┌────────────▼────────────┐
                    │  Push to UI             │
                    │  SSE / WebSocket        │
                    └─────────────────────────┘
```

The TQ-compressed KV store is the novel piece — a persistent, append-only cache of each customer's
inference history in compressed form. Each new interaction adds ~2 KB (250 tokens × 3b key / 2b val)
rather than recomputing 50k tokens from scratch.

---

## Full latency picture

| Path | Latency | Triggered by |
|---|---|---|
| BERT → lookup | 8 ms | clear fit signal (95% of traffic) |
| BERT → LLM (cold, full history) | 5–8 s | first-ever recommendation |
| BERT → LLM (warm, incremental KV) | **430 ms** | new return, KV cache warm |
| BERT → structured profile → LLM | 80 ms | complex case, profile exists |

**Component breakdown (warm path):**

| Component | Latency | Bottleneck |
|---|---|---|
| BERT extraction | 20–50 ms | GPU compute |
| KV store append (TQ-compressed) | 10–30 ms | memory write |
| Delta inference (250 new tokens) | 80–150 ms | GPU compute |
| Speculative decode (128-token response) | 80–150 ms | GPU memory bandwidth |
| Push to UI | 20–50 ms | network |
| **Total** | **210–430 ms** | |

Cold inference (first visit, full history) takes 3–8 s — acceptable as a page-load precompute,
not acceptable as a real-time response. The incremental path is what enables the real-time product.

---

## TurboQuant: why the LLM layer needs it

Even at 500 tokens, the LLM decode step is bottlenecked by memory bandwidth — the GPU must read every
weight and every KV cache entry on every generated token. TurboQuant quantizes the KV cache to
3-bit keys / 2-bit values, reducing memory traffic by ~5× on the attention layer.

**Benchmark — RTX A4000 (SM86, 448 GB/s), DeepSeek-R1-Distill-Qwen-7B-AWQ:**

| Context tokens | Baseline tok/s | TQ tok/s | Improvement | % of peak BW |
|---|---|---|---|---|
| 1 024 | 47.3 | 55.3 | **+17%** | 75% |
| 2 048 | 61.0 | 65.8 | **+8%** | 90% |
| 4 096 | 54.4 | 62.9 | **+16%** | 88% |
| 8 192 | 54.3 | 59.0 | **+9%** | 85% |

The A4000 is running at 75–90% of its theoretical memory bandwidth ceiling — this is close to the
hardware limit for a decode-bound workload.

---

## Why these two models have opposite hardware profiles

```
Arithmetic intensity (FLOP / byte)
                                   │
compute-bound                      │             ● BERT (batched encoder)
(tensor cores matter)              │           ╱
                                   │         ╱  roofline
                                   │       ╱
memory-bound                       │     ╱
(bandwidth matters)       ● LLM ╱
(TQ helps here)                    │
                                   └─────────────────────────────────────
                                              Arithmetic intensity →
```

| | BERT | LLM decode |
|---|---|---|
| Operation | Full sequence in parallel | One token at a time |
| Arithmetic intensity | High (matmuls over full batch) | Low (reads weights per step) |
| Roofline position | Compute-bound | Memory-bound |
| Optimization lever | Tensor cores, batch size, sequence packing | Bandwidth, KV compression (TurboQuant) |

Two models, opposite ends of the roofline, complementary roles in the same pipeline.

---

## Running the demo

**Prerequisites:** NVIDIA GPU with ≥ 16 GB VRAM (tested on RTX A4000).

```bash
# 1. Download the model (one-time, ~5.2 GB)
make demo-model

# 2. Start both vLLM servers (baseline + TurboQuant, sequential on single GPU)
make demo-servers

# 3. Run benchmarks
make bench-bert        # BERT extraction latency (~5 ms warm)
make bench-tq          # tok/s sweep across context lengths, writes bench_results.json
make bench-pipeline    # end-to-end BERT + LLM pipeline (~500 ms)

# 4. Load test (baseline :8001 vs TQ :8000 in parallel)
make bench-locust                                   # 4 users, 60 s
make bench-locust LOCUST_USERS=8 LOCUST_TIME=120s
make locust-ui                                      # interactive UI on :8089

# 5. Streamlit side-by-side demo
make demo-fit          # opens on :8501
```

**The Streamlit demo** streams responses from both servers simultaneously for two scenarios:
a fashion size recommendation (47-item purchase history) and a legal liability clause
analysis (long-context stress test).

---

## Repository layout

```
turboquant-demo/
├── turboquant_demo/
│   ├── bert.py          # zero-shot NLI fit-signal extraction
│   ├── sweep.py         # tok/s + GB/s benchmark across context lengths
│   ├── latency.py       # end-to-end pipeline latency measurement
│   ├── app.py           # Streamlit side-by-side streaming UI
│   └── locustfile.py    # Locust load test (BaselineUser + TQUser)
└── scripts/
    ├── start_servers.sh # sequential vLLM startup (baseline then TQ)
    └── stop_servers.sh  # graceful shutdown via PID files
```

Model: `casperhansen/deepseek-r1-distill-qwen-7b-awq` — DeepSeek-R1 reasoning quality in 5.2 GB,
same GQA architecture (28 layers, 4 KV heads, head\_dim=128) as the production target.

---

## Reference

**TurboQuant:** [arXiv:2504.19874](https://arxiv.org/abs/2504.19874) — ICLR 2026.
Lloyd-Max scalar quantization + QJL projection for KV cache compression.
3-bit keys / 2-bit values; ~5× reduction in attention memory traffic.
