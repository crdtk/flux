MAKEFLAGS += --no-builtin-rules
.SUFFIXES:

USER_HOME ?= $(shell getent passwd $${SUDO_USER:-$$(whoami)} | cut -d: -f6)
MODEL_DIR ?= $(USER_HOME)/models
UV        ?= $(USER_HOME)/.local/bin/uv

DEMO_DIR      := $(CURDIR)
DEMO_SENTINEL := $(DEMO_DIR)/.sentinel
$(shell mkdir -p $(DEMO_SENTINEL))
TURBO_DIR     ?=
VENV          := $(DEMO_DIR)/.venv
VENV_PY       := $(VENV)/bin/python3
VENV_PIP       = VIRTUAL_ENV=$(VENV) $(UV) pip install

# ---- Stage 1: uv ----
$(DEMO_SENTINEL)/uv-installed:
	curl -LsSf https://astral.sh/uv/install.sh | sh
	touch $@
	@echo ">>> uv ready at $(UV)"

# ---- Stage 2: venv (Python 3.12 — llvmlite 0.44 doesn't support 3.14) ----
$(DEMO_SENTINEL)/demo-venv: $(DEMO_SENTINEL)/uv-installed
	$(UV) venv $(VENV) --python 3.12
	touch $@
	@echo ">>> venv at $(VENV) (python 3.12)"

# ---- Stage 3: Python deps + install package in editable mode ----
$(DEMO_SENTINEL)/demo-deps: $(DEMO_SENTINEL)/demo-venv
	$(VENV_PIP) \
	    "vllm==0.18.0" \
	    transformers \
	    accelerate \
	    streamlit \
	    pynvml \
	    "huggingface_hub[cli]" \
	    openai \
	    triton \
	    locust \
	    pyspark
	$(VENV_PIP) -e "$(DEMO_DIR)"
	@[ -n "$(TURBO_DIR)" ] && $(VENV_PIP) -e "$(TURBO_DIR)" || true
	touch $@
	@echo ">>> demo deps installed (vllm==0.18.0)"

# ---- Stage 4: model download ----
# Model is public — no HF login needed.
.PHONY: demo-model
DEMO_MODEL_HF  ?= casperhansen/deepseek-r1-distill-qwen-7b-awq
DEMO_MODEL_DIR := $(MODEL_DIR)/$(notdir $(DEMO_MODEL_HF))
demo-model: $(DEMO_SENTINEL)/demo-deps | $(MODEL_DIR)
	$(VENV_PY) -c "from huggingface_hub import snapshot_download; \
snapshot_download('$(DEMO_MODEL_HF)', local_dir='$(DEMO_MODEL_DIR)')"
	@echo ">>> model ready: $(DEMO_MODEL_DIR)"

$(MODEL_DIR):
	mkdir -p $@

.PHONY: bench-bert
bench-bert: $(DEMO_SENTINEL)/demo-deps
	cd $(DEMO_DIR) && $(VENV_PY) -m turboquant_demo.bert

.PHONY: bench-tq
bench-tq: $(DEMO_SENTINEL)/demo-deps
	@curl -sf http://localhost:8000/health >/dev/null 2>&1 || \
	    { echo ">>> TQ server not running — run: make demo-servers"; exit 1; }
	@curl -sf http://localhost:8001/health >/dev/null 2>&1 || \
	    { echo ">>> Baseline server not running — run: make demo-servers"; exit 1; }
	cd $(DEMO_DIR) && $(VENV_PY) -m turboquant_demo.sweep
	@echo ">>> results: $(DEMO_DIR)/bench_results.json"

.PHONY: bench-spark
bench-spark: $(DEMO_SENTINEL)/demo-deps
	cd $(DEMO_DIR) && $(VENV_PY) -m turboquant_demo.pipeline \
	    --generate \
	    --input  data/returns.parquet \
	    --output data/profiles.parquet
	@echo ">>> profiles: $(DEMO_DIR)/data/profiles.parquet"

