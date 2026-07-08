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

%% Tailscale login — only fixable when TS_AUTHKEY is in the environment;
%% without it the advisory below names the human step instead.
service_check(tailscale_up, Check, Fix) :-
    getenv('TS_AUTHKEY', Key),
    Check = "tailscale status 2>/dev/null | grep -q '^100\\.'",
    format(atom(Fix),
        "tailscale up --authkey \"~w\" --accept-routes --accept-dns", [Key]).

advisory(services, tailscale_up,
         'not logged in — export TS_AUTHKEY to authenticate') :-
    \+ service_check(tailscale_up, _, _),
    \+ shell_ok("tailscale status 2>/dev/null | grep -q '^100\\.'").
