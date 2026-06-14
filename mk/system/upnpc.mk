UPNP_IP6 := $(shell ip -6 addr show scope global 2>/dev/null | awk '$$1=="inet6" && $$2 !~ /^(fd|fe80)/ {sub(/\/.*/,"",$$2); print $$2; exit}')
UPNP_PORTS := 9090 22 8384 22000
LEASE ?= 3600
MANAGEMENT += /usr/bin/upnpc $(foreach p,$(UPNP_PORTS),open-port-$(p))
open-port-%: /usr/bin/upnpc
	@upnpc -6 -A "" 0 $(UPNP_IP6) $* TCP $(LEASE) >/dev/null 2>&1 \
	  && echo ">>> IPv6 pinhole: TCP $* -> [$(UPNP_IP6)] (lease $(LEASE)s)" \
	  || echo ">>> WARNING: pinhole TCP $* not opened (router UPnP off, or no global IPv6)"
