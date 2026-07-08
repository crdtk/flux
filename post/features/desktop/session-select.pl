%% desktop/session-select — the display-manager redundancy strategy (see
%% memory: project-display-manager-gdm). ALL ranked candidates for the
%% display_manager and session domains live HERE — clause order is rank,
%% never split a domain across modules. GDM is primary (only DM proven to
%% launch X11, Wayland AND Lomiri sessions); installed alternates are held
%% standby-ready so switching is a greeter choice, not a repair.

candidate(display_manager, gdm).      % proven here: launches X11, Wayland AND Lomiri sessions
candidate(display_manager, sddm).     % Plasma-native, plain INI config — first standby
candidate(display_manager, lightdm).  % cannot launch Wayland sessions — last resort
candidate(session, plasmax11).        % global menu needs X11 (KWin Wayland lacks appmenu)
candidate(session, plasmawayland).
candidate(session, lomiri).           % experimental — demoted while crash evidence stands

%% viable(+Domain, +Option) — live probes, not assumptions.
%% (viable(session, lomiri) lives in desktop/lomiri.pl with its evidence.)
viable(display_manager, DM) :- dm_installed(DM).
viable(session, plasmax11) :-
    shell_ok("test -f /usr/share/xsessions/plasmax11.desktop").
viable(session, plasmawayland) :-
    shell_ok("test -f /usr/share/wayland-sessions/plasma.desktop").

dm_installed(gdm)     :- shell_ok("test -x /usr/sbin/gdm3").
dm_installed(sddm)    :- shell_ok("test -x /usr/bin/sddm").
dm_installed(lightdm) :- shell_ok("test -x /usr/sbin/lightdm").

%% The session file GDM/SDDM need to offer Plasma (X11) — POST's session fixes
%% assume it exists; this makes it restorable.
binary_pkg('/usr/share/xsessions/plasmax11.desktop', 'plasma-session-x11').

%% active_display_manager(-DM) — which greeter actually launches sessions.
%% /etc/X11/default-display-manager is authoritative on Debian/Ubuntu; if it
%% names nothing recognizable, fall back to the selector's choice.
active_display_manager(DM) :-
    member(DM, [gdm, sddm, lightdm]),
    format(atom(C), "grep -q ~w /etc/X11/default-display-manager 2>/dev/null", [DM]),
    shell_ok(C), !.
active_display_manager(DM) :- select(display_manager, DM).

%% dm_session_check(+DM, -CheckShell) / dm_session_fix(+DM, -FixCmd)
%% Is Plasma (X11) recorded as the default session where THIS display manager
%% actually reads it — and how to record it. GDM: AccountsService. SDDM:
%% /etc/sddm.conf.d + state.conf, with DisplayServer=x11 (the Wayland greeter
%% leaks WAYLAND_DISPLAY and KWin on Wayland lacks the appmenu protocol the
%% global menu needs). LightDM: conf.d user-session.
dm_session_check(gdm, Check) :-
    run_as_user(User),
    format(atom(Check),
        "busctl get-property org.freedesktop.Accounts /org/freedesktop/Accounts/User$(id -u ~w) org.freedesktop.Accounts.User Session | grep -q plasmax11",
        [User]).
dm_session_check(sddm,
    "grep -q 'Session=plasmax11' /etc/sddm.conf.d/20-kubuntu.conf 2>/dev/null && grep -q 'DisplayServer=x11' /etc/sddm.conf.d/30-x11-session.conf 2>/dev/null").
dm_session_check(lightdm,
    "grep -q 'user-session=plasmax11' /etc/lightdm/lightdm.conf.d/50-session.conf 2>/dev/null").

dm_session_fix(gdm, Cmd) :-
    run_as_user(User),
    format(atom(Cmd),
        "U=$(id -u ~w) && busctl call org.freedesktop.Accounts /org/freedesktop/Accounts/User$U org.freedesktop.Accounts.User SetSession s plasmax11 && busctl call org.freedesktop.Accounts /org/freedesktop/Accounts/User$U org.freedesktop.Accounts.User SetXSession s plasmax11",
        [User]).
