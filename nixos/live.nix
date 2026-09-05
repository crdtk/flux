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
    ./serval-install-script.nix
    ./packages.nix
  ];

  # vscode (Microsoft's build — parity with Ubuntu's `code`) is unfree;
  # nixpkgs refuses it without this explicit opt-in.
  nixpkgs.config.allowUnfree = true;

  isoImage.volumeID = "SERVAL_LIVE";
  # xz took 50+ min on 8 threads for this closure; zstd builds in minutes
  # for a modestly larger image — rebuild-speed wins for a rehearsal ISO.
  isoImage.squashfsCompression = "zstd -Xcompression-level 6";
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
  # claude-code: the rescue stick's killer feature — ask why the machine
  # won't boot, from the stick that boots. Auth note: the live system is
  # stateless, so `claude` needs its OAuth login once per boot (or copy
  # ~/.claude/.credentials.json from a synced machine into the session).
  environment.systemPackages = with pkgs; [ thunderbird firefox claude-code ];
}
