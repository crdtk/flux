# Tailscale — mesh VPN replacing DynDNS, UPnP pinholes, and WAN port forwarding.
# Provides stable hostnames (MagicDNS) and direct connectivity without open
# ports or port forwarding. Installed from the upstream repo for the latest
# stable release.

# Auth key comes from the environment: TS_AUTHKEY (Make auto-imports env vars). Pass it
# through sudo, e.g. `sudo TS_AUTHKEY=tskey-... make` or `sudo -E make`.
MANAGEMENT         += /usr/bin/tailscale

/usr/bin/tailscale: /etc/apt/sources.list.d/tailscale.list
	$(APT) update; $(APT) install -y tailscale

TAILSCALE_LOGGED_IN := $(shell tailscale status 2>/dev/null | grep -qc '^100\.' && echo 1)
TAILSCALE_UP_FLAGS  := --accept-routes --accept-dns
system::
ifeq ($(TAILSCALE_LOGGED_IN),)
	$(if $(TS_AUTHKEY),tailscale up --authkey "$(TS_AUTHKEY)" $(TAILSCALE_UP_FLAGS) && echo ">>> Tailscale authenticated",echo ">>> WARNING: Tailscale installed but not authenticated (set TS_AUTHKEY).")
endif

/etc/apt/sources.list.d/tailscale.list: /usr/share/keyrings/tailscale-archive-keyring.gpg
	curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/$(UBUNTU_CODENAME).tailscale-keyring.list -o $@

/usr/share/keyrings/tailscale-archive-keyring.gpg:
	curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/$(UBUNTU_CODENAME).noarmor.gpg -o $@
