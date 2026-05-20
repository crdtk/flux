"""
End-to-end pipeline latency measurement.

Stages:
  1. BERT extraction  — parse return text into structured fit signal
  2. LLM decode       — generate size recommendation from profile + signal

Measures mean and p95 latency across a set of sample return texts.

Requires: TQ vLLM server on :8000  (make demo-servers)
Run standalone:  python -m turboquant_demo.latency
"""
import json
import statistics
import time

from openai import OpenAI

from turboquant_demo.bert import extract_fit_signal

client = OpenAI(base_url="http://localhost:8000/v1", api_key="x")

CUSTOMER_PROFILE = (
    "Customer fit profile (47 purchases, 3 years):\n"
    "  thigh_width:  wide      (8 returns citing tight thighs, conf=0.91)\n"
    "  waist:        normal    (stable across 12 items)\n"
    "  shoulders:    narrow    (3 returns, conf=0.74)\n"
    "  proven sizes: Gap relaxed 33W 30L · Levi's 541 33W · Levi's 502 33W 30L"
)

_SAMPLES = [
    "The jeans were too tight in the thighs but the waist fit perfectly",
    "Way too large in the shoulders, had to return",
    "Perfect fit, definitely keeping these",
    "Chest was a bit snug but the length was great",
    "Runs small overall, went up a size next time",
]


def run_pipeline(text: str) -> dict:
    t0  = time.perf_counter()
    sig = extract_fit_signal(text)
    t1  = time.perf_counter()

    prompt = (
        f"{CUSTOMER_PROFILE}\n\n"
        f"New return signal: {json.dumps(sig)}\n"
        f"Target item: Levi's 501 32W 32L\n\n"
        f"Recommend size:"
    )
    response = client.chat.completions.create(
        model="default",
        messages=[{"role": "user", "content": prompt}],
        max_tokens=96,
        stream=False,
    )
    t2 = time.perf_counter()

    return {
        "bert_ms":  (t1 - t0) * 1000,
        "llm_ms":   (t2 - t1) * 1000,
        "total_ms": (t2 - t0) * 1000,
        "rec":      response.choices[0].message.content.strip(),
    }


def _p95(values: list[float]) -> float:
    return sorted(values)[max(int(0.95 * len(values)) - 1, 0)]


if __name__ == "__main__":
    rows = []
    for sample in _SAMPLES:
        r = run_pipeline(sample)
        rows.append(r)
        print(
            f"BERT {r['bert_ms']:.0f}ms | LLM {r['llm_ms']:.0f}ms | "
            f"total {r['total_ms']:.0f}ms"
        )
        print(f"  '{sample[:60]}'\n  -> {r['rec'][:80]}\n")

    bert_ms  = [r["bert_ms"]  for r in rows]
    total_ms = [r["total_ms"] for r in rows]
    print(f"BERT  — mean {statistics.mean(bert_ms):.0f}ms  p95 {_p95(bert_ms):.0f}ms")
    print(f"Total — mean {statistics.mean(total_ms):.0f}ms  p95 {_p95(total_ms):.0f}ms")
