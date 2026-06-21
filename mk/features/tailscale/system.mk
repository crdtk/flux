# Tailscale — mesh VPN replacing DynDNS, UPnP pinholes, and WAN port forwarding.
# Provides stable hostnames (MagicDNS) and direct connectivity without open
# ports or port forwarding. Installed from the upstream repo for the latest
# stable release.

# Contract with user.mk: the user half writes this file, the system half reads the key.
# Read via $(shell) (not -include) so Make doesn't try to rebuild the file at parse time.
TAILSCALE_CONF := $(PROJECTS)/secrets/tailscale.conf
tailscale_auth_key := $(shell test -f $(TAILSCALE_CONF) && sed -n 's/^tailscale_auth_key=//p' $(TAILSCALE_CONF))

TAILSCALE_LOGGED_IN := $(shell tailscale status 2>/dev/null | grep -qc '^100\.' && echo 1)

ifneq ($(TAILSCALE_LOGGED_IN),1)
MANAGEMENT += .tailscale-ensure
endif

/usr/bin/tailscale: /etc/apt/sources.list.d/tailscale.list
	$(APT) update
	$(APT) install -y tailscale

TAILSCALE_UP_FLAGS := --accept-routes --accept-dns

.tailscale-ensure: /usr/bin/tailscale
	$(if $(tailscale_auth_key),tailscale up --authkey "$(tailscale_auth_key)" $(TAILSCALE_UP_FLAGS))
	$(if $(tailscale_auth_key),@echo ">>> Tailscale authenticated",@echo ">>> WARNING: Tailscale installed but not authenticated.")

/etc/apt/sources.list.d/tailscale.list: /usr/share/keyrings/tailscale-archive-keyring.gpg
	curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/$(UBUNTU_CODENAME).tailscale-keyring.list -o $@

/usr/share/keyrings/tailscale-archive-keyring.gpg:
	curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/$(UBUNTU_CODENAME).noarmor.gpg -o $@
