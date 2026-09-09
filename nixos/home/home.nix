# Home Manager — the user-owned half of the setup, one file for every
# user on every host. Nix cannot sense (pure evaluation: no hostname, no
# environment), so the flake passes `user` and `host` in and roles are
# DECLARED from them here; sensing stays POST's. Root state (apt, sudoers,
# SDDM, tailscaled, the NVIDIA driver, mounts) stays POST's too — on
# Ubuntu, Nix owns only what the user owns. The same file is consumed
# unchanged by the NixOS side (home-manager as a NixOS module, specialArgs
# user/host), so every area that moves here is migrated for the
# btrfs-on-LV NixOS install as well.
#
# POST applies it (base/home-manager.pl): each user's active generation is
# compared with what this flake evaluates to for user@host; drift →
# `home-manager switch` in that user's pipe (make | bash). Phase 0: a
# generation that owns nothing yet.
{ lib, user, host, ... }:
let
  rig    = host == "crucible";   # holds the backup drive; receive-only, versioned
  laptop = host == "servalws";   # travels; sends; carries the Fritz!Box peer
in
{
  home.username = user;
  home.homeDirectory = "/home/${user}";

  # Pins the state formats HM migrates between releases — never bump casually.
  home.stateVersion = "25.05";

  # `home-manager` CLI on PATH after the first switch (generations, rollback).
  programs.home-manager.enable = true;
}
