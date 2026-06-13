.PHONY: configure-panels

DOLPHIN_PREVIEW_OK := $(shell grep -c '^Show Preview=true' $(USER_HOME)/.config/kdeglobals 2>/dev/null)
GLOBALMENU_OK      := $(shell grep -c 'org.kde.plasma.appmenu' $(USER_HOME)/.config/plasma-org.kde.plasma.desktop-appletsrc 2>/dev/null)
KWIN_BORDERLESS_OK := $(shell grep -c '^BorderlessMaximizedWindows=true' $(USER_HOME)/.config/kwinrc 2>/dev/null)
DOCK_OK            := $(shell grep -B 10 'org.kde.plasma.icontasks' $(USER_HOME)/.config/plasma-org.kde.plasma.desktop-appletsrc 2>/dev/null | grep -c 'location=4')
SCREEN_W           := $(shell xrandr --current 2>/dev/null | awk '/*/{split($$1,a,"x"); print a[1]; exit}')
## Gate on the config value we actually care about, not on knowing the panel ID at parse time.
DOCK_CONFIGURED_OK := $(shell grep -c 'panelVisibility=1' $(USER_HOME)/.config/plasmashellrc 2>/dev/null)
APPDASH_OK         := $(shell grep -c 'org.kde.plasma.applicationdashboard' $(USER_HOME)/.config/plasma-org.kde.plasma.desktop-appletsrc 2>/dev/null)
LAUNCHER_OK        := $(shell grep -c 'org.kde.plasma.kickoff' $(USER_HOME)/.config/plasma-org.kde.plasma.desktop-appletsrc 2>/dev/null)
ALBERT_HOTKEY_OK   := $(shell grep -c '^hotkey=Alt+Space' $(USER_HOME)/.config/albert/albert.conf 2>/dev/null)
KRUNNER_CONFLICT   := $(shell grep -c 'Alt+Space' $(USER_HOME)/.config/kglobalshortcutsrc 2>/dev/null)
PLASMASHELL_RUNNING       := $(shell systemctl --user is-active plasma-plasmashell.service 2>/dev/null | grep -c '^active')
## Non-empty when this run will create/modify panels and needs one restart at the end.
PLASMASHELL_NEEDS_RESTART := $(or $(filter 0,$(GLOBALMENU_OK)),$(filter 0,$(DOCK_OK)),$(filter 0,$(DOCK_CONFIGURED_OK)),$(filter 0,$(APPDASH_OK)),$(filter 0,$(LAUNCHER_OK)))

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

## Bottom panel: app launcher + launchpad + task manager.
## JS creates the panel; kwriteconfig6 writes geometry/visibility to plasmashellrc post-creation.
define DOCK_PANEL_JS
  var d = new Panel;
  d.location = "bottom";
  d.addWidget("org.kde.plasma.kickoff");
  d.addWidget("org.kde.plasma.applicationdashboard");
  d.addWidget("org.kde.plasma.icontasks");
endef

define APPDASH_ADD_JS
  var all = panels();
  for (var i = 0; i < all.length; i++) {
    if (all[i].location == 4) { all[i].addWidget("org.kde.plasma.applicationdashboard"); break; }
  }
endef

define LAUNCHER_ADD_JS
  var all = panels();
  for (var i = 0; i < all.length; i++) {
    if (all[i].location == 4) { all[i].addWidget("org.kde.plasma.kickoff"); break; }
  }
endef

configure-panels:
ifeq ($(PLASMASHELL_RUNNING),0)
	systemctl --user reset-failed plasma-plasmashell.service 2>/dev/null || true
	systemctl --user start plasma-plasmashell.service
	@echo ">>> plasmashell started"
endif
ifeq ($(DOLPHIN_PREVIEW_OK),0)
	kwriteconfig5 --file kdeglobals --group "KFileDialog Settings" --key "Show Preview" true
	@echo ">>> Dolphin show preview enabled"
endif
ifeq ($(GLOBALMENU_OK),0)
	gdbus call --session --dest org.kde.plasmashell --object-path /PlasmaShell \
	  --method org.kde.PlasmaShell.evaluateScript '$(strip $(TOP_PANEL_JS))' >/dev/null
	@echo ">>> Top bar with global menu created"
