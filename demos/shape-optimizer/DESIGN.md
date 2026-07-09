# Shape Optimizer — Design Document

**Status**: Pre-implementation  
**Hardware**: RTX A4000 (SM86, 16 GB GDDR6) now · 4× RTX PRO 6000 Blackwell Max-Q (SM100, 96 GB GDDR7) on arrival  
**Problem**: GDPR (General Data Protection Regulation) / DSA (Digital Services Act) compliance forces every user-generated item through classification and every flag through a reasoned explanation — serving a 7B teacher on all of that traffic is the cost bottleneck  
**Deliverable**: a cascaded serving stack (encoder fast path + shape-optimized distilled decoder) that holds teacher accuracy within 5% at a fraction of the serving cost  
**Byproduct**: the workload's unusual attention shape yields a Triton kernel worth upstreaming — PR (Pull Request) to vLLM with benchmarked improvement

---

## 1. Problem Statement

Moderation is no longer work a platform can sample: the DSA obliges platforms to act on policy-violating content, and its Article 17 requires a "clear and specific statement of reasons" for every restriction. The GDPR adds personal-data exposure (FLAG:PII) to the same pipeline. Compliance therefore fixes the workload — **every** item gets classified, and **every** flag needs a generated explanation. What compliance does not fix is the serving bill.

A 7B teacher (Qwen2.5-7B-Instruct-AWQ) clears the accuracy bar on the SAFE / FLAG:PII / FLAG:HATE / FLAG:SPAM / FLAG:REVIEW taxonomy, but running a 7B decoder over 100% of traffic ties serving cost linearly to the very volume regulation forces you to process. The engineering question is the cheapest system that still holds the bar:

**What student model shape, when distilled from the moderation teacher, minimizes system serving latency on target hardware while staying within 5% of teacher accuracy?**

This is a bi-objective optimization over a discrete, hardware-constrained search space. The two objectives pull in different directions — optimal training-efficiency shapes differ from optimal serving-latency shapes. The criterion for a good serving shape is hardware saturation:

> "Choosing neural net topology shapes that fully saturate all hardware units — matmul FLOPs (Floating-Point Operations per Second), memory bandwidth, communication bandwidth — to get as high MFU (Model FLOPs Utilization) as possible during inference." — Vlad Feinberg, Google DeepMind

---

## 2. Production Use Case

**Teacher model**: Qwen/Qwen2.5-7B-Instruct-AWQ — already running in `demos/prefix-caching/prefix_caching_demo.ipynb`  
**Serving infrastructure**: vLLM with prefix caching (Experiment 2 in Notebook 1)  
**Accuracy floor**: Student must match teacher F1 (F-measure, harmonic mean of precision and recall) within 5% on the 10-query TEST_QUERIES confusion matrix from Notebook 1  
**Latency target**: P99 (99th percentile) TTFT (Time to First Token) < 50ms for the decoder stage under representative load

### 2.1 Cascaded Inference Architecture

The production serving stack uses two stages routing on encoder confidence. This matches how Twitter/X, Meta, and YouTube moderation pipelines are structured at scale.

```
Input text (20–150 tokens)
        │
        ▼
┌───────────────────────────────────────┐
│  Stage 1 — Encoder  (always runs)    │
│  Model: DistilBERT fine-tuned on     │
│         teacher soft labels           │
│  Latency: ~5ms  ·  86M params        │
│  Output: (label, confidence)          │
└───────────────┬───────────────────────┘
                │
    ┌───────────┴────────────┐
    │ confidence ≥ θ         │ confidence < θ
    │ (~80% of traffic)      │ OR recommendation_needed
    ▼                        ▼
SAFE / FLAG:X           ┌────────────────────────────────────┐
(done, no generation)   │  Stage 2 — Decoder  (slow path)   │
                        │  Model: shape-optimized student    │
                        │  Served: vLLM + prefix caching     │
                        │  Latency: ~40ms                    │
                        │  Output: label + explanation +     │
                        │          actionable recommendation  │
                        └────────────────────────────────────┘
```

