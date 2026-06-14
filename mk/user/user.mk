#include mk/user/albert.mk
include mk/user/shell.mk
include mk/user/demos.mk
include mk/user/panels/panels.mk
include mk/user/plasmoids.mk
include mk/user/references.mk
include mk/user/vscode.mk

USER_PENDING := $(filter-out $(wildcard $(USER_FILES)),$(USER_FILES))

.PHONY: user
user: $(USER_PENDING) \
    configure-top-panel \
    configure-bottom-panel \
    configure-panels \
    configure-shell \
    configure-vscode
	/usr/bin/kbuildsycoca6
	@systemctl --user restart plasma-plasmashell.service
	@echo ">>> plasmashell restarted — system tray indicators (keyboard layout, volume, etc.) will auto-populate"
	@[ -z "$(GPU_BDF)" ] || echo ">>> GPU $(GPU_BDF) PCIe link: $$(cat /sys/bus/pci/devices/$(GPU_BDF)/current_link_speed) x$$(cat /sys/bus/pci/devices/$(GPU_BDF)/current_link_width) (want 8.0 GT/s x4; 2.5 GT/s = reseat/swap cable)"
