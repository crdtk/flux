%% net/syncthing — the fleet's file plane and the backup. Devices, folders,
%% versioning and the user unit are Home Manager's (nixos/home/home.nix,
%% services.syncthing, phase 1). POST keeps what HM cannot own on Ubuntu —
%% root state: linger, so the user unit runs without a login — and what
%% must never be in the tree — the GUI password, from SYNCTHING_GUI_PASS
%% at apply time (default change-me) — and SAYS where the human steps and
%% the backup stand.

%% The apt package stays for now: HM's unit runs the nixpkgs binary, the
%% archive one is the CLI on PATH for shells that predate the profile.
binary_pkg('/usr/bin/syncthing', syncthing).

service_check(syncthing_linger, Check, Fix) :-
    run_as_user(User),
    format(atom(Check), "test -e /var/lib/systemd/linger/~w", [User]),
    format(atom(Fix),   "loginctl enable-linger ~w", [User]).

%% GUI auth: address is declared (HM), the password is not — patched in
%% place, never written to the tree.
service_check(syncthing_gui_remote, Check, Fix) :-
    run_as_user(User), user_home(Home),
    format(atom(Check),
        "grep -hq '<user>~w</user>' '~w/.local/state/syncthing/config.xml' 2>/dev/null",
        [User, Home]),
    format(atom(Fix),
        "KEY=$(grep -h '<apikey>' '~w/.local/state/syncthing/config.xml' 2>/dev/null | sed -n 's:.*<apikey>\\(.*\\)</apikey>.*:\\1:p' | head -1) && for i in $(seq 30); do curl -sf http://localhost:8384/rest/noauth/health >/dev/null 2>&1 && break || sleep 1; done && curl -sS -X PATCH http://localhost:8384/rest/config/gui -H \"X-API-Key: $KEY\" -H 'Content-Type: application/json' -d '{\"user\":\"~w\",\"password\":\"'\"${SYNCTHING_GUI_PASS:-change-me}\"'\"}'",
        [Home, User]).

service_deps(syncthing_gui_remote, [service_ready(syncthing_linger)]).

%% ── What is in place, and the human steps (XXIV) ─────────────────────────

%% The phone offers a folder under an id of its own: the declared folder
%% (xcover-dcim) binds only when the phone uses that id.
advisory(services, syncthing_phone_folder,
    'the phone is offering a folder — on the phone set its Folder ID to xcover-dcim (shared with servalws and crucible), then the declared folder binds') :-
    user_home(Home),
    format(atom(Cmd),
        "KEY=$(sed -n 's:.*<apikey>\\(.*\\)</apikey>.*:\\1:p' '~w/.local/state/syncthing/config.xml' 2>/dev/null | head -1) && curl -sf -H \"X-API-Key: $KEY\" http://localhost:8384/rest/cluster/pending/folders 2>/dev/null | grep -q ':'",
        [Home]),
    shell_ok(Cmd).

%% A backup machine that is off is no backup — seen from a sender.
advisory(services, syncthing_backup_offline,
    'crucible (the backup) is offline on the tailnet — nothing is being versioned until it is on (make rig-wake / rig-on)') :-
    \+ shell_ok("test \"$(hostname)\" = crucible"),
    shell_ok("tailscale status 2>/dev/null | grep -qw crucible"),
    shell_ok("tailscale status 2>/dev/null | grep -w crucible | grep -q offline").

%% On the rig: the drive out means the receive-only folders are paused.
advisory(services, syncthing_backup_drive,
    'backup drive not mounted at /mnt/backup — the receive-only folders are paused until it is plugged in') :-
    shell_ok("test \"$(hostname)\" = crucible"),
    \+ shell_ok("mountpoint -q /mnt/backup").
