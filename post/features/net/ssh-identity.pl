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
        "grep -q '^Host crucible' ~w/.ssh/config 2>/dev/null", [Home]),
    format(atom(Fix),
        "printf '%s\\n' 'Host crucible' '    HostName crucible.dns.army' '    AddressFamily inet' '    User m' '    IdentityFile ~w/.ssh/id_ed25519' '    ServerAliveInterval 60' >> ~w/.ssh/config && chmod 600 ~w/.ssh/config",
        [Home, Home, Home]).

user_config_deps(ssh_authorized_keys, [user_config_applied(ssh_key)]).
user_config_deps(ssh_config_crucible, [user_config_applied(ssh_key)]).
