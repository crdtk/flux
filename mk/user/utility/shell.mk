SSH_KEY             := $(USER_HOME)/.ssh/id_ed25519
SSH_CONFIG          := $(USER_HOME)/.ssh/config
BASHRC              := $(USER_HOME)/.bashrc
MAKE_COMPLETION     := /usr/share/bash-completion/completions/make
MAKE_COMPLETION_OK  := $(shell grep -c 'bash-completion/completions/make' $(BASHRC) 2>/dev/null)

define SSH_CONFIG_CONTENT
Host crucible
	HostName concise.dynv6.net
	User m
	IdentityFile $(SSH_KEY)
	ServerAliveInterval 60
endef

USER_FILES += $(USER_HOME)/.ssh/authorized_keys $(SSH_CONFIG)

.PHONY: configure-shell
configure-shell:
ifeq ($(MAKE_COMPLETION_OK),0)
	echo 'source $(MAKE_COMPLETION)' >> $(BASHRC)
	@echo ">>> Make autocomplete enabled"
endif

$(USER_HOME)/.ssh/authorized_keys: $(SSH_KEY)
	cat $(SSH_KEY).pub >> $@
	chmod 600 $@
	@echo ">>> SSH key authorized for localhost"

$(SSH_KEY):
	ssh-keygen -t ed25519 -f $@ -N ""
	@echo ">>> SSH key generated: $@"

$(SSH_CONFIG): $(SSH_KEY)
	mkdir -p $(dir $@)
	$(file >$@,$(SSH_CONFIG_CONTENT))
	chmod 600 $@
	@echo ">>> $@"
