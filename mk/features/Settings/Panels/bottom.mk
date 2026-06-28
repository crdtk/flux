include mk/features/Settings/Panels/plasmashell.mk

## Bottom panel: app launcher + launchpad + task manager.
## All layout properties set via JS — no kwriteconfig6 Panel-ID lookups needed.
## .reset-panels (shared prereq with top) strips appletsrc and restarts plasmashell before this
## runs, so there are no old panel containments to reload from disk.
define DOCK_PANEL_JS
  var d = new Panel;
  d.location = "bottom";
  d.height = 60;
  d.hiding = "autohide";
  d.lengthMode = "fit";
  d.floating = false;
  d.opacity = "opaque";
  d.addWidget("org.kde.plasma.kickoff");
  d.addWidget("org.kde.plasma.applicationdashboard");
  d.addWidget("org.kde.plasma.icontasks");
endef

.PHONY: configure-bottom-panel .remove-bottom-panels

.remove-bottom-panels:
	@gdbus call --session --dest org.kde.plasmashell --object-path /PlasmaShell \
	  --method org.kde.PlasmaShell.evaluateScript \
	  'var all=panels();for(var i=0;i<all.length;i++){if(all[i].location==4){all[i].remove();}}' >/dev/null 2>&1 || true

configure-bottom-panel: reset-panels
	@gdbus call --session --dest org.kde.plasmashell --object-path /PlasmaShell \
	  --method org.kde.PlasmaShell.evaluateScript '$(strip $(DOCK_PANEL_JS))' >/dev/null 2>&1 \
	  && echo ">>> Bottom panel created (auto-hide, fit, 60px)" \
	  || echo ">>> WARNING: bottom panel not created (plasmashell down)"
