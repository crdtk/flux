"""
Token/s and GB/s sweep across context lengths.

Compares baseline (bf16 KV) vs TurboQuant (3b key / 2b val KV) on a single A4000.
Estimates effective DRAM bandwidth utilisation against the SM86 theoretical peak.

Requires: make demo-servers   (baseline on :8001, TQ on :8000)
Results:  bench_results.json  (written to cwd)

Run standalone:  python -m turboquant_demo.sweep
"""
import json
import time

from openai import OpenAI

BASELINE_URL = "http://localhost:8001/v1"
TQ_URL       = "http://localhost:8000/v1"
CTX_LENGTHS  = [1024, 2048, 4096, 8192]

# RTX A4000 SM86 theoretical DRAM bandwidth (GB/s)
PEAK_BW_GBS = 448.0

# Per-token KV cache bytes for 7B model (DeepSeek-R1-Distill-Qwen-7B):
#   28 layers * 4 KV heads (GQA) * head_dim=128 * 2 (K+V) * 2 bytes (bf16)
KV_BYTES_PER_TOKEN = 28 * 4 * 128 * 2 * 2

# AWQ-quantised 7B model weights ≈ 5.6 GB in VRAM
WEIGHT_BYTES = int(5.6 * 1024 ** 3)


def bench(url: str, ctx: int, gen: int = 64) -> dict:
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
    gb_s  = (WEIGHT_BYTES + ctx * KV_BYTES_PER_TOKEN) * n / dt / 1e9

    return {
        "ctx":      ctx,
        "tok_s":    tok_s,
        "gb_s":     gb_s,
        "pct_peak": 100.0 * gb_s / PEAK_BW_GBS,
    }


if __name__ == "__main__":
    results: dict[str, list] = {"baseline": [], "tq": []}

    header = (
        f"{'ctx':>8} | {'base tok/s':>10} | {'TQ tok/s':>9} | "
        f"{'delta':>7} | {'GB/s':>7} | {'%peak':>6}"
    )
    print(f"\n{header}")
    print("-" * len(header))

    for ctx in CTX_LENGTHS:
        try:
            b = bench(BASELINE_URL, ctx)
            t = bench(TQ_URL,       ctx)
            results["baseline"].append(b)
            results["tq"].append(t)
            delta = 100.0 * (t["tok_s"] - b["tok_s"]) / b["tok_s"]
            print(
                f"{ctx:>8} | {b['tok_s']:>10.1f} | {t['tok_s']:>9.1f} | "
                f"{delta:>+6.1f}% | {t['gb_s']:>7.1f} | {t['pct_peak']:>5.0f}%"
            )
        except Exception as exc:
            print(f"{ctx:>8} | error: {exc}")

    with open("bench_results.json", "w") as fh:
        json.dump(results, fh, indent=2)
    print("\n>>> bench_results.json written")
