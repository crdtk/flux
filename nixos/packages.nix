# GENERATED from POST's binary_pkg catalog by nixos/deb2nix.pl
# (make nixos/packages.nix). Edit the mapping there, never this file.
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    # appmenu-gtk3-module — global-menu shim: revisit with the panel config
    # appmenu-registrar — global-menu shim: revisit with the panel config
    # apt-file — apt plumbing: no NixOS analogue
    arp-scan
    ausweisapp
    # avahi-daemon — service: services.avahi
    bleachbit
    cmake
    # cockpit cockpit-files — service: no live-ISO consumer
    # cockpit-storaged — service: no live-ISO consumer
    vscode
    czkawka
    czkawka-full
    digikam
    dmidecode
    f3d
    kdePackages.ffmpegthumbs
    kdePackages.filelight
    flameshot
    gcc14
    gh
    git
    # grafana — service: services.grafana
    kdePackages.gwenview
    jq
    kdePackages.kdeconnect-kde
    kdePackages.kdenlive
    kdePackages.kimageformats
    libheif
    exiftool
    mc
    ncdu
    # nix-bin — native on NixOS
    # nix-setup-systemd — native on NixOS
    nmap
    nodejs
    obs-studio
    # openssh-server — service: services.openssh
    pciutils
    plank
    plantuml
    # plasma-session-x11 — comes with services.desktopManager.plasma6
    kdePackages.kdeplasma-addons
    # prometheus — service: services.prometheus
    rclone
    sane-airscan
    simple-scan
    swi-prolog
    syncthing
    # tailscale — service: services.tailscale
    terminator
    vlc
    wakeonlan
    xclip
    xournalpp
  ];
}