.PHONY: bench-pipeline
bench-pipeline: $(DEMO_SENTINEL)/demo-deps
	@curl -sf http://localhost:8000/health >/dev/null 2>&1 || \
	    { echo ">>> TQ server not running — run: make demo-servers"; exit 1; }
	cd $(DEMO_DIR) && $(VENV_PY) -m turboquant_demo.latency

.PHONY: demo-servers
demo-servers: $(DEMO_SENTINEL)/demo-deps
	@echo ">>> Splitting A4000 16GB: 0.42 each, eager mode (baseline :8001, TQ :8000)"
	$(DEMO_DIR)/scripts/start_servers.sh "$(DEMO_MODEL_DIR)"

.PHONY: demo-fit
demo-fit: $(DEMO_SENTINEL)/demo-deps
	cd $(DEMO_DIR) && $(VENV)/bin/streamlit run turboquant_demo/app.py \
	    --browser.gatherUsageStats false \
	    --server.headless true

.PHONY: bench-locust
LOCUST_USERS ?= 4
LOCUST_RATE  ?= 1
LOCUST_TIME  ?= 60s
LOCUST_CSV   ?= $(DEMO_DIR)/locust_results
bench-locust: $(DEMO_SENTINEL)/demo-deps
	@curl -sf http://localhost:8000/health >/dev/null 2>&1 || \
	    { echo ">>> TQ server not running — run: make demo-servers"; exit 1; }
	@curl -sf http://localhost:8001/health >/dev/null 2>&1 || \
	    { echo ">>> Baseline server not running — run: make demo-servers"; exit 1; }
	cd $(DEMO_DIR) && $(VENV)/bin/locust \
	    -f turboquant_demo/locustfile.py \
	    --headless \
	    -u $(LOCUST_USERS) -r $(LOCUST_RATE) -t $(LOCUST_TIME) \
	    --csv $(LOCUST_CSV) \
	    --host http://localhost:8000
	@echo ">>> results: $(LOCUST_CSV)_stats.csv"

.PHONY: locust-ui
locust-ui: $(DEMO_SENTINEL)/demo-deps
	@curl -sf http://localhost:8000/health >/dev/null 2>&1 || \
	    { echo ">>> TQ server not running — run: make demo-servers"; exit 1; }
	@echo ">>> Locust UI at http://localhost:8089"
	cd $(DEMO_DIR) && $(VENV)/bin/locust \
	    -f turboquant_demo/locustfile.py \
	    --host http://localhost:8000

.PHONY: colab-upload
COLAB_REMOTE ?= gdrive
COLAB_DIR    ?= Colab Notebooks
COLAB_NB     := $(DEMO_DIR)/prefix_caching_demo.ipynb
colab-upload: $(COLAB_NB)
	@command -v rclone >/dev/null || { echo ">>> rclone not found — run: sudo make"; exit 1; }
	@rclone listremotes | grep -q "^$(COLAB_REMOTE):" || { echo ">>> run: rclone config — add a Google Drive remote named '$(COLAB_REMOTE)'"; exit 1; }
	rclone copy $(COLAB_NB) "$(COLAB_REMOTE):$(COLAB_DIR)/"
	@echo ">>> uploaded to $(COLAB_REMOTE):$(COLAB_DIR)/$(notdir $(COLAB_NB))"

.PHONY: clean
clean:
	-kill $$(cat /tmp/vllm-base.pid 2>/dev/null) 2>/dev/null; rm -f /tmp/vllm-base.pid
	-kill $$(cat /tmp/vllm-tq.pid  2>/dev/null) 2>/dev/null; rm -f /tmp/vllm-tq.pid
	rm -rf $(DEMO_DIR)/.venv $(DEMO_DIR)/.sentinel
	@echo ">>> demo venv cleaned (source preserved in turboquant-demo/)"
