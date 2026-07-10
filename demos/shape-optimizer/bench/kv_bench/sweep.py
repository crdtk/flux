"""
Token/s and GB/s sweep across context lengths.

Restored from 8cb3df4:demos/turboquant/turboquant_demo/sweep.py. The quantized
side is now stock vLLM FP8 KV cache (--kv-cache-dtype fp8) instead of the
unrecoverable TurboQuant 3-bit/2-bit patch, and the effective-bandwidth
estimate uses each server's own KV byte width.

Compares baseline (bf16 KV, :8001) vs FP8 KV (:8000) on a single RTX A4000.
Estimates effective DRAM bandwidth utilisation against the SM86 theoretical peak.

Requires: make servers
Results:  results/bench_results.json  (committed — provenance, not scratch)

Run standalone:  .venv/bin/python3 kv_bench/sweep.py
"""
import json
import pathlib
import time

from openai import OpenAI

BASELINE_URL = "http://localhost:8001/v1"
FP8_URL      = "http://localhost:8000/v1"
CTX_LENGTHS  = [1024, 2048, 4096, 8192]

# RTX A4000 SM86 theoretical DRAM bandwidth (GB/s)
PEAK_BW_GBS = 448.0

# Per-token KV cache bytes for DeepSeek-R1-Distill-Qwen-7B:
#   28 layers * 4 KV heads (GQA) * head_dim=128 * 2 (K+V) * bytes-per-value
KV_BYTES_BF16 = 28 * 4 * 128 * 2 * 2
KV_BYTES_FP8  = 28 * 4 * 128 * 2 * 1

# AWQ-quantised 7B model weights ≈ 5.6 GB in VRAM
WEIGHT_BYTES = int(5.6 * 1024 ** 3)

RESULTS_DIR = pathlib.Path(__file__).resolve().parent.parent / "results"


def gpu_name() -> str:
    try:
        import pynvml
        pynvml.nvmlInit()
        name = pynvml.nvmlDeviceGetName(pynvml.nvmlDeviceGetHandleByIndex(0))
        return name.decode() if isinstance(name, bytes) else name
    except Exception:
        return "unknown"


def bench(url: str, ctx: int, kv_bytes_per_token: int, gen: int = 64) -> dict:
    client = OpenAI(base_url=url, api_key="x", timeout=300.0)
    # Fill context with repetitive tokens; truncate to approximate ctx tokens
    prompt = ("word " * (ctx // 5 + 1))[: ctx * 5]
    t0 = time.perf_counter()
    response = client.chat.completions.create(
        model="default",
        messages=[{"role": "user", "content": prompt}],
        max_tokens=gen,
        stream=False,
    )
    dt = time.perf_counter() - t0
    n  = response.usage.completion_tokens

    tok_s = n / dt
    # Effective GB/s: (weights + KV cache) read once per decode step, summed over n steps
    gb_s  = (WEIGHT_BYTES + ctx * kv_bytes_per_token) * n / dt / 1e9

    return {
        "ctx":      ctx,
        "tok_s":    tok_s,
        "gb_s":     gb_s,
        "pct_peak": 100.0 * gb_s / PEAK_BW_GBS,
    }


if __name__ == "__main__":
    results: dict = {
        "meta": {
            "gpu":          gpu_name(),
            "model":        "casperhansen/deepseek-r1-distill-qwen-7b-awq",
            "baseline_kv":  "bf16",
            "variant_kv":   "fp8 (stock vLLM --kv-cache-dtype fp8, no scale calibration)",
            "peak_bw_gbs":  PEAK_BW_GBS,
            "timestamp":    time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        },
        "baseline": [],
        "fp8":      [],
    }

    header = (
        f"{'ctx':>8} | {'base tok/s':>10} | {'fp8 tok/s':>9} | "
        f"{'delta':>7} | {'GB/s':>7} | {'%peak':>6}"
    )
    print(f"\n{header}")
    print("-" * len(header))

    for ctx in CTX_LENGTHS:
        try:
            b = bench(BASELINE_URL, ctx, KV_BYTES_BF16)
            f = bench(FP8_URL,      ctx, KV_BYTES_FP8)
            results["baseline"].append(b)
            results["fp8"].append(f)
            delta = 100.0 * (f["tok_s"] - b["tok_s"]) / b["tok_s"]
            print(
                f"{ctx:>8} | {b['tok_s']:>10.1f} | {f['tok_s']:>9.1f} | "
                f"{delta:>+6.1f}% | {f['gb_s']:>7.1f} | {f['pct_peak']:>5.0f}%"
            )
        except Exception as exc:
            print(f"{ctx:>8} | error: {exc}")

    RESULTS_DIR.mkdir(exist_ok=True)
    out = RESULTS_DIR / "bench_results.json"
    with open(out, "w") as fh:
        json.dump(results, fh, indent=2)
    print(f"\n>>> {out} written — commit it")
