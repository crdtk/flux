VSCODE_SETTINGS := $(CURDIR)/.vscode/settings.json
USER_FILES      += $(VSCODE_SETTINGS)

# Absolute path via ${workspaceFolder}: a relative ".venv/bin/python3" makes the pet
# locator spawn from its own cwd and fail to resolve (then it silently auto-discovers).
# Merge, don't clobber — preserves any other keys already in the file.
$(VSCODE_SETTINGS):
	@mkdir -p $(dir $@) && { test -f $@ || printf '{}' > $@; } && jq '. + {"python.defaultInterpreterPath": "$${workspaceFolder}/.venv/bin/python"}' $@ > $@.tmp && mv $@.tmp $@ && echo ">>> .vscode/settings.json: defaultInterpreterPath set"

user::
VSCODE_PYTHON_OK     := $(shell ls $(USER_HOME)/.vscode/extensions 2>/dev/null | grep -c '^ms-python.python-')
ifeq ($(VSCODE_PYTHON_OK),0)
	@code --install-extension ms-python.python && echo ">>> VS Code: Python extension installed"
endif
VSCODE_JUPYTER_OK    := $(shell ls $(USER_HOME)/.vscode/extensions 2>/dev/null | grep -c '^ms-toolsai.jupyter-')
ifeq ($(VSCODE_JUPYTER_OK),0)
	@code --install-extension ms-toolsai.jupyter && echo ">>> VS Code: Jupyter extension installed"
endif
VSCODE_REMOTE_SSH_OK := $(shell ls $(USER_HOME)/.vscode/extensions 2>/dev/null | grep -c '^ms-vscode-remote.remote-ssh-')
ifeq ($(VSCODE_REMOTE_SSH_OK),0)
	@code --install-extension ms-vscode-remote.remote-ssh && echo ">>> VS Code: Remote SSH extension installed"
endif
VSCODE_COLAB_OK      := $(shell ls $(USER_HOME)/.vscode/extensions 2>/dev/null | grep -c '^google.colab-')
ifeq ($(VSCODE_COLAB_OK),0)
	@code --install-extension Google.colab && echo ">>> VS Code: Google Colab extension installed"
endif
VSCODE_GITMSG_OK     := $(shell ls $(USER_HOME)/.vscode/extensions 2>/dev/null | grep -c '^businessaddonscom.gitmessagegenerator-')
ifeq ($(VSCODE_GITMSG_OK),0)
	@code --install-extension BusinessAddonscom.gitmessagegenerator && echo ">>> VS Code: gitMessageGenerator extension installed"
endif

# OPENCODE_ZEN_KEY comes from the environment (Make auto-imports env vars).
VSCODE_USER_SETTINGS := $(USER_HOME)/.config/Code/User/settings.json
USER_FILES           += $(if $(OPENCODE_ZEN_KEY),$(VSCODE_USER_SETTINGS),)

$(VSCODE_USER_SETTINGS):
	@mkdir -p $(dir $@) && { test -f $@ || printf '{}' > $@; } && jq --arg key "$(OPENCODE_ZEN_KEY)" '. + {"gitMessageGenerator.opencodeZenKey": $$key, "gitMessageGenerator.provider": "opencode-zen"}' $@ > $@.tmp && mv $@.tmp $@ && echo ">>> OpenCode Zen configured for commit messages"
