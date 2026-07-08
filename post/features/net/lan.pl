%% net/lan — serving and using the apartment LAN: Cockpit admin UI,
%% NetworkManager captive-portal probing, password-SSH only from the local
%% subnet, and the avahi-discovered HP printer.

binary_pkg('/usr/bin/cockpit-bridge', 'cockpit cockpit-files').

service_check(cockpit_socket,
    "systemctl is-enabled --quiet cockpit.socket",
    "systemctl enable --now cockpit.socket").
service_check(captive_portal,
    "test -f /etc/NetworkManager/conf.d/captive-portal.conf",
    "mkdir -p /etc/NetworkManager/conf.d && printf '[connectivity]\\nuri=http://nmcheck.gnome.org/check_network_status.txt\\nresponse=NetworkManager is online\\ninterval=60\\n' > /etc/NetworkManager/conf.d/captive-portal.conf && systemctl reload NetworkManager").
%% LAN subnet is resolved at apply time on the machine being fixed.
service_check(ssh_lan_password,
    "test -f /etc/ssh/sshd_config.d/lan-password.conf",
    "SUBNET=$(ip route | awk '/proto kernel/ && !/wl|ww|lo|vir|br-|docker/{print $1; exit}') && mkdir -p /etc/ssh/sshd_config.d && printf 'PasswordAuthentication no\\n\\nMatch Address %s,127.0.0.1\\n\\tPasswordAuthentication yes\\n' \"$SUBNET\" > /etc/ssh/sshd_config.d/lan-password.conf && (systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true)").
%% Printer: applicable when already configured (verify) or currently
%% discoverable on the LAN (configure) — otherwise skipped, not failed.
service_check(printer_lpadmin, Check, Fix) :-
    once(( shell_ok("lpstat -p hp-laserjet-mfp-2604sdw")
         ; shell_ok("avahi-browse -t -r -p _ipp._tcp 2>/dev/null | grep -q 2604sdw")
         )),
    Check = "lpstat -p hp-laserjet-mfp-2604sdw >/dev/null 2>&1",
    Fix = "IP=$(avahi-browse -t -r -p _ipp._tcp 2>/dev/null | awk -F';' '/^=/ && /2604sdw/{print $8; exit}') && test -n \"$IP\" && lpadmin -p hp-laserjet-mfp-2604sdw -E -v \"ipp://$IP/ipp/print\" -m everywhere && lpoptions -d hp-laserjet-mfp-2604sdw".
