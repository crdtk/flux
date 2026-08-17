%% desktop/session-select — the display-manager redundancy strategy (see
%% memory: project-display-manager-gdm). ALL ranked candidates for the
%% display_manager and session domains live HERE — clause order is rank,
%% never split a domain across modules. GDM is primary (only DM proven to
%% launch X11, Wayland AND Lomiri sessions); installed alternates are held
%% standby-ready so switching is a greeter choice, not a repair.

%% Unified 2026-08-16: SDDM everywhere, Lomiri over. GDM's only unique
%% capability was launching Lomiri sessions; with that experiment closed
%% the machines unify on the Plasma-native DM. On the rig this was forced
%% first (GDM's Wayland greeter renders on the GPU head and VT-switches
%% SDDM's X away, blacking the iKVM — fought 2026-08-16); the laptop
%% followed by decision. GDM is purged wherever it is NOT the active
%% greeter — the gate keeps POST from purging a DM mid-session (the
%% 2026-08-10 scar): on a machine still seated on GDM the rule waits
%% for the reboot that hands the seat to SDDM.
candidate(display_manager, sddm).     % Plasma-native, unified primary
candidate(display_manager, lightdm).  % X11-only standby (cannot launch Wayland sessions)
hardening_check(no_gdm,
    "! dpkg -l gdm3 2>/dev/null | grep -q '^ii'",
    "apt-get purge -y gdm3") :-
    \+ shell_ok("systemctl is-active --quiet gdm3 2>/dev/null || systemctl is-active --quiet gdm 2>/dev/null").
advisory(hardening, gdm_seat_handoff,
    'GDM still holds the seat — log out and reboot so SDDM takes over; no_gdm purges gdm3 on the next pass') :-
    shell_ok("systemctl is-active --quiet gdm3 2>/dev/null || systemctl is-active --quiet gdm 2>/dev/null").
candidate(session, plasmax11).        % global menu needs X11 (KWin Wayland lacks appmenu)
candidate(session, plasmawayland).

%% viable(+Domain, +Option) — live probes, not assumptions.
%% (lomiri.pl deleted 2026-08-16 — experiment closed, module revoked whole.)
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

%% X must come up by itself: the selector's first viable DM is recorded in
%% /etc/X11/default-display-manager (Debian DMs refuse to start when it
%% names another or nothing — lost in the 2026-08-10 purge incident, which
%% left graphical.target defaulted but no greeter willing to claim it),
%% enabled, and running. `start`, never restart: a live session must not
%% be bounced by a POST pass (start is a no-op while active).
dm_binary(gdm, '/usr/sbin/gdm3').
dm_binary(sddm, '/usr/bin/sddm').
dm_binary(lightdm, '/usr/sbin/lightdm').
dm_service(gdm, gdm3).
dm_service(sddm, sddm).
dm_service(lightdm, lightdm).
%% SEAT GATE (2026-08-17 scar): `start` is a no-op only for the SAME
%% service — starting the ranked DM while a DIFFERENT one holds the live
%% seat steals the VT and terminates the running session (it killed the
%% laptop's Plasma-under-GDM session mid-`make | sudo bash`). So the fix
%% records + enables unconditionally (inert until boot) but starts only
%% when no rival DM is active; and a pending handoff COUNTS as converged
%% — the reboot is the human step the gdm_seat_handoff advisory names,
%% not a failure to nag every run.
other_dm_active_shell(Svc, Shell) :-
    findall(S, (dm_service(_, S), S \= Svc), Others),
    atomic_list_concat(Others, ' || systemctl is-active --quiet ', Inner),
    format(atom(Shell), "systemctl is-active --quiet ~w", [Inner]).
hardening_check(display_manager_boots, Check, Fix) :-
    select(display_manager, DM),
    dm_binary(DM, Bin),
    dm_service(DM, Svc),
    other_dm_active_shell(Svc, Rival),
    format(atom(Check),
        "grep -q ~w /etc/X11/default-display-manager 2>/dev/null && systemctl is-enabled --quiet ~w 2>/dev/null && { systemctl is-active --quiet ~w || ~w; }",
        [Bin, Svc, Svc, Rival]),
    format(atom(Fix),
        "echo ~w > /etc/X11/default-display-manager && systemctl set-default graphical.target && systemctl enable ~w 2>/dev/null; if ~w; then echo '>>> DM handoff deferred: a rival display manager holds the live seat - reboot to switch'; else systemctl start ~w; fi",
        [Bin, Svc, Rival, Svc]).

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

%% After the seat lands with the ranked DM, a rival gdm3 unit can linger
%% active, respawning a greeter that fights for the VT and — worse —
%% gate-blocking its own purge forever (seen 2026-08-17: gdm3 + sddm both
%% active after the collision). Stop it, but only when provably safe:
%% the ranked DM is active AND no user-class session is served by GDM
%% (a greeter session is GDM's own furniture, killable; a user session
%% never is — the 2026-08-10 scar).
hardening_check(no_rival_gdm_unit, Check, Fix) :-
    select(display_manager, DM),
    DM \= gdm,
    dm_service(DM, Svc),
    Check = "! systemctl is-active --quiet gdm3 && ! systemctl is-active --quiet gdm",
    format(atom(Fix),
        "if systemctl is-active --quiet ~w && ! ( for s in $(loginctl list-sessions --no-legend | awk '{print $1}'); do loginctl show-session $s -p Class | grep -q Class=user && loginctl show-session $s -p Service | grep -q gdm && exit 0; done; exit 1 ); then systemctl stop gdm3 2>/dev/null; systemctl stop gdm 2>/dev/null; true; else echo '>>> rival gdm stop deferred: it still serves a user session - reboot instead'; fi",
        [Svc]).
