# uv/kaggle drift is owned by POST (post/post.pl: user_tool, XXI). This module
# keeps the venv build: rebuild-on-requirements.txt-change is timestamp
# semantics only Make has. The $(UV) bootstrap stays as the venv's order-only
# prerequisite (XVIII) so the build works on a box POST hasn't converged yet.

UV        := $(USER_HOME)/.local/bin/uv
LLMS_VENV := demos/LLMs-from-scratch/venv

# Demo venv excluded from default flows — run explicitly: make $(LLMS_VENV)/bin/jupyter

$(UV):
	curl -LsSf https://astral.sh/uv/install.sh | sh
	@echo ">>> uv installed"

$(LLMS_VENV)/bin/jupyter: demos/LLMs-from-scratch/requirements.txt | $(UV)
	$(UV) venv --python 3.12 --clear $(LLMS_VENV)
	VIRTUAL_ENV=$(LLMS_VENV) $(UV) pip install -r $<
	$(LLMS_VENV)/bin/python -m ipykernel install --user --name llms-from-scratch --display-name "LLMs-from-scratch"
	@echo ">>> LLMs-from-scratch deps installed"
