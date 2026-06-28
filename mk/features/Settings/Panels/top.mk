include mk/features/Settings/Panels/plasmashell.mk

## Title widget: text-only normally; close/min/max appear far-left only when
## maximized — the one state borderless windows lack their own buttons (Unity).
## AppName source, 10pt = default panel font: one continuous text band, no icons.
## Clock: far right, date | time on one line, 24h, manual 14pt. The | is an
## unquoted Qt format literal — the JS must stay single-quote-free, since the
## recipe wraps $(strip TOP_PANEL_JS) in shell single quotes.
## Weather: stock org.kde.plasma.weather (plasma-widgets-addons), provider dwd,
## station Berlin-Alexanderplatz (10389, DWD MOSMIX catalogue), temp shown in
## panel. placeInfo format is place_name|station_id (ion_dwd.cpp fetchForecast);
## the name is display-only, the id drives the API. Flex Hub stays factory-default.
## Tray must never host weather: its hidden auto-instance segfaults plasmashell on
## exit (upstream 6.6.5). knownItems pre-seeds weather as known-but-disabled;
## emptied extraItems is repopulated by tray auto-add on the post-script restart.
## Enum formats differ per widget: antroids stores ints, digitalclock stores names.
define TOP_PANEL_JS
  var p = new Panel;
  p.location = "top";
  p.addWidget("com.github.chrtall.kppleMenu");
  var t = p.addWidget("com.github.antroids.application-title-bar");
  t.currentConfigGroup = ["Appearance"];
  t.writeConfig("widgetElements", ["windowTitle"]);
  t.writeConfig("overrideElementsMaximized", true);
  t.writeConfig("widgetElementsMaximized", ["windowCloseButton", "windowMinimizeButton", "windowMaximizeButton", "windowTitle"]);
  t.writeConfig("windowTitleSource", 0);
  t.writeConfig("windowTitleSourceMaximized", 0);
  t.writeConfig("windowTitleFontSize", 10);
  t.writeConfig("windowTitleUndefined", "Plasma");
  p.addWidget("org.kde.plasma.appmenu");
  p.addWidget("org.kde.plasma.panelspacer");
  var w = p.addWidget("org.kde.plasma.weather");
  w.currentConfigGroup = ["WeatherStation"];
  w.writeConfig("provider", "dwd");
  w.writeConfig("placeInfo", "Berlin-Alex.|10389");
  w.writeConfig("placeDisplayName", "Berlin-Alex.");
  w.currentConfigGroup = ["Appearance"];
  w.writeConfig("showTemperatureInCompactMode", true);
  var s = p.addWidget("org.kde.plasma.systemtray");
  s.currentConfigGroup = ["General"];
  s.writeConfig("extraItems", "");
  s.writeConfig("knownItems", ["org.kde.plasma.weather"]);
  p.addWidget("Plasma.Flex.Hub");
  var c = p.addWidget("org.kde.plasma.digitalclock");
  c.currentConfigGroup = ["Appearance"];
  c.writeConfig("dateDisplayFormat", "BesideTime");
  c.writeConfig("use24hFormat", 2);
  c.writeConfig("autoFontAndSize", false);
  c.writeConfig("fontSize", 14);
  c.writeConfig("dateFormat", "custom");
  c.writeConfig("customDateFormat", "dd.MM.yy |");
endef

.PHONY: configure-top-panel .remove-top-panels

.remove-top-panels:
	@gdbus call --session --dest org.kde.plasmashell --object-path /PlasmaShell \
	  --method org.kde.PlasmaShell.evaluateScript \
	  'var all=panels();for(var i=0;i<all.length;i++){if(all[i].location==3){all[i].remove();}}' >/dev/null 2>&1 || true

configure-top-panel: reset-panels
	@gdbus call --session --dest org.kde.plasmashell --object-path /PlasmaShell \
	  --method org.kde.PlasmaShell.evaluateScript '$(strip $(TOP_PANEL_JS))' >/dev/null 2>&1 \
	  && echo ">>> Top panel created" \
	  || echo ">>> WARNING: top panel not created (plasmashell down)"
