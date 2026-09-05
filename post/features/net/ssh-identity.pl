%% net/ssh-identity — the user's keypair and how it reaches crucible:
%% key → authorized for localhost → crucible host entry (Tailscale IPv4
%% via the crucible.dns.army A record; AddressFamily inet ignores the AAAA).

user_config(ssh_key, Check, Fix) :-
    user_home(Home),
    format(atom(Check), "test -f ~w/.ssh/id_ed25519", [Home]),
    format(atom(Fix),
        "mkdir -p ~w/.ssh && chmod 700 ~w/.ssh && ssh-keygen -t ed25519 -f ~w/.ssh/id_ed25519 -N ''",
        [Home, Home, Home]).
user_config(ssh_authorized_keys, Check, Fix) :-
    user_home(Home),
    format(atom(Check),
        "test -f ~w/.ssh/authorized_keys && grep -qf ~w/.ssh/id_ed25519.pub ~w/.ssh/authorized_keys 2>/dev/null",
        [Home, Home, Home]),
    format(atom(Fix),
        "cat ~w/.ssh/id_ed25519.pub >> ~w/.ssh/authorized_keys && chmod 600 ~w/.ssh/authorized_keys",
        [Home, Home, Home]).
user_config(ssh_config_crucible, Check, Fix) :-
    user_home(Home),
    format(atom(Check),
        "grep -q '^Host crucible$' ~w/.ssh/config 2>/dev/null", [Home]),
    format(atom(Fix),
        "printf '%s\\n' 'Host crucible' '    AddressFamily inet' '    User m' '    IdentityFile ~w/.ssh/id_ed25519' '    ServerAliveInterval 60' >> ~w/.ssh/config && chmod 600 ~w/.ssh/config",
        [Home, Home, Home]).
%% No HostName: `crucible` resolves over the tailnet via MagicDNS
%% (--accept-dns, net/tailscale). The former HostName crucible.dns.army
%% is a dead DynDNS name (dns.army gone 2026-08); this drift rule strips
%% it from configs an earlier pass wrote, else `ssh crucible` hangs on it.
user_config(ssh_config_crucible_no_dnsarmy, Check, Fix) :-
    user_home(Home),
    format(atom(Check),
        "! grep -q 'crucible\\.dns\\.army' ~w/.ssh/config 2>/dev/null", [Home]),
    format(atom(Fix),
        "sed -i '/HostName crucible\\.dns\\.army/d' ~w/.ssh/config", [Home]).
%% The mDNS spelling is a separate Host block: ssh only applies User/options
%% when the TYPED name matches a Host pattern, so `ssh crucible.local` sailed
%% past the `Host crucible` block and fell back to the client's local username.
%% No HostName — the typed name is already the address (LAN, DHCP-proof).
user_config(ssh_config_crucible_local, Check, Fix) :-
    user_home(Home),
    format(atom(Check),
        "grep -q '^Host crucible\\.local$' ~w/.ssh/config 2>/dev/null", [Home]),
    format(atom(Fix),
        "printf '%s\\n' 'Host crucible.local' '    AddressFamily inet' '    User m' '    IdentityFile ~w/.ssh/id_ed25519' '    ServerAliveInterval 60' >> ~w/.ssh/config && chmod 600 ~w/.ssh/config",
        [Home, Home, Home]).

%% Peer authorization: each machine generates its OWN keypair and
%% self-authorizes, so the rig's key is unknown here until fetched.
%% origin is a peer clone (rig ⇄ laptop) — for the rig to fetch/push
%% back, its pubkey must sit in this machine's authorized_keys. The
%% already-working outbound direction delivers it: pull the key over
%% ssh, append if absent. Applicable only when the rig answers with
%% key auth (BatchMode) — offline rig is a skip, not a failure.
user_config(ssh_rig_key_authorized, Check, Fix) :-
    shell_ok("timeout 8 ssh -o BatchMode=yes -o ConnectTimeout=5 crucible.local true"),
    user_home(Home),
    format(atom(Check),
        "ssh -o BatchMode=yes crucible.local cat .ssh/id_ed25519.pub 2>/dev/null | grep -qxFf - ~w/.ssh/authorized_keys",
        [Home]),
    format(atom(Fix),
        "KEY=$(ssh -o BatchMode=yes crucible.local cat .ssh/id_ed25519.pub) && test -n \"$KEY\" && echo \"$KEY\" >> ~w/.ssh/authorized_keys && chmod 600 ~w/.ssh/authorized_keys",
        [Home, Home]).

user_config_deps(ssh_authorized_keys, [user_config_applied(ssh_key)]).
user_config_deps(ssh_config_crucible, [user_config_applied(ssh_key)]).
user_config_deps(ssh_config_crucible_local, [user_config_applied(ssh_key)]).
user_config_deps(ssh_rig_key_authorized, [user_config_applied(ssh_config_crucible_local)]).
