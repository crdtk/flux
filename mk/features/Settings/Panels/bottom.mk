include mk/features/Settings/Panels/plasmashell.mk

## Bottom panel: app launcher + launchpad + task manager.
## All layout properties set via JS — no kwriteconfig6 Panel-ID lookups needed.
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

