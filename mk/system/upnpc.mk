UPNP_PORTS := 9090 22 8384 22000
LEASE ?= 3600
CRON_MIN := $(shell expr $(LEASE) / 120)

# apt needs root; opening a pinhole does not. So only the install is root — the
# renewal is a user crontab, run unprivileged by cron (VII).
MANAGEMENT += /usr/bin/upnpc
USER_FILES += $(USER_HOME)/.config/cron/upnp-pinholes

# One cron line: a shell loop over the ports requests each pinhole, re-detecting the
# global IPv6 each run (survives a prefix change). Fires at half the lease so pinholes
# never expire. The loop lives in the cron artifact, not a Make recipe.
define UPNP_CRON
*/$(CRON_MIN) * * * * ip6=$$(ip -6 addr show scope global | awk '$$1=="inet6"&&$$2!~/^(fd|fe80)/{sub(/\/.*/,"",$$2);print $$2;exit}'); for p in $(UPNP_PORTS); do upnpc -6 -A "" 0 "$$ip6" $$p TCP $(LEASE) >/dev/null 2>&1; done
endef

$(USER_HOME)/.config/cron/upnp-pinholes: | $(USER_HOME)/.config/cron
	$(file >$@,$(UPNP_CRON))
	crontab $@
	@echo ">>> UPnP pinhole cron installed — every $(CRON_MIN) min, ports: $(UPNP_PORTS)"

$(USER_HOME)/.config/cron:
	mkdir -p $@
