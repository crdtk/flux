# Half the Bytes, Twice the Shoppers

*How one mid-range GPU, a deleted prototype, and three benchmarks that
lied on the way to a number: compressing an LLM's working memory serves
56% more customers at peak — for free.*

---

Two supposedly rival servers spent an evening in July trading benchmark
results so similar they could have been photocopies. Every latency
percentile matched. Every throughput curve overlapped. It looked like a
perfectly controlled experiment — right up until the request counters
gave the game away. One server had answered 2,180 requests.

The other had answered four.

The A/B test was never an A/B test. One server had been racing its own
reflection, and the harness cheerfully scored the tie. This is the
story of getting an honest number out of one mid-range workstation GPU
— and of the three lies a benchmark told on the way.

## June 2026: the number that couldn't be checked

This bench exists because a claim lost its evidence. The TurboQuant
pilot — a patched vLLM (an open-source large-language-model serving
engine) squeezing attention state down to 3 and 2 bits — was removed
from this repo on June 15 (`8cb3df4`, `demos/turboquant/`). Its
benchmark wrote `bench_results.json` to the current directory and
nobody ever committed one. All that survived were the claims themselves
— numbers quoted in prose, with nothing left to check them against.

The rebuild rule this time: **stock software only, results committed.**
No patched engine — just vLLM's off-the-shelf `--kv-cache-dtype fp8`
flag
([vLLM docs](https://docs.vllm.ai/en/latest/features/quantization/quantized_kvcache.html)).
Any number that someone with the same GPU and this Makefile can't
reproduce doesn't go in the repo.

## The scenario: a size advisor with a memory problem

The workload simulates an online apparel retailer's **AI size advisor**.
Returns are the single largest avoidable cost in online apparel, and
"doesn't fit" is their #1 reason — so before a shopper buys the wrong
jeans, the advisor reads their purchase-and-return history and
recommends a size.

Every request the load generator sends looks like a real one:

```
Customer id: 3f9c81a2e5d47b06
Customer fit profile (47 purchases, 3 years):
  thigh_width:  wide      (8 returns citing tight thighs, conf=0.91)
  waist:        normal    (stable across 12 items)
  shoulders:    narrow    (3 returns, conf=0.74)
  proven sizes: Gap relaxed 33W 30L · Levi's 541 33W · Levi's 502 33W 30L

Full purchase history:
  2024-03-14 · Levi's 541 · 33W 30L · returned: tight thighs
  2024-05-02 · Gap relaxed · 33W 30L · kept
  ... (as many dated lines as the experiment needs)

New return signal: {"region": "thigh", "fit": -1}
Target item: Levi's 501 32W 32L

Recommend size:
```

And the model answers in prose — like this (illustrative; the committed
results measure throughput, not text):

> *Recommend 34W 32L, not the 32W on the product page. This customer
> has returned 8 items for tight thighs and every size they've kept is
> a 33W in a relaxed cut — the 501's straight leg runs tighter in the
> thigh than the 541 they already returned. Going up one waist size is
> the cheapest insurance against a ninth return.*

## The bottleneck: the KV-cache tax

While that answer is being generated, the GPU holds the shopper's
*entire context* — profile, history, question — in working memory. That
memory is the **KV cache** (key-value cache, the model's
per-conversation short-term memory), and every shopper being served
pays the tax for as long as their answer takes to write.

> **The memory limit:** the KV pool's size is fixed at server start.
> When it fills, the next shopper waits in a queue.

vLLM can store that memory in **fp8** — 8-bit floating point, half the
bytes of the 16-bit (bf16) default. Half the bytes means twice the
shoppers in memory at once, on the same silicon. That left two things
to measure: does the compression slow the answers down, and does the
doubled capacity actually help when traffic peaks?

## July 11, 21:02 — the server that wouldn't start

The A/B setup is deliberately minimal: one RTX A4000 (16 GB, 448 GB/s)
split into two identical vLLM servers — same 7-billion-parameter
DeepSeek distill, same 0.42 memory budget each — twins in every respect
except how densely they pack their memory. But the fp8 twin failed
three ways at boot, each failure masking the next: a stale process from
a previous run answering health checks while hoarding the memory; the
`ninja` build tool invisible to the just-in-time kernel compiler; a
CUDA header the host compiler rejected outright. The bf16 baseline
compiles nothing at startup, which is why it never complained. (All
three fixes are permanent — in the Makefile, its scripts, and POST,
this repo's drift-repair system.)

## 21:19 — quiet hours: a wash

First real numbers, one shopper at a time (`bench-kv`):

|  history length (tokens) | base tok/s | fp8 tok/s | delta |
|-----:|-----------:|----------:|------:|
| 1024 |       51.0 |      66.1 | +29.6% *(warm-up artifact)* |
| 2048 |       68.2 |      67.4 |  -1.1% |
| 4096 |       62.0 |      63.9 |  +3.0% |
| 8192 |       55.3 |      56.5 |  +2.2% |

**The finding is clear: at low traffic, performance is a wash (±1–3%).**
With a single shopper, answer speed is limited by reading the model's
own weights — measured at 79–91% of the card's peak memory bandwidth —
so shrinking the per-shopper memory barely moves the needle. (The 1024
row is the first cell measured and eats the GPU's warm-up; an artifact,
not a result.)

That could have been the end of the story: a compression that changes
nothing. If fp8 had a win, it was hiding somewhere a single-shopper
test could never see.

## The load tests that lied

Capacity is a crowd phenomenon, so the harness simulates one: Locust
(an open-source load-testing tool) spawns concurrent shoppers against
both servers. This is where the evening's opening scene took place —
the first three attempts produced clean-looking numbers that meant
nothing:

1. **The shared-host illusion.** The photocopied percentiles from the
   top of this story. Locust's `--host` flag silently overrides each
   user class's own target — every earlier "A/B" was one server
   load-testing itself, 2,180 requests to 4. The Makefile now passes no
   `--host`; each shopper class carries its own.
2. **The smart-cache loophole.** vLLM's prefix caching deduplicates
   identical prompts — twelve shoppers with the same synthetic history
   cost the memory pool *one* copy (~7k tokens of pressure instead of
   ~20k), so nobody ever queued, at any crowd size. Now every request
   opens with a unique customer id, as production traffic would: each
   shopper is a different person, and the cache's block-hash chain
   breaks from the first line.
3. **The polite-shopper problem.** Default think-time (1–3 s between
   requests) and short 96-token answers kept server occupancy near 45%;
   shoppers released their memory before a crowd could form. The honest
   run uses zero think-time and long, detailed answers.

All three lies were caught the same way: the harness kept producing
plausible numbers, and the servers' own gauges kept contradicting them
— shoppers running, shoppers waiting, memory-pool fill. `make watch-kv`
puts all three on screen, refreshed every second: the experiment's
polygraph.

## 22:33 — peak traffic: +56%

The honest experiment: 12 closed-loop shoppers, every one a unique
customer carrying a ~1.7k-token history and asking for a detailed
512-token recommendation, hammering each server serially for 120
seconds at identical offered load. (Serial matters: run both crowds at
once and they share the GPU's compute, degrading in lockstep and hiding
the capacity difference.) Reproduced twice.

This time the polygraph showed separation in real time. The baseline
pinned at 4 shoppers in flight, the other 8 forced straight into the
wait queue; the fp8 twin, under the same rush, held 8–12 in flight.
Both memory pools sat at 100% and both servers preempted work — the
difference was how many shoppers fit inside before that happened:
26,384 tokens of room versus ~13k.

| | baseline (bf16) | compressed (fp8 KV) |
|---|---:|---:|
| recommendations delivered in 120 s | 41 | **64 (+56%)** |
| median time to a complete answer | 33 s | **20 s (−39%)** |

**The bottom line:** storing the advisor's working memory in fp8 costs
nothing when the shop is quiet and serves ~1.5× the shoppers when it
isn't. Same GPU, same model, same electricity bill — 56% more
recommendations per minute at peak, each arriving 13 seconds sooner.

The benchmarks lied three times in one evening. The gauges never did —
and this time, the numbers are committed in `results/`.

---

## Run it yourself

```
make -C demos/shape-optimizer/bench servers        # deps + model + both vLLM servers
make -C demos/shape-optimizer/bench bench-kv       # tok/s + GB/s sweep → results/bench_results.json
make -C demos/shape-optimizer/bench bench-locust   # load test → results/locust_*.csv
make -C demos/shape-optimizer/bench servers-stop
```

`servers` fails fast off the A4000 host (compute-capability gate) and
warns when a desktop shares the GPU (~1–3% noise on absolute numbers,
common-mode for the A/B delta).

The +56% protocol — each class serially, demand sized *between* the two
pools (~13k bf16 / 26,384 fp8):

```
make bench-locust LOCUST_CLASS=BaselineUser LOCUST_USERS=12 LOCUST_RATE=4 \
    LOCUST_TIME=120s LOCUST_CTX=1500 LOCUST_MAX_TOKENS=512 LOCUST_WAIT=0
make bench-locust LOCUST_CLASS=FP8User     LOCUST_USERS=12 LOCUST_RATE=4 \
    LOCUST_TIME=120s LOCUST_CTX=1500 LOCUST_MAX_TOKENS=512 LOCUST_WAIT=0
```

Traffic-shape knobs (defaults keep the original short shape, so the
committed results stay comparable):

- `LOCUST_CTX` — purchase history per shopper, in extra prompt tokens
  (default 0; without history the memory pools never fill, so there is
  nothing to measure).
- `LOCUST_MAX_TOKENS` — answer detail (default 96; one-liners free
  their memory before demand accumulates).
- `LOCUST_WAIT` — shopper think-time in seconds (default 3;
  0 = continuous rush).
- `LOCUST_CLASS` — `BaselineUser` or `FP8User` for a serial run; empty
  runs both concurrently (latency shape, not capacity).

Watching live: `make watch-kv` (the three gauges above), `make
locust-web` (interactive dashboard, http://localhost:8089). Grafana +
Prometheus are provisioned by POST (`post/features/net/observability.pl`):
Prometheus on :9095, Grafana on :3000 with the official vLLM dashboard
pinned to v0.18.0.

## Provenance

Restored from the TurboQuant pilot and adapted to stock vLLM:

| | Pilot (unrecoverable) | This harness |
|---|---|---|
| Quantized server | Patched vLLM, `TURBOQUANT=1`, 3-bit K / 2-bit V | Stock `--kv-cache-dtype fp8` |
| Results | Written to cwd, never committed | `results/` — **committed** |
| Locust prompt | BERT extraction per request | Static structured profile (irrelevant to a KV A/B) |

Model: `casperhansen/deepseek-r1-distill-qwen-7b-awq` (~5.6 GB of
AWQ — Activation-aware Weight Quantization — weights); split arithmetic
in `scripts/start_servers.sh`. No KV scale calibration — this is a
memory-traffic experiment, not a quality comparison. Results in
`results/` are meant to be committed: they are the provenance for any
measured claim made outside this repo.