**Stage 1** (encoder, fast path): DistilBERT (66M params) or DeBERTa-v3-base (86M params), fine-tuned on soft labels from the teacher. Not the subject of shape optimization — architecture is fixed. Serves ~80% of traffic with a single forward pass, no KV (Key-Value) cache required.

**Stage 2** (decoder, slow path): the custom student architecture found by the shape optimizer. Served by vLLM with prefix caching on the shared policy prefix. Generates a classification label plus a natural-language recommendation (e.g., "Flagged FLAG:PII — email address in line 2. Redact before publication.") — the statement-of-reasons artifact DSA Article 17 requires. The long shared prefix + short per-request query is what creates the interesting attention shape for kernel optimization.

**Confidence threshold θ**: a tunable parameter (default 0.95) added to the Bayesian optimization search space (Section 4.4). Higher θ → more traffic hits the decoder → higher latency, higher accuracy. Lower θ → more fast-path routing → lower latency, risk of missing edge cases.

**Why this workload is interesting for kernel optimization**: Stage 2 has a long shared KV cache (~500 tokens of policy prefix) and a short per-request query (64–100 tokens). This creates an attention shape where SEQ_Q << SEQ_KV, which is memory-bound differently from standard generation and likely reveals a distinct roofline position for the attention kernel — exactly the shape that a custom Triton kernel can exploit.

---

## 3. System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      OUTER OPTIMIZATION LOOP                     │
│                         (optimize_loop.py)                       │
│                                                                  │
│   ┌─────────────┐     ┌──────────────┐     ┌─────────────────┐  │
│   │  Bayesian   │────>│  papermill   │────>│  Trial Notebook  │  │
│   │  Opt        │<────│  runner      │<────│  (parameterized) │  │
│   │  (optuna)   │     │              │     │                  │  │
│   └─────────────┘     └──────────────┘     └─────────────────┘  │
│          │                                                        │
│          │ shape candidates                                       │
│          ▼                                                        │
│   ┌──────────────────────────────────────────────────────────┐   │
│   │               SWI-PROLOG REASONING LAYER                  │   │
│   │  prolog/hardware.pl  — GPU facts (SM86, SM100)            │   │
│   │  prolog/roofline.pl  — bottleneck classification rules    │   │
│   │  prolog/shapes.pl    — CLP(FD) shape constraint solver    │   │
│   │                                                            │   │
│   │  Python bridge: janus (bidirectional, in-process)         │   │
│   └──────────────────────────────────────────────────────────┘   │
│          │                              ▲                         │
│          │ valid shape list             │ kernel timing facts      │
│          ▼                              │                         │
│   ┌─────────────┐    ┌──────────────┐  │                         │
│   │   Triton    │    │  SQLite      │──┘                         │
│   │  Autotuner  │    │  parser      │                            │
│   │             │    │  (Python)    │                            │
│   └─────────────┘    └──────────────┘                            │
│                              ▲                                    │
│                              │ nsys export --type=sqlite          │
│                       ┌──────────────┐                           │
│                       │   Nsight     │                           │
│                       │   Systems    │                           │
│                       └──────────────┘                           │
│                              ▲                                    │
│                              │ profiles                           │
│                       ┌──────────────┐                           │
│                       │    vLLM      │  ← teacher inference       │
│                       │              │  ← production serving      │
│                       │              │  ← profiling target        │
│                       └──────────────┘                           │
└─────────────────────────────────────────────────────────────────┘
```

---

## 4. Component Specifications

### 4.1 Profiling Pipeline

**Tool**: Nsight Systems CLI (`nsys`)  
**Invocation**: `nsys profile --output=traces/run --trace=cuda,nvtx,osrt python -m ...`  
**Export**: `nsys export --type=sqlite --output=traces/run.sqlite traces/run.nsys-rep`  
**Key tables in output**:
- `CUPTI_ACTIVITY_KIND_KERNEL` — kernel name, start, end, grid dims, block dims
- `CUPTI_ACTIVITY_KIND_MEMCPY` — bytes transferred, direction, duration
- `StringIds` — maps integer IDs to kernel name strings

**scripts/extract_events.py** reads these tables, computes per-kernel:
- Duration (ns)
- Arithmetic intensity (FLOPs / bytes) — requires FLOPs annotation via NVTX markers or heuristic from kernel name
- Bandwidth utilization (bytes/ns vs. hardware roof)

Output: JSON facts for Prolog consumption.

### 4.2 SWI-Prolog Reasoning Layer

**prolog/hardware.pl** — hardware specification facts:
```prolog
hardware(sm86, compute_roof_tf32_tflops, 77.4).
hardware(sm86, compute_roof_fp16_tflops, 154.8).
hardware(sm86, memory_bandwidth_gbps,    448).
hardware(sm86, tensor_core_alignment,    64).
hardware(sm86, sram_per_sm_kb,          96).

