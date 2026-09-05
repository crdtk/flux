%% net/tailscale — mesh VPN replacing DynDNS/port-forwarding; the crucible
%% host is reached over the tailnet (see net/ssh-identity for the client
%% side). Login is env-gated: no TS_AUTHKEY, no fix — only the advisory.

binary_pkg('/usr/bin/tailscale', tailscale).

apt_repo(tailscale_repo,
    "test -f /etc/apt/sources.list.d/tailscale.list",
    AddCmd) :-
    ubuntu_codename(C),
    format(atom(AddCmd),
        "curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/~w.noarmor.gpg | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null && curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/~w.tailscale-keyring.list | tee /etc/apt/sources.list.d/tailscale.list",
        [C, C]).

pkg_repo(tailscale, tailscale_repo).

%% Tailscale login handled by systemd service (tailscale-login.service).
%% Auth key prompt moved to base/tools.pl to run early, before other setup.
%% Boot-time service reads /etc/tailscale/authkey and authenticates once.
%% Auth state persists in /var/lib/tailscale/ across reboots.

hardening_check(tailscale_login_now,
    "tailscale status 2>/dev/null | grep -q '^100\\.'",
    "mkdir -p /var/lib/tailscale && tailscale up --authkey=\"$(cat /etc/tailscale/authkey)\" --accept-routes --accept-dns").

hardening_check(tailscale_login_service,
    "test -f /etc/systemd/system/tailscale-login.service",
    "cat > /etc/systemd/system/tailscale-login.service << 'EOF'\n[Unit]\nDescription=Tailscale auto-reconnect on boot\nAfter=tailscale.service\nWants=tailscale.service\n\n[Service]\nType=oneshot\nExecStart=/usr/bin/tailscale up\nRemainAfterExit=yes\nUser=root\n\n[Install]\nWantedBy=multi-user.target\nEOF\nsystemctl daemon-reload && systemctl enable tailscale-login.service").

hardening_check(tailscale_login_script,
    "test -f /usr/local/bin/tailscale-login && grep -q 'tailscale up' /usr/local/bin/tailscale-login",
    "cat > /usr/local/bin/tailscale-login << 'EOF'\n#!/usr/bin/env bash\nset -e\nif ! tailscale status 2>/dev/null | grep -q '^100\\.'; then\n  AUTHKEY=$(cat /etc/tailscale/authkey 2>/dev/null) || { echo 'ERROR: /etc/tailscale/authkey not found'; exit 1; }\n  tailscale up --authkey=\"$AUTHKEY\" --accept-routes --accept-dns\nfi\nEOF\nchmod 755 /usr/local/bin/tailscale-login").
