{ config, pkgs, lib, modulesPath, ... }:
{
  # Live-desktop ISO: the provisioned environment, reproduced — not
  # copied. Boots to SDDM → Plasma 6 with the POST tool catalog
  # (packages.nix, generated from binary_pkg facts), RAM-backed,
  # touching no disk. Doubles as a rescue environment that feels like
  # home and as the try-before-committing preview of the migration.
  # Stateless by design: data lives on the rig/Syncthing, not the stick.
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
    ./packages.nix
  ];

  isoImage.volumeID = "SERVAL_LIVE";
  networking.hostName = "serval-live";
  time.timeZone = "Europe/Berlin";

  # Same unified stack as serval.nix / both physical machines.
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;
  services.displayManager.autoLogin = { enable = true; user = "m"; };
  networking.networkmanager.enable = true;
  # The minimal-ISO base enables wireless.networking (wpa_supplicant);
  # NetworkManager owns wifi in our stack — the two conflict.
  networking.wireless.enable = lib.mkForce false;

  users.users.m = {
    isNormalUser = true;
    uid = 1000;                       # matches the laptop — NFS/rsync sanity
    extraGroups = [ "wheel" "networkmanager" ];
    initialPassword = "";
  };

  # Not in the binary_pkg catalog (they are opt_installs on Ubuntu, snap
  # politics) but part of the environment; plain packages here.
  environment.systemPackages = with pkgs; [ thunderbird firefox ];
}
