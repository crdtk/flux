include mk/features/Settings/Panels/top.mk
include mk/features/Settings/Panels/bottom.mk

include mk/features/Settings/Panels/desktop.mk

TOP_PANEL_OK    := $(shell grep -c 'location=3' $(APPLETSRC) 2>/dev/null)
BOTTOM_PANEL_OK := $(shell grep -c 'location=4' $(APPLETSRC) 2>/dev/null)
user::
ifeq ($(TOP_PANEL_OK),0)
	@gdbus call --session --dest org.kde.plasmashell --object-path /PlasmaShell --method org.kde.PlasmaShell.evaluateScript '$(strip $(TOP_PANEL_JS))' >/dev/null 2>&1 && echo ">>> Top panel created" || echo ">>> WARNING: top panel not created (plasmashell down)"
endif
ifeq ($(BOTTOM_PANEL_OK),0)
	@gdbus call --session --dest org.kde.plasmashell --object-path /PlasmaShell --method org.kde.PlasmaShell.evaluateScript '$(strip $(DOCK_PANEL_JS))' >/dev/null 2>&1 && echo ">>> Bottom panel created (auto-hide, fit, 60px)" || echo ">>> WARNING: bottom panel not created (plasmashell down)"
endif
