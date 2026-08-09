feat(bench): fp8 KV capacity result — +56% throughput at saturation; honest harness; Grafana

Serial capacity A/B, reproduced twice (12 closed-loop users, ~1.7k-token
unique prompts, 512-token decodes, 120s per server, identical offered
load): the fp8 KV pool (26,384 tokens) ran 8-12 concurrent sequences
where bf16 (13k) capped at 4 with 8 queued — 64 vs 41 requests (+56%),
median 20s vs 33s (-39%), both pools pinned at 100% and preempting.
Combined with the earlier single-stream sweep (±1-3%): fp8 KV costs
nothing quiet and buys ~1.5x throughput at saturation. Results CSVs
committed as provenance (locust-BaselineUser_*, locust-FP8User_*).

Three measurement traps fixed en route, each caught by the servers' own
counters rather than the harness:

- Locust's CLI --host OVERRIDES per-class hosts: every earlier "A/B"
  sent both user classes to :8000 — one server tested against itself,
  bucket-identical percentiles as the tell (:8001 counters at 4 requests
  vs 2,180). --host removed; classes carry their own hosts. LOCUST_CLASS
  knob added for serial runs (concurrent classes share the A4000's
  compute and degrade in lockstep at saturation, masking capacity).
- vLLM prefix caching deduplicated the identical synthetic histories to
  ONE cached copy (12 x 1.7k-token prompts ~ 7k tokens of real KV, zero
  pressure at any user count). Unique first line per request breaks the
  block-hash chain; load-shape knobs LOCUST_CTX / LOCUST_MAX_TOKENS /
  LOCUST_WAIT expose context, decode length and think-time (the 1-3s
  default wait alone kept duty cycle ~45% and demand under the pool).
- watch-kv target: 1s vLLM gauge view (running/waiting/cache%) — the
  three numbers that ARE the capacity experiment; locust-web target for
  the interactive dashboard.

post/features/net/observability.pl: Prometheus + Grafana as POST rules —
grafana apt repo, packages, Prometheus moved to :9095 (Ubuntu default
9090 is Cockpit's port here; the move is a prerequisite of the service,
XVIII), scrape jobs for both bench servers, provisioned datasource and
the official vLLM dashboard pinned to v0.18.0 so panel metric names
match. Every piece drift-checked (XXI).

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01JqSUPP1cufDUKEE8PzU587
