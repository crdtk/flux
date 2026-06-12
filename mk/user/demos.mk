.PHONY: llms-from-scratch

LLMS_VENV := demos/LLMs-from-scratch/venv

llms-from-scratch: $(LLMS_VENV)/bin/jupyter

$(LLMS_VENV)/bin/jupyter: demos/LLMs-from-scratch/requirements.txt | $(LLMS_VENV)/bin/pip
	$(LLMS_VENV)/bin/pip install -r $<
	@echo ">>> LLMs-from-scratch deps installed"

$(LLMS_VENV)/bin/pip:
	python3 -m venv $(LLMS_VENV)
	@echo ">>> venv created at $(LLMS_VENV)"
