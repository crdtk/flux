SSH_KEY             := $(USER_HOME)/.ssh/id_ed25519
SSH_CONFIG          := $(USER_HOME)/.ssh/config
BASHRC              := $(USER_HOME)/.bashrc
MAKE_COMPLETION     := /usr/share/bash-completion/completions/make
MAKE_COMPLETION_OK  := $(shell grep -c 'bash-completion/completions/make' $(BASHRC) 2>/dev/null)
# crucible.dns.army is its own dynv6 zone whose A record is crucible's stable Tailscale
# IP (100.x). dynv6 keeps auto-populating the zone's IPv6 prefix from the account's
# WAN prefix (fed by FRITZ), so AddressFamily inet pins SSH to the IPv4 A record and
# ignores the AAAA entirely — immune to any v6 clobbering. Reaches the box over
# Tailscale: no port forwarding, no WAN exposure, tailnet members only.
define SSH_CONFIG_CONTENT
Host crucible
	HostName crucible.dns.army
	AddressFamily inet
	User m
	IdentityFile $(SSH_KEY)
	ServerAliveInterval 60
endef

USER_FILES += $(USER_HOME)/.ssh/authorized_keys $(SSH_CONFIG) $(USER_HOME)/.config/kwalletrc

# Disable KWallet so nothing ever prompts for a wallet password. On an autologin box
# pam_kwallet can't derive an unlock key (no login password is typed), so disabling is
# the only way to never be asked. ~/.config always exists, so no dir prereq needed.
define KWALLETRC
[Wallet]
Enabled=false
First Use=false
endef

$(USER_HOME)/.config/kwalletrc:
	$(file >$@,$(KWALLETRC))
	@echo ">>> KWallet disabled — no wallet password prompts"

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
