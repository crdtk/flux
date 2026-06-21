VSCODE_JUPYTER_OK     := $(shell ls $(USER_HOME)/.vscode/extensions 2>/dev/null | grep -c '^ms-toolsai.jupyter-')
VSCODE_PYTHON_OK      := $(shell ls $(USER_HOME)/.vscode/extensions 2>/dev/null | grep -c '^ms-python.python-')
VSCODE_REMOTE_SSH_OK  := $(shell ls $(USER_HOME)/.vscode/extensions 2>/dev/null | grep -c '^ms-vscode-remote.remote-ssh-')
VSCODE_COLAB_OK       := $(shell ls $(USER_HOME)/.vscode/extensions 2>/dev/null | grep -c '^google.colab-')
VSCODE_GITMSG_OK      := $(shell ls $(USER_HOME)/.vscode/extensions 2>/dev/null | grep -c '^businessaddonscom.gitmessagegenerator-')

VSCODE_SETTINGS      := $(CURDIR)/.vscode/settings.json
VSCODE_USER_SETTINGS := $(USER_HOME)/.config/Code/User/settings.json
OPENCODE_ZEN_KEY     := $(shell sed -n 's/^opencode_zen_key=//p' $(PROJECTS)/secrets/opencode.conf 2>/dev/null | tr -d "'\"")
USER_FILES           += $(VSCODE_SETTINGS)

$(VSCODE_SETTINGS):
	mkdir -p $(dir $@)
	printf '{}' | jq '. + {"python.defaultInterpreterPath": ".venv/bin/python3"}' > $@
	@echo ">>> .vscode/settings.json: defaultInterpreterPath → .venv/bin/python3"

.PHONY: configure-vscode

configure-vscode:
ifeq ($(VSCODE_PYTHON_OK),0)
	code --install-extension ms-python.python
	@echo ">>> VS Code: Python extension installed"
endif
ifeq ($(VSCODE_JUPYTER_OK),0)
	code --install-extension ms-toolsai.jupyter
	@echo ">>> VS Code: Jupyter extension installed"
endif
ifeq ($(VSCODE_REMOTE_SSH_OK),0)
	code --install-extension ms-vscode-remote.remote-ssh
	@echo ">>> VS Code: Remote SSH extension installed"
endif
ifeq ($(VSCODE_COLAB_OK),0)
	code --install-extension Google.colab
	@echo ">>> VS Code: Google Colab extension installed"
endif
ifeq ($(VSCODE_GITMSG_OK),0)
	code --install-extension BusinessAddonscom.gitmessagegenerator
	@echo ">>> VS Code: gitMessageGenerator extension installed"
endif
ifneq ($(OPENCODE_ZEN_KEY),)
	mkdir -p $(dir $(VSCODE_USER_SETTINGS))
	touch $(VSCODE_USER_SETTINGS)
	jq --arg key "$(OPENCODE_ZEN_KEY)" '. + {"gitMessageGenerator.opencodeZenKey": $$key, "gitMessageGenerator.provider": "opencode-zen"}' $(VSCODE_USER_SETTINGS) > $(VSCODE_USER_SETTINGS).tmp
	mv $(VSCODE_USER_SETTINGS).tmp $(VSCODE_USER_SETTINGS)
	@echo ">>> OpenCode Zen configured for commit messages via gitMessageGenerator"
endif
