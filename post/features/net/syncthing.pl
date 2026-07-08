%% net/syncthing — file sync between the fleet, with the web GUI reachable
%% from the LAN. Password comes from SYNCTHING_GUI_PASS at apply time
%% (default change-me).

binary_pkg('/usr/bin/syncthing', syncthing).

service_check(syncthing_service, Check, Fix) :-
    run_as_user(User), user_home(Home),
    format(atom(Check),
        "test -e ~w/.config/systemd/user/default.target.wants/syncthing.service && test -e /var/lib/systemd/linger/~w",
        [Home, User]),
    format(atom(Fix),
        "loginctl enable-linger ~w && runuser -u ~w -- env XDG_RUNTIME_DIR=/run/user/$(id -u ~w) systemctl --user enable --now syncthing",
        [User, User, User]).
%% GUI remote access: bind Syncthing's web UI to 0.0.0.0 with auth.
service_check(syncthing_gui_remote, Check, Fix) :-
    run_as_user(User), user_home(Home),
    format(atom(Check),
        "grep -hq '0\\.0\\.0\\.0:8384' '~w/.config/syncthing/config.xml' '~w/.local/state/syncthing/config.xml' 2>/dev/null",
        [Home, Home]),
    format(atom(Fix),
        "KEY=$(grep -h '<apikey>' '~w/.config/syncthing/config.xml' '~w/.local/state/syncthing/config.xml' 2>/dev/null | sed -n 's:.*<apikey>\\(.*\\)</apikey>.*:\\1:p' | head -1) && for i in $(seq 30); do curl -sf http://localhost:8384/rest/noauth/health >/dev/null 2>&1 && break || sleep 1; done && curl -sS -X PATCH http://localhost:8384/rest/config/gui -H \"X-API-Key: $KEY\" -H 'Content-Type: application/json' -d '{\"address\":\"0.0.0.0:8384\",\"user\":\"~w\",\"password\":\"'\"${SYNCTHING_GUI_PASS:-change-me}\"'\"}'",
        [Home, Home, User]).

service_deps(syncthing_gui_remote, [service_ready(syncthing_service)]).
