%% platform/bmc — IPMI policy tied to the board: enable where a BMC
%% exists (the E3C256D4I-2T), mask where none does (this laptop).
%% dmidecode needs root; the /sys probe works for any user once ipmi_si
%% has auto-loaded from SMBIOS, so unprivileged runs still see a live BMC.

has_bmc :- shell_ok("ls /sys/class/ipmi/ipmi* 2>/dev/null | grep -q ipmi"), !.
has_bmc :- shell_ok("dmidecode -t 38 2>/dev/null | grep -q 'IPMI Device Information'").

hardening_check(openipmi_policy, Check, Fix) :-
    ( has_bmc
    ->  Check = "systemctl is-enabled --quiet openipmi 2>/dev/null",
        Fix   = "apt install -y openipmi && systemctl enable --now openipmi"
    ;   Check = "test -L /etc/systemd/system/openipmi.service",
        Fix   = "systemctl mask openipmi; apt-get purge -y openipmi 2>/dev/null || true"
    ).

%% Wake-on-LAN: password-free out-of-band power-on. Only meaningful on
%% the BMC machine (the rig is the thing that gets powered off remotely);
%% NetworkManager's wake-on-lan property survives reboots and re-arms the
%% NIC on every activation — a bare `ethtool -s ... wol g` dies with the
%% link. Applies to whichever wired connection currently carries the
%% default route (sensed, never named). Laptop side: `make rig-wake`.
hardening_check(wol_magic_packet, Check, Fix) :-
    has_bmc,
    Check = "nmcli -g 802-3-ethernet.wake-on-lan connection show \"$(nmcli -g GENERAL.CONNECTION device show $(ip -o route get 1.1.1.1 | sed 's/.* dev \\([^ ]*\\).*/\\1/') )\" 2>/dev/null | grep -q magic",
    Fix   = "nmcli connection modify \"$(nmcli -g GENERAL.CONNECTION device show $(ip -o route get 1.1.1.1 | sed 's/.* dev \\([^ ]*\\).*/\\1/') )\" 802-3-ethernet.wake-on-lan magic".
