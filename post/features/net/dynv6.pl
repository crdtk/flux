%% net/dynv6 — keep the public-IP zone concise.dynv6.net current.
%% Ported 2026-08-09 from the stale rig clone's uncommitted Makefile
%% (~/Desktop/Projects/Crucible, archived) — the machinery lived only
%% there, so the zone stopped updating when work moved to flux. Note:
%% crucible.dns.army is a DIFFERENT zone — a static A record pointing
%% at the rig's Tailscale IP; it needs tailscale up, not this updater.
%%
%% Three artifacts, single-level chain (dispatcher ← service ← timer):
%% a NetworkManager dispatcher script that refreshes the zone the
%% moment any interface comes up, a oneshot service that simply calls
%% that script (args "x up" satisfy its interface-up gate — one source
%% of truth for the update logic), and a 5-minute timer as fallback.
%% Gate: the per-machine token file — a host without it (the laptop)
%% skips, not fails. The token stays out of the repo (no-keyring
%% policy: secrets come from the invoking machine, never the tree).

service_check(dynv6_dispatcher, Check, Fix) :-
    user_home(Home),
    format(atom(TokenGate), "test -f ~w/.config/dynv6-token", [Home]),
    shell_ok(TokenGate),
    Check = "test -x /etc/NetworkManager/dispatcher.d/99-dynv6 && grep -q 'zone=concise.dynv6.net' /etc/NetworkManager/dispatcher.d/99-dynv6",
    format(atom(Fix),
        "printf '%s\\n' '#!/bin/sh' '# dynv6: refresh public-IP zone when an interface comes up' '[ \"$2\" = \"up\" ] || exit 0' 'TOKEN_FILE=~w/.config/dynv6-token' '[ -f \"$TOKEN_FILE\" ] || exit 0' 'IPV4=$(curl -fsS -4 https://api4.ipify.org) || exit 0' 'curl -fsS \"https://dynv6.com/api/update?zone=concise.dynv6.net&token=$(cat $TOKEN_FILE)&ipv4=$IPV4\"' > /etc/NetworkManager/dispatcher.d/99-dynv6 && chmod 755 /etc/NetworkManager/dispatcher.d/99-dynv6",
        [Home]).

service_check(dynv6_service, Check, Fix) :-
    user_home(Home),
    format(atom(TokenGate), "test -f ~w/.config/dynv6-token", [Home]),
    shell_ok(TokenGate),
    Check = "test -f /etc/systemd/system/dynv6-update.service",
    Fix = "printf '%s\\n' '[Unit]' 'Description=dynv6 IP update' 'After=network-online.target' 'Wants=network-online.target' '' '[Service]' 'Type=oneshot' 'ExecStart=/etc/NetworkManager/dispatcher.d/99-dynv6 x up' > /etc/systemd/system/dynv6-update.service".

service_check(dynv6_timer, Check, Fix) :-
    user_home(Home),
    format(atom(TokenGate), "test -f ~w/.config/dynv6-token", [Home]),
    shell_ok(TokenGate),
    Check = "systemctl is-enabled --quiet dynv6-update.timer",
    Fix = "printf '%s\\n' '[Unit]' 'Description=dynv6 IP update every 5 minutes' '' '[Timer]' 'OnBootSec=1min' 'OnUnitActiveSec=5min' '' '[Install]' 'WantedBy=timers.target' > /etc/systemd/system/dynv6-update.timer && systemctl daemon-reload && systemctl enable --now dynv6-update.timer".

service_deps(dynv6_service, [service_ready(dynv6_dispatcher)]).
service_deps(dynv6_timer,   [service_ready(dynv6_service)]).

%% The token cannot be provisioned — it is a human-only step (XXIV),
%% and 2026-08-09 it existed on NO machine: the historical dispatcher
%% has been exiting silently at its token gate the whole time, which
%% is how concise.dynv6.net went stale unnoticed.
advisory(services, dynv6_token,
    'no ~/.config/dynv6-token — dynv6 rules skip; put the dynv6 HTTP token there to activate the updater') :-
    user_home(Home),
    format(atom(Gate), "test -f ~w/.config/dynv6-token", [Home]),
    \+ shell_ok(Gate).
