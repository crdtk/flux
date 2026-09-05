{ config, pkgs, lib, modulesPath, flakeSelf, ... }:
{
  # Console install USB. Boot it, log in as nixos, run:
  #   sudo serval-nixos-install
  # The script IS the procedure — every step fenced, nothing improvised
  # at the console; it lives in serval-install-script.nix, shared with
  # the live-desktop ISO (which carries the same installer in a Plasma
  # session — the more comfortable vehicle for the same ritual).
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
    ./serval-install-script.nix
  ];

  isoImage.volumeID = "SERVAL_NIXOS";
  networking.hostName = "serval-installer";
}
