%% desktop/panels — the screen-space strategy: top bar with GLOBAL MENU on
%% EVERY screen, titlebar widget replacing window decorations (kwin
%% borderless), auto-hide dock, per-output kscreen autostarts. Destructive
%% panel operations (make reset-panels / backup-plasma) stay in
%% mk/features/Settings/Panels.
%%
%% Multi-screen: Panel.screen is writable in the Plasma 6 scripting API, and
%% screenCount/panels() enumerate live state — check and fix both run inside
%% plasmashell via evaluateScript, so drift (a new monitor without a top bar)
%% is detected against reality, not against appletsrc parsing. Panels whose
%% screen disappears stay dormant in appletsrc and come back with the screen;
%% removing them is destructive and stays in make reset-panels.
%%
%% Top: kppleMenu | title widget | GLOBAL MENU (appmenu) | spacer |
%% weather (DWD Berlin-Alexanderplatz) | tray | Flex Hub | clock. The JS is
%% single-quote-free by construction — the gdbus call wraps it in single
%% quotes. Bottom: auto-hide dock (kickoff + dashboard + icontasks).
%% Weather placeInfo format is place_name|station_id (ion_dwd.cpp): the name
%% is display-only, the id (10389, DWD MOSMIX) drives the API. The tray must
%% never host weather: its hidden auto-instance segfaults plasmashell on exit
%% (upstream 6.6.5) — knownItems pre-seeds weather as known-but-disabled.
%% Enum formats differ per widget: antroids stores ints, digitalclock names.

binary_pkg('/usr/share/plasma/plasmoids/org.kde.plasma.kickerdash/metadata.json',
                                     'plasma-widgets-addons').
binary_pkg('/usr/lib/x86_64-linux-gnu/gtk-3.0/modules/libappmenu-gtk-module.so',
                                     'appmenu-gtk3-module').
binary_pkg('/usr/libexec/vala-panel/appmenu-registrar',
                                     'appmenu-registrar').

%% KDE Store widgets — repo and package subdir, keyed by plugin id.
kde_widget('com.github.antroids.application-title-bar',
           'https://github.com/antroids/application-title-bar', package).
kde_widget('Plasma.Flex.Hub',
           'https://github.com/zayronxio/Plasma.Flex.Hub', '.').
kde_widget('com.github.chrtall.kppleMenu',
           'https://github.com/ChrTall/kppleMenu', package).
user_config(widget(Id), Check, Fix) :-
    kde_widget(Id, Repo, Sub),
    user_home(Home),
    format(atom(Check),
        "test -f ~w/.local/share/plasma/plasmoids/~w/metadata.json", [Home, Id]),
    format(atom(Fix),
        "rm -rf '/tmp/~w' && git clone --depth 1 ~w '/tmp/~w' && kpackagetool6 -t Plasma/Applet -i '/tmp/~w/~w'; rm -rf '/tmp/~w'",
        [Id, Repo, Id, Id, Sub, Id]).

top_panel_js(JS) :-
    atomic_list_concat([
        'function mkTop(s) {',
        'var p = new Panel;',
        'p.location = "top";',
        'p.screen = s;',
        'p.addWidget("com.github.chrtall.kppleMenu");',
        'var t = p.addWidget("com.github.antroids.application-title-bar");',
        't.currentConfigGroup = ["Appearance"];',
        't.writeConfig("widgetElements", ["windowTitle"]);',
        't.writeConfig("overrideElementsMaximized", true);',
        't.writeConfig("widgetElementsMaximized", ["windowCloseButton", "windowMinimizeButton", "windowMaximizeButton", "windowTitle"]);',
        't.writeConfig("windowTitleSource", 0);',
        't.writeConfig("windowTitleSourceMaximized", 0);',
        't.writeConfig("windowTitleFontSize", 10);',
        't.writeConfig("windowTitleUndefined", "Plasma");',
        'p.addWidget("org.kde.plasma.appmenu");',
        'p.addWidget("org.kde.plasma.panelspacer");',
        'var w = p.addWidget("org.kde.plasma.weather");',
        'w.currentConfigGroup = ["WeatherStation"];',
        'w.writeConfig("provider", "dwd");',
        'w.writeConfig("placeInfo", "Berlin-Alex.|10389");',
        'w.writeConfig("placeDisplayName", "Berlin-Alex.");',
        'w.currentConfigGroup = ["Appearance"];',
        'w.writeConfig("showTemperatureInCompactMode", true);',
        'var s = p.addWidget("org.kde.plasma.systemtray");',
        's.currentConfigGroup = ["General"];',
        's.writeConfig("extraItems", "");',
        's.writeConfig("knownItems", ["org.kde.plasma.weather"]);',
        'p.addWidget("Plasma.Flex.Hub");',
        'var c = p.addWidget("org.kde.plasma.digitalclock");',
        'c.currentConfigGroup = ["Appearance"];',
        'c.writeConfig("dateDisplayFormat", "BesideTime");',
        'c.writeConfig("use24hFormat", 2);',
        'c.writeConfig("autoFontAndSize", false);',
        'c.writeConfig("fontSize", 14);',
        'c.writeConfig("dateFormat", "custom");',
        'c.writeConfig("customDateFormat", "dd.MM.yy |");',
        '}',
        'var have = panels().filter(function(q) { return q.location == "top"; }).map(function(q) { return q.screen; });',
        'for (var i = 0; i < screenCount; i++) { if (have.indexOf(i) < 0) { mkTop(i); } }'
    ], ' ', JS).

