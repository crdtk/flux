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

# ---- toolchain chain: uv ← venv ← deps ← model (real outputs, no sentinels) ----
$(UV):
	curl -LsSf https://astral.sh/uv/install.sh | sh

# Python 3.12 — llvmlite 0.44 doesn't support 3.14
$(VENV_PY): $(UV)
	$(UV) venv $(VENV) --python 3.12

$(VENV)/bin/vllm: $(VENV_PY)
	$(VENV_PIP) \
	    "vllm==0.18.0" \
	    transformers \
	    accelerate \
	    pynvml \
	    "huggingface_hub[cli]" \
	    openai \
	    locust

# Model is public — no HF login needed.
$(MODEL_LOCAL)/config.json: $(VENV)/bin/vllm
	$(VENV_PY) -c "from huggingface_hub import snapshot_download; \
snapshot_download('$(MODEL_HF)', local_dir='$(MODEL_LOCAL)')"

.PHONY: servers
servers: $(MODEL_LOCAL)/config.json
	@echo ">>> Splitting A4000 16GB: 0.42 each, eager mode (baseline :8001, fp8 :8000)"
	$(BENCH_DIR)/scripts/start_servers.sh "$(MODEL_LOCAL)"

.PHONY: servers-stop
servers-stop:
	$(BENCH_DIR)/scripts/stop_servers.sh

define REQUIRE_SERVERS
	@curl -sf http://localhost:8001/health >/dev/null 2>&1 || \
	    { echo ">>> baseline server not running — run: make servers"; exit 1; }
	@curl -sf http://localhost:8000/health >/dev/null 2>&1 || \
	    { echo ">>> fp8 server not running — run: make servers"; exit 1; }
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
