# Constitutional rule: ONE project venv at $(CURDIR)/.venv, rebuilt when
# requirements.txt changes. All targets (jupyter, papermill, demos) use this
# shared venv. Ephemeral runs use `uv run --with <pkg>` (no persistent venv).
# uv/kaggle drift is owned by POST (post/post.pl: user_tool, XXI).

UV := $(USER_HOME)/.local/bin/uv
VENV := $(CURDIR)/.venv
VENV_PY := $(VENV)/bin/python3
VENV_PIP = VIRTUAL_ENV=$(VENV) $(UV) pip install

$(UV):
	curl -LsSf https://astral.sh/uv/install.sh | sh
	@echo ">>> uv installed"

# Single repo venv, built on first use or when requirements.txt changes.
# Install all shared demo deps here (jupyter, ipykernel, torch, tokenizers, etc.).
$(VENV_PY): | $(UV)
	$(UV) venv $(VENV) --python 3.12
	$(VENV_PIP) ipykernel jupyter torch tokenizers huggingface_hub safetensors papermill flash-linear-attention causal-conv1d
	$(VENV_PY) -m ipykernel install --user --name turboquant --display-name "TurboQuant (repo)"
	@echo ">>> single repo venv ready at $(VENV)"