top_panel_check_js(JS) :-
    atomic_list_concat([
        'var have = panels().filter(function(q) { return q.location == "top"; }).map(function(q) { return q.screen; });',
        'var m = 0;',
        'for (var i = 0; i < screenCount; i++) { if (have.indexOf(i) < 0) { m += 1; } }',
        'print(m == 0 ? "OK" : "MISSING" + m);'
    ], ' ', JS).
bottom_panel_js(JS) :-
    atomic_list_concat([
        'var d = new Panel;',
        'd.location = "bottom";',
        'd.height = 60;',
        'd.hiding = "autohide";',
        'd.lengthMode = "fit";',
        'd.floating = false;',
        'd.opacity = "opaque";',
        'd.addWidget("org.kde.plasma.kickoff");',
        'd.addWidget("org.kde.plasma.applicationdashboard");',
        'd.addWidget("org.kde.plasma.icontasks");'
    ], ' ', JS).

%% Panels restore from appletsrc via KConfig watchers, so a dead or failed
%% plasmashell makes every panel fix a silent no-op — recover it first.
user_config(plasmashell_active,
    "systemctl --user is-active plasma-plasmashell.service >/dev/null 2>&1 || ! systemctl --user list-unit-files plasma-plasmashell.service --no-legend 2>/dev/null | grep -q .",
    "systemctl --user reset-failed plasma-plasmashell.service 2>/dev/null; systemctl --user start plasma-plasmashell.service && until systemctl --user is-active plasma-plasmashell.service >/dev/null 2>&1; do sleep 1; done").
user_config(top_panel, Check, Fix) :-
    top_panel_check_js(CheckJS),
    format(atom(Check),
        "gdbus call --session --dest org.kde.plasmashell --object-path /PlasmaShell --method org.kde.PlasmaShell.evaluateScript '~w' 2>/dev/null | grep -q OK",
        [CheckJS]),
    top_panel_js(JS),
    format(atom(Fix),
        "gdbus call --session --dest org.kde.plasmashell --object-path /PlasmaShell --method org.kde.PlasmaShell.evaluateScript '~w' >/dev/null",
        [JS]).
user_config(bottom_panel, Check, Fix) :-
    user_home(Home),
    format(atom(Check),
        "grep -q 'location=4' ~w/.config/plasma-org.kde.plasma.desktop-appletsrc 2>/dev/null",
        [Home]),
    bottom_panel_js(JS),
    format(atom(Fix),
        "gdbus call --session --dest org.kde.plasmashell --object-path /PlasmaShell --method org.kde.PlasmaShell.evaluateScript '~w' >/dev/null",
        [JS]).

%% Screen-space: maximized windows lose their titlebar (the top panel's
%% application-title-bar widget takes over its role).
user_config(kwin_borderless, Check,
    "kwriteconfig6 --file kwinrc --group Windows --key BorderlessMaximizedWindows true && (gdbus call --session --dest org.kde.KWin --object-path /KWin --method org.kde.KWin.reconfigure >/dev/null 2>&1 || true)") :-
    user_home(Home),
    format(atom(Check),
        "grep -q '^BorderlessMaximizedWindows=true' ~w/.config/kwinrc 2>/dev/null", [Home]).

%% One autostart entry per connected output (kscreen-doctor enable only —
%% KScreen keeps the arrangement). Snapshot-free: the loop re-derives the
%% output list at apply time.
user_config(kscreen_autostart, Check, Fix) :-
    user_home(Home),
    format(atom(Check),
        "kscreen-doctor --json 2>/dev/null | jq -r '.outputs[] | select(.connected) | .name' | { while read -r o; do test -f ~w/.config/autostart/enable-$o.desktop || exit 1; done; }",
        [Home]),
    format(atom(Fix),
        "mkdir -p ~w/.config/autostart && kscreen-doctor --json 2>/dev/null | jq -r '.outputs[] | select(.connected) | .name' | while read -r o; do printf '[Desktop Entry]\\nType=Application\\nName=Enable monitor %s\\nExec=kscreen-doctor output.%s.enable\\nOnlyShowIn=KDE;\\n' \"$o\" \"$o\" > ~w/.config/autostart/enable-$o.desktop; kscreen-doctor output.$o.enable >/dev/null 2>&1 || true; done",
        [Home, Home]).

user_config_deps(top_panel,
    [user_config_applied(widget('com.github.antroids.application-title-bar')),
     user_config_applied(widget('Plasma.Flex.Hub')),
     user_config_applied(widget('com.github.chrtall.kppleMenu')),
     user_config_applied(plasmashell_active),
     packages_installed]).
user_config_deps(bottom_panel,
    [user_config_applied(plasmashell_active), packages_installed]).
