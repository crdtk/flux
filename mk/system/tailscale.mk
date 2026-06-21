# Tailscale — mesh VPN replacing DynDNS, UPnP pinholes, and WAN port forwarding.
# Provides stable hostnames (MagicDNS) and direct connectivity without open
# ports or port forwarding. Installed from the upstream repo for the latest
# stable release.

TAILSCALE_LOGGED_IN := $(shell tailscale status 2>/dev/null | grep -qc '^100\.' && echo 1)
TAILSCALE_AUTH_KEY  := $(shell sed -n 's/^tailscale_auth_key=//p' $(PROJECTS)/secrets/tailscale.conf 2>/dev/null | tr -d "'\"")

ifneq ($(TAILSCALE_LOGGED_IN),1)
MANAGEMENT += $(if $(TAILSCALE_AUTH_KEY),.tailscale-up-with-key,.tailscale-up-warn)
endif

TAILSCALE_UP_FLAGS := --accept-routes --accept-dns

.tailscale-up-with-key: /usr/bin/tailscale
	tailscale up --authkey "$(TAILSCALE_AUTH_KEY)" $(TAILSCALE_UP_FLAGS)
	@echo ">>> Tailscale authenticated"

.tailscale-up-warn: /usr/bin/tailscale
	@echo ">>> WARNING: Tailscale installed but not authenticated."
	@echo ">>> Run 'tailscale up' as root interactively to connect."
	@echo ">>> Or store an auth key: echo 'tailscale_auth_key=tskey-...' > $(PROJECTS)/secrets/tailscale.conf"

/usr/bin/tailscale: /etc/apt/sources.list.d/tailscale.list
	$(APT) update
	$(APT) install -y tailscale

/etc/apt/sources.list.d/tailscale.list: /usr/share/keyrings/tailscale-archive-keyring.gpg
	curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/$(UBUNTU_CODENAME).tailscale-keyring.list -o $@

/usr/share/keyrings/tailscale-archive-keyring.gpg:
	curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/$(UBUNTU_CODENAME).noarmor.gpg -o $@
