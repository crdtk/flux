ifndef _PLASMASHELL_MK
_PLASMASHELL_MK := 1

PLASMASHELL_RUNNING := $(shell systemctl --user is-active plasma-plasmashell.service 2>/dev/null | grep -c '^active')

.PHONY: .ensure-plasmashell
.ensure-plasmashell:
ifeq ($(PLASMASHELL_RUNNING),0)
	systemctl --user reset-failed plasma-plasmashell.service 2>/dev/null || true
	systemctl --user start plasma-plasmashell.service
	@echo ">>> plasmashell started"
endif

endif
