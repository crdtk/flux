include mk/user/utility/utility.mk
include mk/user/development/development.mk
include mk/user/settings/settings.mk

USER_PENDING := $(filter-out $(wildcard $(USER_FILES)),$(USER_FILES))

.PHONY: user
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
