UV       := $(USER_HOME)/.local/bin/uv
LLMS_VENV := demos/LLMs-from-scratch/venv

# The LLMs-from-scratch venv is gated on its repo being cloned — without
# requirements.txt there's nothing to build, so skip it rather than halt the run (III).
USER_FILES += $(UV) $(USER_HOME)/.local/bin/kaggle \
              $(if $(wildcard demos/LLMs-from-scratch/requirements.txt),$(LLMS_VENV)/bin/jupyter)

$(UV):
	curl -LsSf https://astral.sh/uv/install.sh | sh
	@echo ">>> uv installed"

$(USER_HOME)/.local/bin/kaggle: | $(UV)
	$(UV) tool install kaggle
	@echo ">>> kaggle CLI ready"

$(LLMS_VENV)/bin/jupyter: demos/LLMs-from-scratch/requirements.txt | $(UV)
	$(UV) venv --python 3.12 --clear $(LLMS_VENV)
	VIRTUAL_ENV=$(LLMS_VENV) $(UV) pip install -r $<
	$(LLMS_VENV)/bin/python -m ipykernel install --user --name llms-from-scratch --display-name "LLMs-from-scratch"
	@echo ">>> LLMs-from-scratch deps installed"
