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
import random

from locust import HttpUser, between, task

CUSTOMER_PROFILE = (
    "Customer fit profile (47 purchases, 3 years):\n"
    "  thigh_width:  wide      (8 returns citing tight thighs, conf=0.91)\n"
    "  waist:        normal    (stable across 12 items)\n"
    "  shoulders:    narrow    (3 returns, conf=0.74)\n"
    "  proven sizes: Gap relaxed 33W 30L · Levi's 541 33W · Levi's 502 33W 30L"
)

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
    prompt = (
        f"{CUSTOMER_PROFILE}\n\n"
        f"New return signal: {json.dumps(sig)}\n"
        f"Target item: Levi's 501 32W 32L\n\n"
        f"Recommend size:"
    )
    return {
        "model":      "default",
        "messages":   [{"role": "user", "content": prompt}],
        "max_tokens": 96,
        "stream":     False,
    }


class BaselineUser(HttpUser):
    """Hits the baseline bf16-KV server on :8001."""
    host       = "http://localhost:8001"
    wait_time  = between(1, 3)

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
    wait_time  = between(1, 3)

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
