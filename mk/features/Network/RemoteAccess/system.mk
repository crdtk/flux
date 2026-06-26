# Tailscale — mesh VPN replacing DynDNS, UPnP pinholes, and WAN port forwarding.
# Provides stable hostnames (MagicDNS) and direct connectivity without open
# ports or port forwarding. Installed from the upstream repo for the latest
# stable release.

# Auth key comes from the environment: TS_AUTHKEY (Make auto-imports env vars). Pass it
# through sudo, e.g. `sudo TS_AUTHKEY=tskey-... make .tailscale-ensure` or `sudo -E make`.
TAILSCALE_LOGGED_IN := $(shell tailscale status 2>/dev/null | grep -qc '^100\.' && echo 1)

ifneq ($(TAILSCALE_LOGGED_IN),1)
MANAGEMENT += .tailscale-ensure
endif

/usr/bin/tailscale: /etc/apt/sources.list.d/tailscale.list
	$(APT) update
	$(APT) install -y tailscale

TAILSCALE_UP_FLAGS := --accept-routes --accept-dns

.tailscale-ensure: /usr/bin/tailscale
	$(if $(TS_AUTHKEY),tailscale up --authkey "$(TS_AUTHKEY)" $(TAILSCALE_UP_FLAGS))
	$(if $(TS_AUTHKEY),@echo ">>> Tailscale authenticated",@echo ">>> WARNING: Tailscale installed but not authenticated (set TS_AUTHKEY).")

/etc/apt/sources.list.d/tailscale.list: /usr/share/keyrings/tailscale-archive-keyring.gpg
	curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/$(UBUNTU_CODENAME).tailscale-keyring.list -o $@

/usr/share/keyrings/tailscale-archive-keyring.gpg:
	curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/$(UBUNTU_CODENAME).noarmor.gpg -o $@
