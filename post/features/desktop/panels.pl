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
%% net speed | tray | clock | kup | clipboard | kscreen | cpu | kdeconnect |
%% net | notifications | print | battery | weather (DWD) | brightness. The JS
%% lives beside this file in panels/*.js and reaches plasmashell as
%% "$(cat …)" — it must contain no $ or backtick (bash expands those
%% inside double quotes). Bottom: auto-hide dock (kickoff + dashboard +
%% icontasks).
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
%% (Plasma.Flex.Hub dropped 2026-08-16: its QML broke on Plasma 6.6 —
%% NightLightControl is a private API it borrowed. Every feature it
%% bundled is stock: volume/brightness/media/network live in the tray
%% extraItems, net speed is a systemmonitor widget. No store widget may
%% hold a CONTROL function; store widgets are cosmetic-only here.)
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

%% The Plasma scripts are files beside this module (panels/*.js): real
%% line breaks, diffable, no quoting layer. They are read at APPLY time,
%% so the plan carries a path, not two kilobytes of quoted JS — `make`
%% stays readable in a terminal and identical in a pipe.
panel_script(File, Path) :-
    project_dir(Root),
    format(atom(Path), '~w/post/features/desktop/panels/~w', [Root, File]).

%% Panels restore from appletsrc via KConfig watchers, so a dead or failed
%% plasmashell makes every panel fix a silent no-op — recover it first.
%% Applicable only inside a live graphical session (a running kwin): from a
%% TTY or headless apply, starting plasmashell just dumps core against the
%% missing display and fails the whole apply — the panel chain must be
%% deferred (blocked deps), not crash-looped. Seen on crucible 2026-07-11.
user_config(plasmashell_active, Check, Fix) :-
    shell_ok("pgrep -x kwin_wayland >/dev/null || pgrep -x kwin_x11 >/dev/null"),
    Check = "systemctl --user is-active plasma-plasmashell.service >/dev/null 2>&1 || ! systemctl --user list-unit-files plasma-plasmashell.service --no-legend 2>/dev/null | grep -q .",
    %% pkill first: a plasmashell running OUTSIDE its unit (rogue from a crash
    %% recovery) makes the unit start collide and fail — and the wait must be
    %% BOUNDED, or a failed start spins `until` forever and hangs the whole
    %% `make | sudo bash` pipe (seen on crucible 2026-07-11).
    Fix = "pkill -x plasmashell 2>/dev/null; sleep 1; systemctl --user reset-failed plasma-plasmashell.service 2>/dev/null; systemctl --user start plasma-plasmashell.service; for i in $(seq 20); do systemctl --user is-active plasma-plasmashell.service >/dev/null 2>&1 && break; sleep 1; done; systemctl --user is-active plasma-plasmashell.service".
advisory(user_config, plasmashell_active,
         'no graphical session — panel configuration deferred to next desktop login') :-
    \+ shell_ok("pgrep -x kwin_wayland >/dev/null || pgrep -x kwin_x11 >/dev/null").
%% Panels are gated on the same compositor probe as plasmashell_active (XXIII):
%% without a session the rules must be ABSENT, not failing — a failing panel
%% check whose dependency has no rule marks the goal unachievable and the
%% planner then blocks the WHOLE plan, holding every unrelated ready fix
%% hostage. The advisory above already tells the human it is deferred.
user_config(top_panel, Check, Fix) :-
    shell_ok("pgrep -x kwin_wayland >/dev/null || pgrep -x kwin_x11 >/dev/null"),
    panel_script('top-check.js', CheckJS),
    format(atom(Check),
        "gdbus call --session --dest org.kde.plasmashell --object-path /PlasmaShell --method org.kde.PlasmaShell.evaluateScript \"$(cat ~w)\" 2>/dev/null | grep -q OK",
        [CheckJS]),
    panel_script('top.js', JS),
    format(atom(Fix),
        "gdbus call --session --dest org.kde.plasmashell --object-path /PlasmaShell --method org.kde.PlasmaShell.evaluateScript \"$(cat ~w)\" >/dev/null",
        [JS]).
user_config(bottom_panel, Check, Fix) :-
    shell_ok("pgrep -x kwin_wayland >/dev/null || pgrep -x kwin_x11 >/dev/null"),
    user_home(Home),
    format(atom(Check),
        "grep -q 'location=4' ~w/.config/plasma-org.kde.plasma.desktop-appletsrc 2>/dev/null",
        [Home]),
    panel_script('bottom.js', JS),
    format(atom(Fix),
        "gdbus call --session --dest org.kde.plasmashell --object-path /PlasmaShell --method org.kde.PlasmaShell.evaluateScript \"$(cat ~w)\" >/dev/null",
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
     user_config_applied(widget('com.github.chrtall.kppleMenu')),
     user_config_applied(plasmashell_active),
     packages_installed]).
user_config_deps(bottom_panel,
    [user_config_applied(plasmashell_active), packages_installed]).
