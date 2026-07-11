"""
Locust load test — baseline bf16 KV (:8001) vs FP8 KV (:8000).

Restored from 8cb3df4:demos/turboquant/turboquant_demo/locustfile.py, two
adaptations: the quantized server is stock vLLM FP8 KV, and the per-request
BERT extraction is replaced by a static structured signal — the extraction
step exercised the pilot's cascade, not the KV cache under test here.

Two user classes run concurrently so both servers are stressed equally.

Headless (via make bench-locust):
  locust --headless -u 4 -r 1 -t 60s --csv results/locust --host http://localhost:8000
"""
import json
import os
import random

from locust import HttpUser, between, task

CUSTOMER_PROFILE = (
    "Customer fit profile (47 purchases, 3 years):\n"
    "  thigh_width:  wide      (8 returns citing tight thighs, conf=0.91)\n"
    "  waist:        normal    (stable across 12 items)\n"
    "  shoulders:    narrow    (3 returns, conf=0.74)\n"
    "  proven sizes: Gap relaxed 33W 30L · Levi's 541 33W · Levi's 502 33W 30L"
)

# LOCUST_CTX: approximate extra prompt tokens of purchase history per request.
# Default 0 keeps the original short shape (committed results stay comparable).
# The short shape can NEVER stress the KV pool (12 users × ~250 tok ≈ 3k, vs
# 13k bf16 / 26k fp8 pools — zero preemptions at any user count). To separate
# the servers on CAPACITY, size concurrent demand BETWEEN the pools, e.g.
# LOCUST_CTX=1500 with 24 users: 12×~1.6k ≈ 19k — baseline preempts, fp8 fits.
CTX_TOKENS = int(os.environ.get("LOCUST_CTX", "0"))
# LOCUST_MAX_TOKENS: decode length — long decodes make sequences HOLD their KV
# (a 96-token answer frees its slot in ~1.6s; demand never accumulates).
# LOCUST_WAIT: max think-time seconds between requests (0 = closed-loop
# hammering). With wait 1-3s the duty cycle was ~45%: 12 users yielded only
# ~5-6 in-flight × 1.6k tok ≈ 9k — still under the 13k bf16 pool, 0 preemptions.
MAX_TOKENS = int(os.environ.get("LOCUST_MAX_TOKENS", "96"))
WAIT_MAX = float(os.environ.get("LOCUST_WAIT", "3"))

_BRANDS = ["Levi's 501", "Gap relaxed", "Levi's 541", "Wrangler 13MWZ", "Lee 101",
           "Nudie Grim Tim", "Uniqlo EZY", "Dockers Alpha"]
_OUTCOMES = ["kept", "returned: tight thighs", "returned: loose waist", "kept, hemmed",
             "returned: short inseam", "kept after exchange"]

def _purchase_history(n_tokens: int) -> str:
    rng = random.Random(42)  # deterministic: every request carries the same weight
    lines = ["Full purchase history:"]
    while sum(len(l) for l in lines) // 4 < n_tokens:  # ~4 chars/token
        lines.append("  2024-%02d-%02d · %s · %dW %dL · %s"
                     % (rng.randint(1, 12), rng.randint(1, 28), rng.choice(_BRANDS),
                        rng.randint(30, 36), rng.randint(28, 34), rng.choice(_OUTCOMES)))
    return "\n".join(lines)

_HISTORY = _purchase_history(CTX_TOKENS) + "\n\n" if CTX_TOKENS else ""

# (return text, pre-extracted structured signal) — static stand-ins for the
# pilot's BERT extraction step
_SAMPLES = [
    ("The jeans were too tight in the thighs but the waist fit perfectly",
     {"region": "thigh", "fit": -1}),
    ("Way too large in the shoulders, had to return",
     {"region": "shoulder", "fit": 1}),
    ("Perfect fit, definitely keeping these",
     {"region": "global", "fit": 0}),
    ("Chest was a bit snug but the length was great",
     {"region": "chest", "fit": -1}),
    ("Runs small overall, went up a size next time",
     {"region": "global", "fit": -1}),
    ("Hips were too wide, waist was fine",
     {"region": "hip", "fit": 1}),
    ("Sleeves were too short for my arms",
     {"region": "sleeve", "fit": -1}),
    ("The length is great but the chest is too tight",
     {"region": "chest", "fit": -1}),
]


def _make_payload() -> dict:
    _text, sig = random.choice(_SAMPLES)
    # Unique first line per request: vLLM's prefix caching hashes KV blocks from
    # the prompt START — identical histories were deduplicated to ONE cached
    # copy, so 12 concurrent 1.7k-token requests cost ~7k tokens, never
    # pressuring either pool (0 preemptions at every load tried). A differing
    # first block breaks all downstream block hashes: each customer is unique.
    prompt = (
        f"Customer id: {random.getrandbits(64):016x}\n"
        f"{CUSTOMER_PROFILE}\n\n"
        f"{_HISTORY}"
        f"New return signal: {json.dumps(sig)}\n"
        f"Target item: Levi's 501 32W 32L\n\n"
        f"Recommend size:"
    )
    return {
        "model":      "default",
        "messages":   [{"role": "user", "content": prompt}],
        "max_tokens": MAX_TOKENS,
        "stream":     False,
    }


class BaselineUser(HttpUser):
    """Hits the baseline bf16-KV server on :8001."""
    host       = "http://localhost:8001"
    wait_time  = between(0, WAIT_MAX)

    @task
    def fit_recommendation(self):
        with self.client.post(
            "/v1/chat/completions",
            json=_make_payload(),
            headers={"Authorization": "Bearer x"},
            catch_response=True,
            name="baseline /v1/chat/completions",
        ) as resp:
            if resp.status_code != 200:
                resp.failure(f"HTTP {resp.status_code}")


class FP8User(HttpUser):
    """Hits the stock-vLLM FP8-KV server on :8000."""
    host       = "http://localhost:8000"
    wait_time  = between(0, WAIT_MAX)

    @task
    def fit_recommendation(self):
        with self.client.post(
            "/v1/chat/completions",
            json=_make_payload(),
            headers={"Authorization": "Bearer x"},
            catch_response=True,
            name="fp8 /v1/chat/completions",
        ) as resp:
            if resp.status_code != 200:
                resp.failure(f"HTTP {resp.status_code}")
