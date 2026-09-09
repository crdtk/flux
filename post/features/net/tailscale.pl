%% net/tailscale — mesh VPN replacing DynDNS/port-forwarding; the crucible
%% host is reached over the tailnet (see net/ssh-identity for the client
%% side). First login is env-gated: TS_AUTHKEY="tskey-…" make | sudo bash.

binary_pkg('/usr/bin/tailscale', tailscale).

apt_repo(tailscale_repo,
    "test -f /etc/apt/sources.list.d/tailscale.list",
    AddCmd) :-
    ubuntu_codename(C),
    format(atom(AddCmd),
        "curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/~w.noarmor.gpg | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null && curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/~w.tailscale-keyring.list | tee /etc/apt/sources.list.d/tailscale.list",
        [C, C]).

pkg_repo(tailscale, tailscale_repo).

%% The daemon is the package's own unit; `make clean` disables it
%% (mk/clean.mk) and nothing brought it back — found 2026-09-09 after a
%% reboot with no socket. Forward rule, first in the chain: everything
%% below needs a running tailscaled.
service_check(tailscaled_running,
    "systemctl is-enabled tailscaled >/dev/null 2>&1 && systemctl is-active tailscaled >/dev/null 2>&1",
    "systemctl enable --now tailscaled").

%% Login is a one-time act: `tailscale up --authkey` stores the node key in
%% /var/lib/tailscale/ and tailscaled reconnects from that state on every
%% boot. No login service of ours is needed — a bare `tailscale up` on
%% boot would in fact FAIL once --accept-routes/--accept-dns are set (it
%% demands the flags be repeated or --reset). The auth key is staged by
%% base/tools.pl (0_tailscale_authkey, from TS_AUTHKEY) and consumed here;
%% a node already holding state passes the check and never reads it.
service_check(tailscale_login_now,
    "tailscale status 2>/dev/null | grep -q '^100\\.'",
    "tailscale up --authkey=\"$(cat /etc/tailscale/authkey)\" --ssh --accept-routes --accept-dns").

%% --ssh runs Tailscale's SSH server so `tailscale ssh <host>` reaches
%% this node without touching sshd; `set` adds it to a logged-in node.
service_check(tailscale_ssh_server,
    "tailscale debug prefs 2>/dev/null | grep -q '\"RunSSH\": *true'",
    "tailscale set --ssh").

%% Single-level chain (XXIV): daemon → login → ssh. One `make | sudo bash`
%% converges all three in order.
service_deps(tailscaled_running,   [packages_installed]).
service_deps(tailscale_login_now,  [service_ready(tailscaled_running)]).
service_deps(tailscale_ssh_server, [service_ready(tailscale_login_now)]).

%% Inverse of the 2026-09-05 login service (spent design, see above):
%% remove it wherever an earlier pass installed it.
hardening_check(no_tailscale_login_service,
    "! test -e /etc/systemd/system/tailscale-login.service && ! test -e /usr/local/bin/tailscale-login",
    "systemctl disable --now tailscale-login.service 2>/dev/null; rm -f /etc/systemd/system/tailscale-login.service /usr/local/bin/tailscale-login; systemctl daemon-reload").
