# vLLM Prefix Caching Demo

A Colab notebook demonstrating how prefix caching in vLLM eliminates redundant prefill computation across requests that share a common context.

**Runtime:** Colab free tier (T4, 16 GB VRAM)
**Model:** `Qwen/Qwen2.5-7B-Instruct-AWQ` (~4 GB)

---

## The mechanism

Every LLM request has two phases:

| Phase | Cost |
|---|---|
| Prefill | O(n²) in context length — slow |
| Decode | O(n) per token — fast |

vLLM splits the context into 16-token blocks, hashes each block chained with the previous one, and stores the computed KV state. On the next request, matching hashes = free prefill.

```
block 1: hash([system_prompt tokens])        → h1
block 2: hash([shared_context tokens] + h1)  → h2  ← reused if identical
block 3: hash([user_query tokens]    + h2)   → h3  ← always computed fresh
```

---

## Three experiments

**1 — Cold vs warm cache**
Three customers query a sizing assistant with the same product reviews but different questions. The first request pays full prefill; the next two are cache hits.

**2 — What defeats the cache**
Same reviews, shuffled order per request. One token difference anywhere in a block produces a different hash → every request is a miss. Demonstrates that stability of the shared prefix is the design constraint.

**3 — Dynamic content placement**
A session ID injected *before* the shared context shifts all subsequent token positions → hash mismatch from block 1 onward. The same session ID placed *after* the shared context leaves the cache intact.

---

## KV quantization

Math cell showing why INT4 fits 4× more contexts before LRU eviction. Qwen2.5-7B: 28 layers × 2 (K+V) × 8 heads × 128 head_dim = 57,344 values per token — FP16 costs 112 KB/token, INT4 costs 28 KB/token.

---

## Running

```bash
make colab-upload   # copies notebook to Google Drive and opens it in Colab
make demo-notebook  # opens locally in Jupyter for editing
```
