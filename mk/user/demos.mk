LLMS_VENV := demos/LLMs-from-scratch/venv

USER_FILES += $(LLMS_VENV)/bin/jupyter

$(LLMS_VENV)/bin/jupyter: demos/LLMs-from-scratch/requirements.txt
	python3.12 -m venv $(LLMS_VENV)
	$(LLMS_VENV)/bin/pip install -r $<
	$(LLMS_VENV)/bin/python -m ipykernel install --user --name llms-from-scratch --display-name "LLMs-from-scratch"
	@echo ">>> LLMs-from-scratch deps installed"
