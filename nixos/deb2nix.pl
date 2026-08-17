%% nixos/deb2nix — export POST's binary_pkg catalog as packages.nix.
%% The single source of truth stays post/ (its facts); this walks the
%% loaded catalog through a deb→nixpkgs mapping and writes
%% nixos/packages.nix for the live ISO. Unmapped packages come out as
%% TODO comments — the migration gap list, discovered mechanically,
%% never hand-maintained. Run via: make nixos/packages.nix
%%
%% skip/2: things that are not packages on NixOS — services get module
%% options in live.nix/serval.nix, apt plumbing has no analogue, and
%% session packages come with the desktop module.

:- consult('post/post.pl').

nix_name(flameshot,                 flameshot).
nix_name(gwenview,                  'kdePackages.gwenview').
nix_name('libheif-examples',        libheif).
nix_name('kimageformat-plugins',    'kdePackages.kimageformats').
nix_name(terminator,                terminator).
nix_name(mc,                        mc).
nix_name(plank,                     plank).
nix_name(rclone,                    rclone).
nix_name(xclip,                     xclip).
nix_name(jq,                        jq).
nix_name(plantuml,                  plantuml).
nix_name(f3d,                       f3d).
nix_name(npm,                       nodejs).
nix_name(bleachbit,                 bleachbit).
nix_name(filelight,                 'kdePackages.filelight').
nix_name(ncdu,                      ncdu).
nix_name('czkawka-gui',             'czkawka-full').
nix_name('czkawka-cli',             czkawka).
nix_name(kdenlive,                  'kdePackages.kdenlive').
nix_name(digikam,                   digikam).
nix_name('libimage-exiftool-perl',  exiftool).
nix_name('obs-studio',              'obs-studio').
nix_name(xournalpp,                 xournalpp).
nix_name(ausweisapp,                ausweisapp).
nix_name(vlc,                       vlc).
nix_name(kdeconnect,                'kdePackages.kdeconnect-kde').
nix_name(git,                       git).
nix_name('arp-scan',                'arp-scan').
nix_name(nmap,                      nmap).
nix_name(pciutils,                  pciutils).
nix_name(dmidecode,                 dmidecode).
nix_name(wakeonlan,                 wakeonlan).
nix_name(ffmpegthumbs,              'kdePackages.ffmpegthumbs').
nix_name('plasma-widgets-addons',   'kdePackages.kdeplasma-addons').
nix_name(code,                      vscode).
nix_name(cmake,                     cmake).
nix_name('g++-14',                  gcc14).
nix_name('swi-prolog-core',         'swi-prolog').
nix_name(gh,                        gh).
nix_name('sane-airscan',            'sane-airscan').
nix_name('simple-scan',             'simple-scan').
nix_name(syncthing,                 syncthing).
nix_name(ipmitool,                  ipmitool).

skip('avahi-daemon',       'service: services.avahi').
skip('openssh-server',     'service: services.openssh').
skip(grafana,              'service: services.grafana').
skip(prometheus,           'service: services.prometheus').
skip(tailscale,            'service: services.tailscale').
skip(cockpit,              'service: no live-ISO consumer').
skip('cockpit cockpit-files', 'service: no live-ISO consumer').
skip('cockpit-storaged',   'service: no live-ISO consumer').
skip('apt-file',           'apt plumbing: no NixOS analogue').
skip('nix-bin',            'native on NixOS').
skip('nix-setup-systemd',  'native on NixOS').
skip('plasma-session-x11', 'comes with services.desktopManager.plasma6').
skip('appmenu-gtk3-module','global-menu shim: revisit with the panel config').
skip('appmenu-registrar',  'global-menu shim: revisit with the panel config').

emit(S, K) :- skip(K, Why), !, format(S, "    # ~w — ~w~n", [K, Why]).
emit(S, K) :- nix_name(K, N), !, format(S, "    ~w~n", [N]).
emit(S, K) :- format(S, "    # TODO(unmapped): ~w~n", [K]).

export_nix :-
    setof(K, P^binary_pkg(P, K), Pkgs),
    open('nixos/packages.nix', write, S),
    format(S, "# GENERATED from POST's binary_pkg catalog by nixos/deb2nix.pl~n", []),
    format(S, "# (make nixos/packages.nix). Edit the mapping there, never this file.~n", []),
    format(S, "{ pkgs, ... }:~n{~n  environment.systemPackages = with pkgs; [~n", []),
    forall(member(K, Pkgs), emit(S, K)),
    format(S, "  ];~n}~n", []),
    close(S).
