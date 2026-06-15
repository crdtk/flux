UV       := $(USER_HOME)/.local/bin/uv
LLMS_VENV := demos/LLMs-from-scratch/venv

USER_FILES += $(UV) $(LLMS_VENV)/bin/jupyter $(USER_HOME)/.local/bin/kaggle

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
