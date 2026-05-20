"""
Locust load test — baseline (:8001) vs TurboQuant (:8000).

Two user classes run concurrently so both servers are stressed equally:
  BaselineUser  → POST http://localhost:8001/v1/chat/completions
  TQUser        → POST http://localhost:8000/v1/chat/completions

Each task picks a random return text, runs BERT extraction once per worker
process (cached after the first call), builds a fit-recommendation prompt,
and fires a non-streaming completion request with max_tokens=96.

Headless (via make bench-locust):
  locust --headless -u 4 -r 1 -t 60s --host http://localhost:8000

Web UI (interactive):
  locust --host http://localhost:8000
  open http://localhost:8089
"""
import json
import random

from locust import HttpUser, between, events, task

from turboquant_demo.bert import extract_fit_signal
from turboquant_demo.latency import CUSTOMER_PROFILE

_SAMPLES = [
    "The jeans were too tight in the thighs but the waist fit perfectly",
    "Way too large in the shoulders, had to return",
    "Perfect fit, definitely keeping these",
    "Chest was a bit snug but the length was great",
    "Runs small overall, went up a size next time",
    "Hips were too wide, waist was fine",
    "Sleeves were too short for my arms",
    "The length is great but the chest is too tight",
]

# Warm the BERT model once per worker process on startup.
@events.init.add_listener
def _warm_bert(environment, **_kw):
    extract_fit_signal(_SAMPLES[0])


def _make_payload() -> dict:
    text = random.choice(_SAMPLES)
    sig  = extract_fit_signal(text)
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


class TQUser(HttpUser):
    """Hits the TurboQuant 3b-key/2b-val server on :8000."""
    host       = "http://localhost:8000"
    wait_time  = between(1, 3)

    @task
    def fit_recommendation(self):
        with self.client.post(
            "/v1/chat/completions",
            json=_make_payload(),
            headers={"Authorization": "Bearer x"},
            catch_response=True,
            name="tq /v1/chat/completions",
        ) as resp:
            if resp.status_code != 200:
                resp.failure(f"HTTP {resp.status_code}")
