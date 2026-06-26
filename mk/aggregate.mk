# Privilege roll-up — parsed after every feature module so the accumulators
# (HARDENING/MANAGEMENT/PKG_APPS/DISPLAY_CONFIG/COMPUTE/STORAGE, USER_FILES) are
# complete. Branches of the IS_ROOT gate (VIII): `system` builds root artifacts,
# `user` builds the user's. Capability senses: HAS_NVIDIA (common.mk), GPU_BDF
# (ParallelComputing), SN8100 below — each gates only its own hardware's targets.

# ---- system (root) ----
.PHONY: system

# Gate the GPU compute stack on GPU *presence* (HAS_NVIDIA, from lspci), not on
# nvidia-smi: the driver install lives inside COMPUTE, so gating on the post-driver tool
# would make a fresh NVIDIA box never install its own driver. Presence is knowable first run.
SN8100_PRESENT := $(shell test -e /dev/disk/by-label/backup && echo 1)

INSTALL := $(HARDENING) $(MANAGEMENT) $(PKG_APPS) $(DISPLAY_CONFIG) \
           $(if $(HAS_NVIDIA),$(COMPUTE),) \
           $(if $(SN8100_PRESENT),$(STORAGE),)
PENDING := $(filter-out $(wildcard $(INSTALL)),$(INSTALL))

system: $(PENDING)
	update-initramfs -u
	$(APT) autoremove

# ---- user (non-root) ----
.PHONY: user

USER_PENDING := $(filter-out $(wildcard $(USER_FILES)),$(USER_FILES))

user: $(USER_PENDING) \
    configure-top-panel \
    configure-bottom-panel \
    configure-panels \
    configure-shell \
    configure-vscode
	/usr/bin/kbuildsycoca6
	@systemctl --user reset-failed plasma-plasmashell.service 2>/dev/null || true
	@systemctl --user restart plasma-plasmashell.service 2>/dev/null || true
	@echo ">>> plasmashell restarted — system tray indicators (keyboard layout, volume, etc.) will auto-populate"
	@[ -z "$(GPU_BDF)" ] || echo ">>> GPU $(GPU_BDF) PCIe link: $$(cat /sys/bus/pci/devices/$(GPU_BDF)/current_link_speed) x$$(cat /sys/bus/pci/devices/$(GPU_BDF)/current_link_width) (want 8.0 GT/s x4; 2.5 GT/s = reseat/swap cable)"
	@echo
	@echo "=== Tailscale Status ==="
	@tailscale status 2>/dev/null || echo "NOT CONNECTED"
	@echo
	@echo "=== Interface ==="
	@ip addr show tailscale0 2>/dev/null | awk '/inet /{print "  IP: " $$2}' || echo "  No tailscale0 interface"
	@echo
	@echo "=== Peers ==="
	@tailscale status 2>/dev/null | awk 'NR>1{print "  " $$0}' | head -5 || echo "  No peers"
