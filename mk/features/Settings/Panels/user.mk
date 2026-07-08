include mk/features/Settings/Panels/top.mk
include mk/features/Settings/Panels/bottom.mk

include mk/features/Settings/Panels/desktop.mk

TOP_PANEL_OK    := $(shell grep -c 'location=3' $(APPLETSRC) 2>/dev/null)
BOTTOM_PANEL_OK := $(shell grep -c 'location=4' $(APPLETSRC) 2>/dev/null)
PANELS_MISSING  := $(filter 0,$(TOP_PANEL_OK))$(filter 0,$(BOTTOM_PANEL_OK))
user::
ifneq ($(PANELS_MISSING),)
	@python3 -c "$$STRIP_PANELS_PY" $(APPLETSRC) 2>/dev/null || true
	@systemctl --user restart plasma-plasmashell.service
	@until systemctl --user is-active plasma-plasmashell.service >/dev/null 2>&1; do sleep 1; done
	@echo ">>> plasmashell restarted with clean panel config"
ifeq ($(TOP_PANEL_OK),0)
	@gdbus call --session --dest org.kde.plasmashell --object-path /PlasmaShell --method org.kde.PlasmaShell.evaluateScript '$(strip $(TOP_PANEL_JS))' >/dev/null 2>&1 && echo ">>> Top panel created" || echo ">>> WARNING: top panel not created (plasmashell down)"
endif
ifeq ($(BOTTOM_PANEL_OK),0)
	@gdbus call --session --dest org.kde.plasmashell --object-path /PlasmaShell --method org.kde.PlasmaShell.evaluateScript '$(strip $(DOCK_PANEL_JS))' >/dev/null 2>&1 && echo ">>> Bottom panel created (auto-hide, fit, 60px)" || echo ">>> WARNING: bottom panel not created (plasmashell down)"
endif
endif