dm_session_fix(sddm, Cmd) :-
    run_as_user(User),
    format(atom(Cmd),
        "mkdir -p /etc/sddm.conf.d /var/lib/sddm && rm -f /etc/sddm.conf.d/99-force-x11.conf && { test -f /etc/sddm.conf.d/20-kubuntu.conf && sed -i 's/^Session=plasma$/Session=plasmax11/' /etc/sddm.conf.d/20-kubuntu.conf || printf '[Autologin]\\nSession=plasmax11\\n' > /etc/sddm.conf.d/20-kubuntu.conf; } && printf '[General]\\nDisplayServer=x11\\n' > /etc/sddm.conf.d/30-x11-session.conf && printf '[Last]\\nUser=~w\\nSession=plasmax11.desktop\\n' > /var/lib/sddm/state.conf && chmod 600 /var/lib/sddm/state.conf && (chown sddm:sddm /var/lib/sddm/state.conf 2>/dev/null || true)",
        [User]).
dm_session_fix(lightdm,
    "mkdir -p /etc/lightdm/lightdm.conf.d && printf '[Seat:*]\\nuser-session=plasmax11\\n' > /etc/lightdm/lightdm.conf.d/50-session.conf").

%% saved_session_is_x11 — checked where the ACTIVE display manager reads it.
saved_session_is_x11 :-
    active_display_manager(DM),
    dm_session_check(DM, Check),
    shell_ok(Check).

%% session_rule(+Name, ?FixCmd) — FixCmd targets the active display manager.
session_rule(wayland_x11_mismatch, Cmd) :-
    active_display_manager(DM),
    dm_session_fix(DM, Cmd).

%% GDM's Wayland greeter leaks XDG_SESSION_TYPE=wayland and an empty
%% WAYLAND_DISPLAY into the login environment; apps launched via the
%% systemd/dbus activation environment (Plasma 6 launches everything that
%% way) then pick the Wayland backend inside an X11 session. This env
%% script, sourced by startplasma before the session settles, scrubs the
%% stale variables when the session is really X11.
config_patch(x11_env_scrub, '/usr/bin/startplasma-x11', Check, Fix) :-
    user_home(Home),
    % Not a bare sentinel: the script must exist AND, when the session is
    % genuinely X11, the live systemd activation environment must already
    % be clean (no WAYLAND_DISPLAY, XDG_SESSION_TYPE=x11) — apps launched
    % by Plasma inherit that environment, not the script's intent.
    format(atom(Check),
        "test -x ~w/.config/plasma-workspace/env/10-x11-scrub-wayland.sh && { ! pgrep -x startplasma-x11 >/dev/null || { systemctl --user show-environment 2>/dev/null | grep -qx XDG_SESSION_TYPE=x11 && ! systemctl --user show-environment 2>/dev/null | grep -q '^WAYLAND_DISPLAY='; }; }",
        [Home]),
    run_as_user(User),
    format(atom(Fix),
        "mkdir -p ~w/.config/plasma-workspace/env && printf '%s\\n' 'if [ -n \"$DISPLAY\" ] && [ -z \"$WAYLAND_DISPLAY\" ]; then' '    unset WAYLAND_DISPLAY' '    export XDG_SESSION_TYPE=x11' '    systemctl --user set-environment XDG_SESSION_TYPE=x11 2>/dev/null' '    systemctl --user unset-environment WAYLAND_DISPLAY 2>/dev/null' 'fi' > ~w/.config/plasma-workspace/env/10-x11-scrub-wayland.sh && chmod +x ~w/.config/plasma-workspace/env/10-x11-scrub-wayland.sh && chown -R ~w:~w ~w/.config/plasma-workspace && if pgrep -x startplasma-x11 >/dev/null; then sudo -u ~w XDG_RUNTIME_DIR=/run/user/$(id -u ~w) systemctl --user set-environment XDG_SESSION_TYPE=x11; sudo -u ~w XDG_RUNTIME_DIR=/run/user/$(id -u ~w) systemctl --user unset-environment WAYLAND_DISPLAY; fi",
        [Home, Home, Home, User, User, Home, User, User, User, User]).

user_config(xsessionrc, Check, Fix) :-
    user_home(Home),
    format(atom(Check),
        "grep -q 'import-environment DISPLAY' ~w/.xsessionrc 2>/dev/null", [Home]),
    format(atom(Fix),
        "printf '%s\\n' 'systemctl --user import-environment DISPLAY XAUTHORITY 2>/dev/null || true' > ~w/.xsessionrc",
        [Home]).
