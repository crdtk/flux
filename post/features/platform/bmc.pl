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
