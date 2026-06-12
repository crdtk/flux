CLAUDE_BIN      := $(USER_HOME)/.local/bin/claude
SSH_KEY         := $(USER_HOME)/.ssh/id_ed25519
BASHRC          := $(USER_HOME)/.bashrc
MAKE_COMPLETION := /usr/share/bash-completion/completions/make

user: $(CLAUDE_BIN) $(USER_HOME)/.ssh/authorized_keys make-completion

$(CLAUDE_BIN):
	mkdir -p $(dir $@)
	@command -v npm >/dev/null 2>&1 || { echo ">>> npm not found — run: sudo make first"; exit 1; }
	npm install --prefix $(USER_HOME)/.local -g @anthropic-ai/claude-code

$(USER_HOME)/.ssh/authorized_keys: $(SSH_KEY)
	cat $(SSH_KEY).pub >> $@
	chmod 600 $@
	@echo ">>> SSH key authorized for localhost"

$(SSH_KEY):
	ssh-keygen -t ed25519 -f $@ -N ""
	@echo ">>> SSH key generated: $@"

.PHONY: make-completion
make-completion:
	@grep -q 'bash-completion/completions/make' $(BASHRC) 2>/dev/null || echo 'source $(MAKE_COMPLETION)' >> $(BASHRC)
	@echo ">>> Make autocomplete enabled"