endif
ifeq ($(KWIN_BORDERLESS_OK),0)
	kwriteconfig6 --file kwinrc --group Windows --key BorderlessMaximizedWindows true
	gdbus call --session --dest org.kde.KWin --object-path /KWin --method org.kde.KWin.reconfigure >/dev/null
	@echo ">>> Borderless maximized windows enabled"
endif
ifeq ($(DOCK_OK),0)
	gdbus call --session --dest org.kde.plasmashell --object-path /PlasmaShell \
	  --method org.kde.PlasmaShell.evaluateScript '$(strip $(DOCK_PANEL_JS))' >/dev/null
	@echo ">>> Bottom panel created"
endif
ifeq ($(DOCK_CONFIGURED_OK),0)
	@ID=$$(grep -B 3 'org.kde.plasma.icontasks' $(USER_HOME)/.config/plasma-org.kde.plasma.desktop-appletsrc 2>/dev/null | grep -oP '(?<=\[Containments\]\[)\d+' | tail -1); \
	 [ -n "$$ID" ] || { echo ">>> Dock not ready — run make again"; exit 0; }; \
	 kwriteconfig6 --file $(USER_HOME)/.config/plasmashellrc --group "PlasmaViews" --group "Panel $$ID" --key "floating" "0"; \
	 kwriteconfig6 --file $(USER_HOME)/.config/plasmashellrc --group "PlasmaViews" --group "Panel $$ID" --key "panelLengthMode" "1"; \
	 kwriteconfig6 --file $(USER_HOME)/.config/plasmashellrc --group "PlasmaViews" --group "Panel $$ID" --key "panelOpacity" "2"; \
	 kwriteconfig6 --file $(USER_HOME)/.config/plasmashellrc --group "PlasmaViews" --group "Panel $$ID" --key "panelVisibility" "1"; \
	 kwriteconfig6 --file $(USER_HOME)/.config/plasmashellrc --group "PlasmaViews" --group "Panel $$ID" --group "Defaults" --key "thickness" "60"; \
	 kwriteconfig6 --file $(USER_HOME)/.config/plasmashellrc --group "PlasmaViews" --group "Panel $$ID" --group "Horizontal$(SCREEN_W)" --key "alignment" "132"; \
	 echo ">>> Bottom panel configured (auto-hide, fit, 60px)"
endif
ifeq ($(APPDASH_OK),0)
ifneq ($(DOCK_OK),0)
	gdbus call --session --dest org.kde.plasmashell --object-path /PlasmaShell \
	  --method org.kde.PlasmaShell.evaluateScript '$(strip $(APPDASH_ADD_JS))' >/dev/null
	@echo ">>> Application Dashboard added to dock"
endif
endif
ifeq ($(LAUNCHER_OK),0)
ifneq ($(DOCK_OK),0)
	gdbus call --session --dest org.kde.plasmashell --object-path /PlasmaShell \
	  --method org.kde.PlasmaShell.evaluateScript '$(strip $(LAUNCHER_ADD_JS))' >/dev/null
	@echo ">>> Application Launcher added to dock"
endif
endif
ifneq ($(KRUNNER_CONFLICT),0)
	kwriteconfig6 --file $(USER_HOME)/.config/kglobalshortcutsrc --group "krunner.desktop" --key "_launch" "Alt+F2,,KRunner"
	@echo ">>> KRunner Alt+Space removed (Albert owns this shortcut)"
endif
ifeq ($(ALBERT_HOTKEY_OK),0)
	mkdir -p $(USER_HOME)/.config/albert
	kwriteconfig6 --file $(USER_HOME)/.config/albert/albert.conf --group General --key hotkey "Alt+Space"
	@echo ">>> Albert hotkey set to Alt+Space"
endif
ifneq ($(PLASMASHELL_NEEDS_RESTART),)
	systemctl --user reset-failed plasma-plasmashell.service 2>/dev/null || true
	systemctl --user restart plasma-plasmashell.service
	@echo ">>> plasmashell restarted — run make again to apply settings"
endif
