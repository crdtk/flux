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
%% sshd must actually speak. TCP-accept without an SSH banner is the
%% socket-activation failure mode: ssh.socket accepts the connection, the
%% spawned sshd dies (bad config, missing host keys), and remote clients
%% hang at "banner exchange" — invisible to is-active checks and to port
%% scans, which both look fine. Probe the banner itself on loopback.
%% Recovery: regenerate any missing host keys, validate config (a broken
%% drop-in aborts here and surfaces the offending line), then restart the
%% socket or service, whichever this host uses. Applicable only where an
%% sshd is installed — absent openssh-server is a skip, not a failure.
service_check(sshd_answers, Check, Fix) :-
    shell_ok("test -x /usr/sbin/sshd"),
    Check = "timeout 5 bash -c 'exec 3<>/dev/tcp/127.0.0.1/22 && read -r b <&3 && case \"$b\" in SSH-*) exit 0;; *) exit 1;; esac'",
    Fix = "ssh-keygen -A && sshd -t && { systemctl reset-failed 'ssh*' 2>/dev/null || true; if systemctl is-enabled --quiet ssh.socket; then systemctl restart ssh.socket; else systemctl restart ssh 2>/dev/null || systemctl restart sshd; fi; }".
%% LAN subnet is resolved at apply time on the machine being fixed. The
%% check demands a real subnet in the Match line, not mere file presence:
%% an empty $SUBNET once wrote "Match Address ,127.0.0.1", which sshd
%% rejects at parse time — killing every connection at banner exchange
%% (see sshd_answers below). The fix now refuses to write without one.
service_check(ssh_lan_password,
    "grep -q '^Match Address [0-9]' /etc/ssh/sshd_config.d/lan-password.conf",
    "SUBNET=$(ip route | awk '/proto kernel/ && !/wl|ww|lo|vir|br-|docker/{print $1; exit}') && test -n \"$SUBNET\" && mkdir -p /etc/ssh/sshd_config.d && printf 'PasswordAuthentication no\\n\\nMatch Address %s,127.0.0.1\\n\\tPasswordAuthentication yes\\n' \"$SUBNET\" > /etc/ssh/sshd_config.d/lan-password.conf && (systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true)").
%% A malformed drop-in must be rewritten before restarting sshd, or the
%% restart just reproduces the parse failure.
service_deps(sshd_answers, [service_ready(ssh_lan_password)]).
%% Printer: applicable when already configured (verify) or currently
%% discoverable on the LAN (configure) — otherwise skipped, not failed.
service_check(printer_lpadmin, Check, Fix) :-
    once(( shell_ok("lpstat -p hp-laserjet-mfp-2604sdw")
         ; shell_ok("avahi-browse -t -r -p _ipp._tcp 2>/dev/null | grep -q 2604sdw")
         )),
    Check = "lpstat -p hp-laserjet-mfp-2604sdw >/dev/null 2>&1",
    Fix = "IP=$(avahi-browse -t -r -p _ipp._tcp 2>/dev/null | awk -F';' '/^=/ && /2604sdw/{print $8; exit}') && test -n \"$IP\" && lpadmin -p hp-laserjet-mfp-2604sdw -E -v \"ipp://$IP/ipp/print\" -m everywhere && lpoptions -d hp-laserjet-mfp-2604sdw".
