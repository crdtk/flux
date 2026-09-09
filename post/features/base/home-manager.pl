%% base/home-manager — Home Manager owns the user-level half of the setup
%% (nixos/home/home.nix); POST owns whether it is APPLIED. The check is a
%% content probe (XXI): the generation the profile points at must be the
%% one the flake evaluates to now — any edit to home.nix or flake.lock is
%% drift. The fix is the switch, user-level by nature (make | bash, never
%% root). --no-write-lock-file keeps sensing pure: a missing lock entry
%% fails the check instead of silently rewriting a tracked file; the
%% switch itself writes the lock. -b hm-bak: a dotfile HM is about to own
%% but did not write is moved aside, not fought over.
%%
%% Sensing cost: one `nix eval` per POST run (seconds once the inputs are
%% fetched). Flakes see only TRACKED files — the advisory names that.
%% Per user by construction: the rule runs as whoever pipes `make | bash`
%% and selects $(id -un)@$(hostname); a user absent from the flake's
%% `users` list fails the eval and shows as missing (declare, then rerun).

hm_flake(Dir) :-
    project_dir(Root),
    atom_concat(Root, '/nixos', Dir).

user_config(home_manager, Check, Fix) :-
    hm_flake(Flake), user_home(Home),
    format(atom(Check),
        "test -n \"$(readlink -f ~w/.local/state/nix/profiles/home-manager 2>/dev/null)\" && test \"$(readlink -f ~w/.local/state/nix/profiles/home-manager)\" = \"$(cd ~w && NIX_CONFIG='experimental-features = nix-command flakes' nix eval --raw --no-write-lock-file .#homeConfigurations.\\\"$(id -un)@$(hostname)\\\".activationPackage.outPath 2>/dev/null)\"",
        [Home, Home, Flake]),
    format(atom(Fix),
        "cd ~w && NIX_CONFIG='experimental-features = nix-command flakes' nix run home-manager/release-25.05 -- switch -b hm-bak --flake .#$(id -un)@$(hostname)",
        [Flake]).

user_config_deps(home_manager, [packages_installed]).

%% The one manual step: the flake cannot see untracked files.
advisory(user_config, home_manager,
    'nixos/home/home.nix is not tracked by git — flakes see only tracked files: git add nixos/home before the switch can evaluate') :-
    project_dir(Root),
    format(atom(Cmd), "cd ~w && git ls-files --error-unmatch nixos/home/home.nix >/dev/null 2>&1", [Root]),
    \+ shell_ok(Cmd).
