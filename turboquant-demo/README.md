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

## Full latency picture

| Path | Latency | Triggered by |
|---|---|---|
| BERT → lookup | 8 ms | clear fit signal |
| BERT → LLM (cold, full history) | 5–8 s | first-ever recommendation |
| BERT → LLM (warm, incremental KV) | 450 ms | new item, complex case |
| BERT → structured profile → LLM | **80 ms** | complex case, profile exists |

The last row is the production sweet spot. BERT compresses history offline; the LLM reasons over
the summary in real-time.

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
