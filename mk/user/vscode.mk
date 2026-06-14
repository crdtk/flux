VSCODE_JUPYTER_OK     := $(shell ls $(USER_HOME)/.vscode/extensions 2>/dev/null | grep -c '^ms-toolsai.jupyter-')
VSCODE_PYTHON_OK      := $(shell ls $(USER_HOME)/.vscode/extensions 2>/dev/null | grep -c '^ms-python.python-')
VSCODE_REMOTE_SSH_OK  := $(shell ls $(USER_HOME)/.vscode/extensions 2>/dev/null | grep -c '^ms-vscode-remote.remote-ssh-')

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
