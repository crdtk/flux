# KV-Cache A/B Bench — Shape Optimizer Phase 1 harness

Serving benchmark restored from the TurboQuant pilot (commit `8cb3df4`,
`demos/turboquant/`, removed from main 2026-06-15) and adapted to run on
**stock vLLM only**:

| | Pilot (unrecoverable) | This harness |
|---|---|---|
| Quantized server | Patched vLLM, `TURBOQUANT=1`, 3-bit K / 2-bit V | Stock `--kv-cache-dtype fp8` |
| Results | `bench_results.json` written to cwd, never committed | `results/` — **committed** |
| Locust prompt | BERT extraction per request (`turboquant_demo.bert`) | Static structured profile (BERT step is irrelevant to a KV A/B) |

The experimental question is unchanged: does KV quantization relieve
memory-bound decode on an RTX A4000 (SM86, 448 GB/s peak DRAM bandwidth)?
Both servers share the GPU (0.42 memory fraction each, eager mode — see
`scripts/start_servers.sh` for the arithmetic), serving
`casperhansen/deepseek-r1-distill-qwen-7b-awq` (~5.6 GB AWQ weights).

FP8 KV here is a memory-traffic experiment, not a quality comparison —
no KV scale calibration is done.

## Run order

```
make -C demos/shape-optimizer/bench servers        # deps + model + both vLLM servers
make -C demos/shape-optimizer/bench bench-kv       # tok/s + GB/s sweep → results/bench_results.json
make -C demos/shape-optimizer/bench bench-locust   # load test → results/locust_*.csv
make -C demos/shape-optimizer/bench servers-stop
```

Results land in `results/` and are meant to be committed — they are the
provenance for any measured claim made outside this repo.
