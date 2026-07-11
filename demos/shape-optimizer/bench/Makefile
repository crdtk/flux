MAKEFLAGS += --no-builtin-rules
.SUFFIXES:

USER_HOME ?= $(shell getent passwd $${SUDO_USER:-$$(whoami)} | cut -d: -f6)
MODEL_DIR ?= $(USER_HOME)/models
UV        ?= $(USER_HOME)/.local/bin/uv

BENCH_DIR := $(CURDIR)
VENV      := $(BENCH_DIR)/.venv
VENV_PY   := $(VENV)/bin/python3
VENV_PIP   = VIRTUAL_ENV=$(VENV) $(UV) pip install
RESULTS   := $(BENCH_DIR)/results

MODEL_HF    ?= casperhansen/deepseek-r1-distill-qwen-7b-awq
MODEL_LOCAL := $(MODEL_DIR)/$(notdir $(MODEL_HF))

# ---- toolchain chain: uv ← venv ← deps ← model (real outputs, no sentinels).
# Order-only (|) prerequisites: the chain encodes existence, not freshness —
# a newer uv binary must not recreate the venv and wipe installed deps. ----
$(UV):
	curl -LsSf https://astral.sh/uv/install.sh | sh

# Python 3.12 — llvmlite 0.44 doesn't support 3.14. --clear replaces a
# half-created .venv non-interactively (this rule only fires when bin/python3
# is missing, so anything it replaces was broken).
$(VENV_PY): | $(UV)
	$(UV) venv $(VENV) --python 3.12 --clear

# ninja is a RUNTIME dep of the fp8 KV path: vllm JIT-compiles quantization
# kernels at engine init; without it the fp8 server dies (FileNotFoundError:
# 'ninja') while the bf16 baseline, which compiles nothing, starts fine.
$(VENV)/bin/vllm: | $(VENV_PY)
	$(VENV_PIP) \
	    "vllm==0.18.0" \
	    transformers \
	    accelerate \
	    pynvml \
	    "huggingface_hub[cli]" \
	    openai \
	    locust \
	    ninja

# Converges pre-ninja venvs: the vllm marker above already exists there, so the
# dep rule never refires — this file target backfills ninja on its own.
$(VENV)/bin/ninja: | $(VENV)/bin/vllm
	$(VENV_PIP) ninja

# Model is public — no HF login needed.
$(MODEL_LOCAL)/config.json: | $(VENV)/bin/vllm
	$(VENV_PY) -c "from huggingface_hub import snapshot_download; \
snapshot_download('$(MODEL_HF)', local_dir='$(MODEL_LOCAL)')"

# Fail fast on the wrong host: AWQ needs compute capability >=7.5, fp8 KV
# cache >=8.0, and two 7B servers need 16 GB. This bench targets the RTX
# A4000 (8.6) in the Crucible rig — not ServalWS's GTX 980M (5.2), where
# vLLM dies 4 minutes in with a buried pydantic ValidationError.
# ninja is an invariant of servers (XVIII): without it the fp8 engine dies at
# kernel-compile time, after the health wait has already burned 240s.
.PHONY: servers
servers: $(MODEL_LOCAL)/config.json $(VENV)/bin/ninja
	@cap=$$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1); \
	test -n "$$cap" || { echo ">>> no NVIDIA GPU visible (nvidia-smi failed)"; exit 1; }; \
	awk "BEGIN { exit ($$cap >= 8.0) ? 0 : 1 }" || { \
	    echo ">>> GPU compute capability $$cap < 8.0 — this bench needs the RTX A4000 (8.6) host"; exit 1; }
	@echo ">>> Splitting A4000 16GB: 0.42 each, eager mode (baseline :8001, fp8 :8000)"
	$(BENCH_DIR)/scripts/start_servers.sh "$(MODEL_LOCAL)"

.PHONY: servers-stop
servers-stop:
	$(BENCH_DIR)/scripts/stop_servers.sh

define REQUIRE_SERVERS
	@curl -sf http://localhost:8001/health >/dev/null 2>&1 || \
	    { echo ">>> baseline server not running — run: make servers (on the A4000 host: this is $$(hostname))"; exit 1; }
	@curl -sf http://localhost:8000/health >/dev/null 2>&1 || \
	    { echo ">>> fp8 server not running — run: make servers (on the A4000 host: this is $$(hostname))"; exit 1; }
endef

.PHONY: bench-kv
bench-kv: $(VENV)/bin/vllm
	$(REQUIRE_SERVERS)
	cd $(BENCH_DIR) && $(VENV_PY) kv_bench/sweep.py
	@echo ">>> results: $(RESULTS)/bench_results.json — commit it"

.PHONY: bench-locust
LOCUST_USERS ?= 4
LOCUST_RATE  ?= 1
LOCUST_TIME  ?= 60s
bench-locust: $(VENV)/bin/vllm
	$(REQUIRE_SERVERS)
	@mkdir -p $(RESULTS)
	cd $(BENCH_DIR) && $(VENV)/bin/locust \
	    -f kv_bench/locustfile.py \
	    --headless \
	    -u $(LOCUST_USERS) -r $(LOCUST_RATE) -t $(LOCUST_TIME) \
	    --csv $(RESULTS)/locust \
	    --host http://localhost:8000
	@echo ">>> results: $(RESULTS)/locust_stats.csv — commit it"

.PHONY: clean
clean: servers-stop
	rm -rf $(VENV)
	@echo ">>> bench venv cleaned (results/ preserved — they are provenance)"