hardware(sm100, compute_roof_fp8_tflops,  3457).
hardware(sm100, compute_roof_bf16_tflops, 1729).
hardware(sm100, memory_bandwidth_gbps,    8000).
hardware(sm100, tensor_core_alignment,    128).
hardware(sm100, sram_per_sm_kb,          256).
```

**prolog/roofline.pl** — bottleneck classification rules:
```prolog
ridge_point(GPU, Ridge) :-
    hardware(GPU, compute_roof_tf32_tflops, C),
    hardware(GPU, memory_bandwidth_gbps, M),
    Ridge is (C * 1e12) / (M * 1e9).

bottleneck(Kernel, compute) :-
    kernel_arithmetic_intensity(Kernel, AI),
    current_gpu(GPU),
    ridge_point(GPU, Ridge),
    AI > Ridge.

bottleneck(Kernel, memory) :-
    \+ bottleneck(Kernel, compute).

roofline_gap(Kernel, Gap) :-
    bottleneck(Kernel, memory),
    kernel_bandwidth_utilization(Kernel, Util),
    current_gpu(GPU),
    hardware(GPU, memory_bandwidth_gbps, Roof),
    Gap is (Roof - Util) / Roof.
```

**prolog/shapes.pl** — CLP(FD) (Constraint Logic Programming over Finite Domains) shape enumeration:
```prolog
:- use_module(library(clpfd)).

valid_shape(GPU, DModel, NHeads, HeadDim, NLayers, DFF) :-
    hardware(GPU, tensor_core_alignment, Align),
    DModel in 128..1024,
    DModel mod Align #= 0,
    NHeads in 4..32,
    HeadDim #= DModel // NHeads,
    HeadDim in 32..128,
    NLayers in 2..12,
    DFF #= 4 * DModel,
    label([DModel, NHeads, NLayers]).
```

**Python bridge**: `janus` (SWI-Prolog 9.x built-in Python↔Prolog interface):
```python
from janus_swi import janus
janus.consult("prolog/hardware.pl")
janus.consult("prolog/shapes.pl")
shapes = list(janus.query("valid_shape(sm86, D, H, Hd, L, FF)"))
```

### 4.3 Triton Autotuner

Target: the attention kernel identified as the primary bottleneck by the Prolog roofline classifier.

**Workload-specific shape** (from Notebook 1 content moderation pattern):
- Query length: 64–100 tokens (per-request query)
- KV length: 500–700 tokens (policy prefix + query)
- Batch size: 16–64 (continuous batching)
- Head dim: to be determined by shape optimizer

**Autotune config space** (triton/attention_kernel.py):
```python
@triton.autotune(configs=[
    triton.Config({"BLOCK_M": 64,  "BLOCK_N": 64,  "num_warps": 4, "num_stages": 2}),
    triton.Config({"BLOCK_M": 128, "BLOCK_N": 64,  "num_warps": 4, "num_stages": 3}),
    triton.Config({"BLOCK_M": 64,  "BLOCK_N": 128, "num_warps": 8, "num_stages": 2}),
    triton.Config({"BLOCK_M": 128, "BLOCK_N": 128, "num_warps": 8, "num_stages": 3}),
], key=["SEQ_Q", "SEQ_KV", "HEAD_DIM"])
@triton.jit
def content_mod_attention_kernel(...):
    ...
