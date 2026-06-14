include mk/user/panels/plasmashell.mk

DOCK_OK            := $(shell grep -B 10 'org.kde.plasma.icontasks' $(USER_HOME)/.config/plasma-org.kde.plasma.desktop-appletsrc 2>/dev/null | grep -c 'location=4')
SCREEN_W           := $(shell xrandr --current 2>/dev/null | awk '/*/{split($$1,a,"x"); print a[1]; exit}')
## Gate on the config value we actually care about, not on knowing the panel ID at parse time.
DOCK_CONFIGURED_OK := $(shell grep -c 'panelVisibility=1' $(USER_HOME)/.config/plasmashellrc 2>/dev/null)

## Bottom panel: app launcher + launchpad + task manager.
## JS creates the panel; kwriteconfig6 writes geometry/visibility to plasmashellrc post-creation.
define DOCK_PANEL_JS
  var d = new Panel;
  d.location = "bottom";
  d.addWidget("org.kde.plasma.kickoff");
  d.addWidget("org.kde.plasma.applicationdashboard");
  d.addWidget("org.kde.plasma.icontasks");
endef

.PHONY: configure-bottom-panel .remove-bottom-panels

.remove-bottom-panels:
	gdbus call --session --dest org.kde.plasmashell --object-path /PlasmaShell \
	  --method org.kde.PlasmaShell.evaluateScript \
	  'var all=panels();for(var i=0;i<all.length;i++){if(all[i].location==4){all[i].remove();}}' >/dev/null 2>&1 || true

configure-bottom-panel: .ensure-plasmashell .remove-bottom-panels
	@gdbus call --session --dest org.kde.plasmashell --object-path /PlasmaShell \
	  --method org.kde.PlasmaShell.evaluateScript '$(strip $(DOCK_PANEL_JS))' >/dev/null 2>&1 \
	  && echo ">>> Bottom panel created" \
	  || echo ">>> WARNING: bottom panel not created (plasmashell down)"
	@ID=$$(grep -B 3 'org.kde.plasma.icontasks' $(USER_HOME)/.config/plasma-org.kde.plasma.desktop-appletsrc 2>/dev/null | grep -oP '(?<=\[Containments\]\[)\d+' | tail -1); \
	 [ -n "$$ID" ] || { echo ">>> Dock not ready — run make again"; exit 0; }; \
	 kwriteconfig6 --file $(USER_HOME)/.config/plasmashellrc --group "PlasmaViews" --group "Panel $$ID" --key "floating" "0"; \
	 kwriteconfig6 --file $(USER_HOME)/.config/plasmashellrc --group "PlasmaViews" --group "Panel $$ID" --key "panelLengthMode" "1"; \
	 kwriteconfig6 --file $(USER_HOME)/.config/plasmashellrc --group "PlasmaViews" --group "Panel $$ID" --key "panelOpacity" "2"; \
	 kwriteconfig6 --file $(USER_HOME)/.config/plasmashellrc --group "PlasmaViews" --group "Panel $$ID" --key "panelVisibility" "1"; \
	 kwriteconfig6 --file $(USER_HOME)/.config/plasmashellrc --group "PlasmaViews" --group "Panel $$ID" --group "Defaults" --key "thickness" "60"; \
	 kwriteconfig6 --file $(USER_HOME)/.config/plasmashellrc --group "PlasmaViews" --group "Panel $$ID" --group "Horizontal$(SCREEN_W)" --key "alignment" "132"; \
	 echo ">>> Bottom panel configured (auto-hide, fit, 60px)"
