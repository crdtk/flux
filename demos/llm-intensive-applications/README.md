# Building LLM-Intensive Applications

A hash map, served from real attention internals, walked through CRUD.

Companion to [`demos/prefix-caching/`](../prefix-caching/), for a different reader: someone who has read Martin Kleppmann's *Designing Data-Intensive Applications* and Sebastian Raschka's *Build a Large Language Model (From Scratch)*, and wants the KV (Key-Value) cache itself treated as a database — Create, Read, Update, Delete — backed by real attention math instead of a vLLM server's reported latency.

**Runtime:** local only — no Colab, no vLLM. CPU works; a CUDA GPU is faster but not required.
**Model:** [`Qwen/Qwen3.5-0.8B`](https://huggingface.co/Qwen/Qwen3.5-0.8B) (~3.8 GB in bfloat16), loaded through Sebastian Raschka's from-scratch reimplementation already checked out at [`demos/LLMs-from-scratch/ch05/16_qwen3.5/`](../LLMs-from-scratch/ch05/16_qwen3.5/).

---

## Why this model

Qwen3.5 alternates `full_attention` layers (classic growing KV) with `linear_attention` layers (a gated delta-net — Qwen3-Next's VRAM trick: a fixed-size recurrent state instead of a tensor that grows with context length). Both cache shapes are real and inspectable here, not hidden behind a server. `demos/prefix-caching/` answers "what does the cache cost." This demo answers "what is the cache, mechanically."

---

## What's in this folder

- **`qwen3_5_kv.py`** — Raschka's `Qwen3_5Model`, `KVCache`, `Qwen3_5LinearAttentionCache`, tokenizer, and weight loader, ported verbatim from his `qwen3.5-plus-kv-cache.ipynb` (cited inline, Apache License 2.0). `Qwen3_5GatedDeltaNet` is imported directly from his `qwen3_5_transformers.py`, itself copied from Hugging Face Transformers (Apache 2.0). The one new piece is `PromptCacheStore`: a dict keyed by SKU, each value a snapshot of that key's attention state, with `warm()`, `ask()`, `delete()`, and a byte-level memory report split by attention type.
- **`llm_intensive_demo.ipynb`** — loads the checkpoint, builds the SKU hash map (the same fit-feedback dataset as the prefix-caching demo), and runs it through CREATE / READ / UPDATE / DELETE.

---

## Running

```bash
make llm-intensive-demo   # registers a dedicated "raschka" Jupyter kernel, opens the notebook locally
```

The kernel points at `demos/LLMs-from-scratch/venv` (a separate venv from the rest of the repo, since this demo depends directly on that checkout's modules). First run downloads the checkpoint (~3.8 GB) to `Qwen3.5-0.8B/` inside this folder.

---

## Attribution

`qwen3_5_kv.py` contains code from [rasbt/LLMs-from-scratch](https://github.com/rasbt/LLMs-from-scratch) (Apache License 2.0) and, transitively through `qwen3_5_transformers.py`, from [huggingface/transformers](https://github.com/huggingface/transformers) (Apache License 2.0). See `demos/LLMs-from-scratch/LICENSE.txt`.