```

Benchmark: autotuned kernel throughput (tokens/s) vs. vLLM's default Triton attention backend on the same shape. The delta is the contribution metric.

### 4.4 Bayesian Optimization Loop

**Library**: optuna  
**Objective**: minimize system latency (ms/request, weighted by routing probability) subject to accuracy >= teacher_accuracy - 0.05  
**Search space**: shape parameters from Prolog CLP(FD) valid candidates, plus cascade routing threshold  
**Evaluation**: papermill executes trial notebook → extracts (throughput, accuracy) → appends to `trials/results.jsonl`  
**Termination**: improvement < 1% over last 5 trials, or 50 trials total

The confidence threshold θ is a third search dimension alongside (d_model, n_heads, n_layers). It controls what fraction of traffic routes to the decoder and therefore the effective system-level latency.

```python
import optuna, json, subprocess

STAGE1_LATENCY_MS = 5.0   # DistilBERT forward pass — fixed

def objective(trial):
    # Decoder shape (validated by Prolog CLP)
    d_model  = trial.suggest_categorical("d_model",  [128, 256, 384, 512, 768])
    n_heads  = trial.suggest_categorical("n_heads",  [4, 6, 8, 12, 16])
    n_layers = trial.suggest_int("n_layers", 2, 12)

    # Cascade routing threshold — controls fast-path vs. slow-path split
    theta    = trial.suggest_float("theta", 0.80, 0.99)

    # Prune shapes that violate tensor core alignment constraints
    if not prolog_valid(d_model, n_heads, n_layers):
        raise optuna.TrialPruned()

    result = run_trial(d_model, n_heads, n_layers, theta)  # papermill
    if result["system_accuracy"] < ACCURACY_FLOOR:
        raise optuna.TrialPruned()

    # System latency = stage1 always + stage2 only when routed there
    decoder_hit_rate = result["decoder_hit_rate"]   # fraction below theta
    system_latency   = (
        STAGE1_LATENCY_MS
        + decoder_hit_rate * result["decoder_latency_ms"]
    )
    return system_latency
```

**Trial notebook parameters cell** gains `THETA` alongside shape parameters:
```python
# parameters
D_MODEL = 384
N_HEADS = 6
N_LAYERS = 6
D_FF    = 1536
THETA   = 0.95   # cascade confidence threshold
BATCH   = 512
STEPS   = 2000
TEACHER = "Qwen/Qwen2.5-7B-Instruct-AWQ"
GPU     = "sm86"
```

**results.jsonl schema** (one record per trial):
```json
{
  "d_model": 384, "n_heads": 6, "n_layers": 6, "theta": 0.95,
  "decoder_latency_ms": 38.2,
  "decoder_hit_rate": 0.19,
  "system_latency_ms": 12.3,
  "system_accuracy": 0.96,
  "throughput_tok_s": 1420
}
```

### 4.5 Notebook Integration (papermill)

Each trial notebook exposes a `parameters` cell:
```python
# parameters
D_MODEL   = 384
N_HEADS   = 6
N_LAYERS  = 6
D_FF      = 1536
BATCH     = 512
STEPS     = 2000   # short training run for proxy evaluation
TEACHER   = "Qwen/Qwen2.5-7B-Instruct-AWQ"
GPU       = "sm86"
```

Last cell writes metrics to a sidecar JSON file:
```python
import json, pathlib
pathlib.Path("trial_metrics.json").write_text(json.dumps({
    "throughput_tok_s": throughput,
    "accuracy":         accuracy,
    "latency_p99_ms":   latency_p99,
}))
```

`scripts/extract_metrics.py` reads the sidecar and appends to `trials/results.jsonl`.

---

## 5. Makefile Targets

```makefile
GPU       ?= sm86
MODEL     ?= Qwen/Qwen2.5-7B-Instruct-AWQ
STEPS     ?= 2000
TRACES    := traces
ANALYSIS  := analysis

