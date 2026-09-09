%% net/fritzbox-vpn — the LAN itself, from outside, when nothing on it is
%% up. The Fritz!Box 6670's own WireGuard server (FRITZ!OS ≥ 7.50) is a
%% channel independent of crucible: net/tailscale reaches the BMC only
%% through a live tailnet node on the LAN, this needs only the box. Cable
%% line (Tele Columbus), public IPv4 + IPv6; the MyFRITZ! name
%% 17v3uqu6p72vzio2.myfritz.net tracks the address (enabled 2026-09-05 —
%% the IPv4 had held six weeks, but it is DHCP, never hardcode it).
%%
%% The peer config holds a private key, so it lives OUTSIDE the tree at
%% ~/.config/wireguard/fritzbox.conf, exported once from the box UI
%% (Internet → Permit Access → VPN (WireGuard) → Connect a single device,
%% second factor by button). NetworkManager imports WireGuard natively —
%% Ubuntu ships no plugin package. autoconnect stays off: at home the
%% tunnel would route the LAN through the LAN. Bring it up by hand when
%% away (plasma-nm tray or nmcli connection up fritzbox); RemoteAccess
%% then reaches the BMC at 192.168.178.23 and the WoL broadcast unchanged.

binary_pkg('/usr/bin/wg', wireguard).

fritzbox_wg_conf(Path) :-
    user_home(Home),
    atom_concat(Home, '/.config/wireguard/fritzbox.conf', Path).

%% Import once; NetworkManager names the connection after the file.
user_config(fritzbox_wireguard, Check, Fix) :-
    fritzbox_wg_conf(Conf),
    exists_file(Conf),
    Check = "nmcli -t -f NAME connection show 2>/dev/null | grep -qx fritzbox",
    format(atom(Fix),
        "nmcli connection import type wireguard file ~w && nmcli connection modify fritzbox connection.autoconnect no",
        [Conf]).

user_config_deps(fritzbox_wireguard, [packages_installed]).

%% The export is a human step on the box (XXIV). Gated on the file only —
%% there is no machine-role gate in post.pl, so the rig sees this too.
advisory(user_config, fritzbox_wireguard,
    'no ~/.config/wireguard/fritzbox.conf — export the servalws peer from the Fritz!Box (Internet → Permit Access → VPN (WireGuard)), chmod 600, rerun') :-
    fritzbox_wg_conf(Conf),
    \+ exists_file(Conf).
