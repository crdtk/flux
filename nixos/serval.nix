{ config, pkgs, lib, ... }:
{
  # Target system: lives entirely inside the LV the installer creates
  # (/dev/VG/nixos, btrfs) plus a shared ESP. Kubuntu's VG/root is never
  # referenced here — the two systems only meet at the firmware boot menu.

  system.stateVersion = "25.05";
  networking.hostName = "serval-nixos";
  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "en_US.UTF-8";

  # Root is an LV on NVMe — initrd must assemble LVM before mounting.
  boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "usb_storage" "sd_mod" ];
  boot.initrd.services.lvm.enable = true;

  # systemd-boot on the EXISTING ESP (shared with Kubuntu's GRUB). It adds
  # its own EFI entry and never removes Ubuntu's — pick the OS in the
  # firmware boot menu (or efibootmgr -o). configurationLimit keeps NixOS
  # kernel payloads small on the 940M ESP.
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 4;
  boot.loader.efi.canTouchEfiVariables = true;

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "btrfs";
    options = [ "subvol=@" "compress=zstd" "noatime" ];
  };
  fileSystems."/home" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "btrfs";
    options = [ "subvol=@home" "compress=zstd" "noatime" ];
  };
  # The laptop's real ESP (blkid UUID 7278-528B, vfat, nvme0n1p1).
  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/7278-528B";
    fsType = "vfat";
    options = [ "umask=0077" ];
  };

  # Mirrors the unified stack decided 2026-08-16: SDDM + Plasma, nothing else.
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;
  networking.networkmanager.enable = true;
  services.openssh.enable = true;

  users.users.m = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    # First-boot password — change immediately with `passwd`.
    initialPassword = "changeme";
  };

  environment.systemPackages = with pkgs; [ git vim htop btrfs-progs ];
}