# ── Phase 1: Profiling ─────────────────────────────────────────
$(TRACES)/run.nsys-rep:
	mkdir -p $(TRACES)
	nsys profile --output=$(TRACES)/run \
		--trace=cuda,nvtx,osrt \
		python scripts/run_serving_workload.py --model $(MODEL)

$(TRACES)/run.sqlite: $(TRACES)/run.nsys-rep
	nsys export --type=sqlite --output=$(TRACES)/run.sqlite $<

# ── Phase 2: Prolog analysis ────────────────────────────────────
$(ANALYSIS)/bottleneck.json: $(TRACES)/run.sqlite
	mkdir -p $(ANALYSIS)
	python scripts/extract_events.py $< | \
		swipl -s prolog/roofline.pl -g "classify_and_print" -t halt > $@

# ── Phase 3: Triton autotuning ──────────────────────────────────
$(ANALYSIS)/kernel_config.json: $(ANALYSIS)/bottleneck.json
	python scripts/autotune.py --bottleneck $< --gpu $(GPU) --output $@

# ── Phase 4: Single trial ───────────────────────────────────────
trial: notebooks/distillation_student.ipynb
	papermill $< notebooks/out/trial_$(D_MODEL)_$(N_HEADS)_$(N_LAYERS).ipynb \
		-p D_MODEL  $(D_MODEL)  \
		-p N_HEADS  $(N_HEADS)  \
		-p N_LAYERS $(N_LAYERS) \
		-p STEPS    $(STEPS)    \
		-p GPU      $(GPU)
	python scripts/extract_metrics.py \
		notebooks/out/trial_$(D_MODEL)_$(N_HEADS)_$(N_LAYERS).ipynb \
		>> trials/results.jsonl

# ── Phase 5: Full optimization loop ────────────────────────────
optimize: $(ANALYSIS)/kernel_config.json
	python scripts/optimize_loop.py \
		--gpu $(GPU) \
		--results trials/results.jsonl \
		--prolog-shapes prolog/shapes.pl \
		--kernel-config $(ANALYSIS)/kernel_config.json

# ── Utilities ───────────────────────────────────────────────────
.PHONY: profile analyze autotune trial optimize clean test-prolog

profile:  $(TRACES)/run.nsys-rep
analyze:  $(ANALYSIS)/bottleneck.json
autotune: $(ANALYSIS)/kernel_config.json

test-prolog:
	swipl -s prolog/hardware.pl -s prolog/shapes.pl \
		-s prolog/test.pl -g run_tests -t halt

clean:
	rm -rf $(TRACES) $(ANALYSIS) trials/results.jsonl notebooks/out/
```

---

## 6. File Map

### Existing (do not modify without checking downstream consumers)

| File | Role in this project |
|------|---------------------|
| `demos/prefix-caching/prefix_caching_demo.ipynb` | Serving workload template; defines the inference pattern Nsight profiles; final deployment target for student |
| `demos/jax-transformer/arithmetic_transformer.ipynb` | Student architecture baseline; proves parameterized shape implementation |

### To create (this project)

```
demos/shape-optimizer/
├── DESIGN.md                          ← this document
├── Makefile
├── prolog/
│   ├── hardware.pl                    ← GPU facts (SM86, SM100, ...)
│   ├── roofline.pl                    ← bottleneck classification rules
│   ├── shapes.pl                      ← CLP(FD) shape constraint solver
│   └── test.pl                        ← unit tests for Prolog rules
├── triton/
│   └── attention_kernel.py            ← autotuned attention kernel
├── scripts/
│   ├── run_serving_workload.py        ← launches vLLM for Nsight to profile
│   ├── extract_events.py              ← SQLite → JSON facts for Prolog
│   ├── autotune.py                    ← Triton autotuner driver
│   ├── optimize_loop.py               ← Bayesian opt outer loop (optuna)
│   ├── extract_metrics.py             ← papermill output → results.jsonl
│   └── cascade_router.py             ← confidence threshold routing logic (shared by trial + production)
├── notebooks/
│   ├── distillation_student.ipynb     ← parameterized decoder trial unit (THETA + shape params)
│   ├── encoder_baseline.ipynb         ← DistilBERT fast-path; fine-tunes on teacher soft labels; fixed arch
│   └── out/                           ← executed trial notebooks (git-ignored)
└── trials/
    └── results.jsonl                  ← accumulated trial results (git-ignored)
