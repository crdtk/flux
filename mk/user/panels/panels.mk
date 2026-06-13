include mk/user/panels/top.mk
include mk/user/panels/bottom.mk

PLASMASHELL_RUNNING       := $(shell systemctl --user is-active plasma-plasmashell.service 2>/dev/null | grep -c '^active')
## Non-empty when panels were created this run and plasmashell needs one restart at the end.
PLASMASHELL_NEEDS_RESTART := $(or $(filter 0,$(GLOBALMENU_OK)),$(filter 0,$(DOCK_OK)),$(filter 0,$(DOCK_CONFIGURED_OK)))

.PHONY: .ensure-plasmashell
.ensure-plasmashell:
ifeq ($(PLASMASHELL_RUNNING),0)
	systemctl --user reset-failed plasma-plasmashell.service 2>/dev/null || true
	systemctl --user start plasma-plasmashell.service
	@echo ">>> plasmashell started"
endif

include mk/user/panels/desktop.mk
