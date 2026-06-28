VSCODE_SETTINGS := $(CURDIR)/.vscode/settings.json
USER_FILES      += $(VSCODE_SETTINGS)

# Absolute path via ${workspaceFolder}: a relative ".venv/bin/python3" makes the pet
# locator spawn from its own cwd and fail to resolve (then it silently auto-discovers).
# Merge, don't clobber — preserves any other keys already in the file.
$(VSCODE_SETTINGS):
	@mkdir -p $(dir $@) && { test -f $@ || printf '{}' > $@; } && jq '. + {"python.defaultInterpreterPath": "$${workspaceFolder}/.venv/bin/python"}' $@ > $@.tmp && mv $@.tmp $@ && echo ">>> .vscode/settings.json: defaultInterpreterPath set"

# Sentinel files record extension installs so Make can track them as real targets.
# Pattern: detection var + conditional USER_FILES + sentinel target, all clustered.
VSCODE_EXT_DIR := $(USER_HOME)/.local/share/make/vscode-ext

$(VSCODE_EXT_DIR):
	mkdir -p $@

VSCODE_PYTHON_OK := $(shell ls $(USER_HOME)/.vscode/extensions 2>/dev/null | grep -c '^ms-python.python-')
USER_FILES       += $(if $(filter 0,$(VSCODE_PYTHON_OK)),$(VSCODE_EXT_DIR)/ms-python.python,)

$(VSCODE_EXT_DIR)/ms-python.python: | $(VSCODE_EXT_DIR)
	@code --install-extension ms-python.python && touch $@ && echo ">>> VS Code: Python extension installed"

VSCODE_JUPYTER_OK := $(shell ls $(USER_HOME)/.vscode/extensions 2>/dev/null | grep -c '^ms-toolsai.jupyter-')
USER_FILES        += $(if $(filter 0,$(VSCODE_JUPYTER_OK)),$(VSCODE_EXT_DIR)/ms-toolsai.jupyter,)

$(VSCODE_EXT_DIR)/ms-toolsai.jupyter: | $(VSCODE_EXT_DIR)
	@code --install-extension ms-toolsai.jupyter && touch $@ && echo ">>> VS Code: Jupyter extension installed"

VSCODE_REMOTE_SSH_OK := $(shell ls $(USER_HOME)/.vscode/extensions 2>/dev/null | grep -c '^ms-vscode-remote.remote-ssh-')
USER_FILES           += $(if $(filter 0,$(VSCODE_REMOTE_SSH_OK)),$(VSCODE_EXT_DIR)/ms-vscode-remote.remote-ssh,)

$(VSCODE_EXT_DIR)/ms-vscode-remote.remote-ssh: | $(VSCODE_EXT_DIR)
	@code --install-extension ms-vscode-remote.remote-ssh && touch $@ && echo ">>> VS Code: Remote SSH extension installed"

VSCODE_COLAB_OK := $(shell ls $(USER_HOME)/.vscode/extensions 2>/dev/null | grep -c '^google.colab-')
USER_FILES      += $(if $(filter 0,$(VSCODE_COLAB_OK)),$(VSCODE_EXT_DIR)/google.colab,)

$(VSCODE_EXT_DIR)/google.colab: | $(VSCODE_EXT_DIR)
	@code --install-extension Google.colab && touch $@ && echo ">>> VS Code: Google Colab extension installed"

VSCODE_GITMSG_OK := $(shell ls $(USER_HOME)/.vscode/extensions 2>/dev/null | grep -c '^businessaddonscom.gitmessagegenerator-')
USER_FILES       += $(if $(filter 0,$(VSCODE_GITMSG_OK)),$(VSCODE_EXT_DIR)/businessaddonscom.gitmessagegenerator,)

$(VSCODE_EXT_DIR)/businessaddonscom.gitmessagegenerator: | $(VSCODE_EXT_DIR)
	@code --install-extension BusinessAddonscom.gitmessagegenerator && touch $@ && echo ">>> VS Code: gitMessageGenerator extension installed"

# OPENCODE_ZEN_KEY comes from the environment (Make auto-imports env vars).
VSCODE_USER_SETTINGS := $(USER_HOME)/.config/Code/User/settings.json
USER_FILES           += $(if $(OPENCODE_ZEN_KEY),$(VSCODE_USER_SETTINGS),)

$(VSCODE_USER_SETTINGS):
	@mkdir -p $(dir $@) && { test -f $@ || printf '{}' > $@; } && jq --arg key "$(OPENCODE_ZEN_KEY)" '. + {"gitMessageGenerator.opencodeZenKey": $$key, "gitMessageGenerator.provider": "opencode-zen"}' $@ > $@.tmp && mv $@.tmp $@ && echo ">>> OpenCode Zen configured for commit messages"