```

---

## 7. vLLM Integration Points

| Role | Where | What |
|------|-------|-------|
| Profiling target | Phase 1 | `nsys profile` runs against `vllm serve` with the content moderation workload |
| Teacher inference | Phase 5 | vLLM batches training corpus through teacher to generate soft labels for distillation |
| Student serving | Post-optimization | distilled student deployed in vLLM with prefix caching; inherits Notebook 1 architecture |
| Upstream contribution | End state | Triton kernel from Phase 3, benchmarked and PR-ready |

---

## 8. Implementation Plan

### Phase 1 — Profiling Pipeline (start here)

**Goal**: get a real Nsight Systems trace from a vLLM inference run and parse it into structured data.

Tasks:
1. Verify Nsight Systems is installed: `nsys --version`
2. Write `scripts/run_serving_workload.py` — loads the content moderation queries from Notebook 1 (`QUERIES` list), sends them to a vLLM server, runs for 60s to warm caches
3. Run `make profile` — produces `traces/run.nsys-rep`
4. Run `make analyze` step 1 — `nsys export` produces `traces/run.sqlite`
5. Write `scripts/extract_events.py` — queries `CUPTI_ACTIVITY_KIND_KERNEL` and `CUPTI_ACTIVITY_KIND_MEMCPY`, computes per-kernel duration totals, identifies top-5 kernels by time
6. Verify output is parseable — print top kernel names and durations

**Completion signal**: `python scripts/extract_events.py traces/run.sqlite` prints a ranked list of kernel names with duration and a compute/memory-bound classification for the top kernel.

### Phase 2 — Prolog Reasoning Layer

**Goal**: classify the top bottleneck kernel and enumerate valid student shapes using CLP(FD).

Tasks:
1. Install SWI-Prolog: `sudo apt install swi-prolog` and verify `janus` Python bridge: `pip install janus-swi`
2. Write `prolog/hardware.pl` with SM86 and SM100 facts
3. Write `prolog/roofline.pl` with ridge point calculation and bottleneck classification rules
4. Write `prolog/shapes.pl` with CLP(FD) valid shape enumeration
5. Write `prolog/test.pl` — assert known facts, verify classification matches expected
6. Run `make test-prolog` — all tests pass
7. Connect via janus in `scripts/extract_events.py` — output includes Prolog bottleneck classification

**Completion signal**: `make analyze` produces `analysis/bottleneck.json` with `{"kernel": "...", "type": "memory", "gap": 0.43}` and a list of valid shape candidates.

### Phase 3 — Triton Kernel Autotuner

**Goal**: write and benchmark a Triton attention kernel for the content moderation workload shape.

Tasks:
1. Identify the exact bottleneck kernel name from Phase 2 output
2. Write `triton/attention_kernel.py` — fused causal attention with autotuned tile configs
3. Write a standalone benchmark script comparing autotuned kernel vs. `torch.nn.functional.scaled_dot_product_attention` on the specific shape (SEQ_Q=80, SEQ_KV=600, HEAD_DIM=TBD, BATCH=32)
4. Run `make autotune` — produces `analysis/kernel_config.json` with winning tile config and speedup ratio

**Completion signal**: `make autotune` prints `speedup: X.Xx on (SEQ_Q=80, SEQ_KV=600, HEAD_DIM=64, BATCH=32)`.

### Phase 4 — Distillation Trial Notebook

**Goal**: parameterized notebook that trains a student model for N steps and reports throughput + accuracy.

Tasks:
1. Create `notebooks/distillation_student.ipynb` — adapted from `demos/jax-transformer/arithmetic_transformer.ipynb` but targeting PyTorch (for vLLM compatibility) and content moderation classification instead of digit addition
2. Tag the `parameters` cell correctly for papermill
3. Add a final cell that writes `trial_metrics.json`
4. Write `scripts/extract_metrics.py` — reads `trial_metrics.json` from executed notebook, appends to `trials/results.jsonl`
5. Run `make trial D_MODEL=384 N_HEADS=6 N_LAYERS=6` manually — verify metrics appear in `trials/results.jsonl`

**Completion signal**: `trials/results.jsonl` has one valid JSON record with throughput, accuracy, and latency fields.

### Phase 5 — Optimization Loop

**Goal**: closed-loop Bayesian optimization over student shapes driven by trial notebook evaluations.

Tasks:
1. Write `scripts/optimize_loop.py` — optuna study, Prolog shape validation as pruner, papermill trial execution as objective
2. Run `make optimize` for 10 trials — verify convergence is directional (loss decreasing, latency improving)
3. Identify the Pareto-optimal shape
4. Train the full student on that shape for the full dataset
5. Deploy in vLLM with prefix caching — run Notebook 1 with student instead of teacher and compare accuracy + latency

**Completion signal**: `trials/results.jsonl` has ≥10 records; `make optimize` reports a best shape with latency < 50ms P99 and accuracy within 5% of teacher on TEST_QUERIES.

---

## 9. Success Criteria

| Criterion | Measurement |
|-----------|-------------|
| Triton kernel improvement | ≥5% throughput gain vs. baseline on content moderation shape |
| Decoder student accuracy | Within 5% F1 of teacher on 10-query TEST_QUERIES matrix |
| Decoder stage latency | P99 TTFT (Time to First Token) < 50ms under 32-concurrent-request load |
| Encoder baseline accuracy | DistilBERT fine-tuned on teacher labels ≥ 90% F1 on TEST_QUERIES |
| System latency (cascade) | Weighted system latency < 15ms at θ=0.95 (≈80% fast-path routing) |
| Shape search efficiency | Bayesian opt converges in < 20 trials (vs. ~200 for grid search over same space) |
| Reproducibility | `make optimize GPU=sm86` runs end-to-end on a fresh clone |

---

## 10. Byproduct: Upstream Kernel Contribution

The attention shape this workload produces — a short per-request query attending over a long shared policy prefix, SEQ_Q ≪ SEQ_KV — is not specific to this deployment: any moderation service with a fixed policy preamble hits it. A kernel tuned for it therefore belongs upstream, not in the app. The vLLM PR (Pull Request) contains:
- `vllm/attention/backends/triton_content_mod.py` — the autotuned kernel
- `benchmarks/shape_optimizer/` — the benchmark showing speedup on the content moderation shape
- `tests/kernels/test_content_mod_attention.py` — correctness test vs. reference implementation

PR description framing: "Adds a Triton attention kernel tuned for the prefill-heavy, long-shared-prefix workload pattern common in document moderation use cases. Benchmarked on SM86 (RTX A4000). Autotuned tile configurations included."

---

## 11. Open Questions

1. **Nsight availability**: confirm `nsys` is installed on the A4000 machine and the GPU is accessible to the profiling process without root.
2. **janus version**: SWI-Prolog 9.x ships janus built-in; verify version with `swipl --version`. If < 9.0, use subprocess approach instead.
3. **Teacher soft labels storage**: generating full vocab logits over a content moderation dataset for distillation produces significant data volume. For Phase 4, use a small synthetic dataset (1000 examples) generated from CATALOG/QUERIES variations rather than a real corpus.
4. **Student framework**: JAX (for Crucible/TPU portability) or PyTorch (for direct vLLM compatibility). Decision: PyTorch for the trial notebook to avoid a conversion step before vLLM deployment.
5. **PCIe link warm-up**: per 2026-06-26 fix, GPU needs load before reaching full PCIe bandwidth. Add a warm-up step (`scripts/warmup_gpu.py`) before any profiling run.
