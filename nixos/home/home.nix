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
# `home-manager switch` in that user's pipe (make | bash).
#
# Phase 0: bootstrap. Phase 1: Syncthing — the fleet's file plane and the
# backup.
{ lib, user, host, ... }:
let
  rig    = host == "crucible";   # holds the backup drive; receive-only, versioned
  laptop = host == "servalws";   # travels; sends; carries the Fritz!Box peer
  home   = "/home/${user}";
in
{
  home.username = user;
  home.homeDirectory = home;

  # Pins the state formats HM migrates between releases — never bump casually.
  home.stateVersion = "25.05";

  # `home-manager` CLI on PATH after the first switch (generations, rollback).
  programs.home-manager.enable = true;

  # ── Syncthing ────────────────────────────────────────────────────────────
  # HM owns the user unit and writes devices/folders through the REST API
  # at activation; with override* (the module's default) this set is the
  # whole truth. Device IDs are public identity, so they live in the tree.
  # crucible is the backup machine: every folder lands there receive-only,
  # on the backup drive, with STAGGERED versioning — a deletion (or a
  # ransomware) on a sender never reaches the history. The rig has to be
  # on for a backup to happen; POST says so (net/syncthing.pl). Folder
  # paths on the rig point into /mnt/backup: while the drive is out the
  # folders pause with "path missing" and resume on plug — that IS the
  # detachable copy. The GUI password stays POST's env-gated patch.
  services.syncthing = {
    enable = true;
    settings = {
      devices = {
        servalws  = { id = "NOERJM3-UDBW6Y3-E2ZKH3I-52HIWUI-WWHO2K7-27JKXKE-66MDY6N-A3EQRQL"; };
        crucible  = { id = "P7YYKTE-RFDCH33-USBZFKX-LB5D7EL-FJNRCF2-B4FNLL5-ZTDKRMW-HYWEAQD"; };
        xcoverpro = { id = "O4PRMHD-ZRZPUTI-YCN4OOX-NYUQEM6-TYTHKXC-FI4SYQC-IZQSMK6-BONKBQM"; };
      };
      folders =
        let
          staggered = { type = "staggered"; params = { cleanInterval = "3600"; maxAge = "31536000"; }; };
          # The rig's side of any folder: under the backup drive, receive-only, versioned.
          onRig = sub: { path = "/mnt/backup/${sub}"; type = "receiveonly"; versioning = staggered; };
        in {
          # Existing folder — id kept so the peers keep matching.
          "mtckm-l3fkj" = { label = "Serval-Pictures"; devices = [ "servalws" "crucible" ]; }
            // (if rig then onRig "servalws/Pictures" else { path = "${home}/Pictures"; });
          "serval-desktop" = { label = "Serval-Desktop"; devices = [ "servalws" "crucible" ]; }
            // (if rig then onRig "servalws/Desktop" else { path = "${home}/Desktop"; });
          # The phone sends its camera roll. Folder ID is set BY HAND on the
          # phone to "xcover-dcim" when sharing (Syncthing-Fork lets you) —
          # then the declared folder binds; POST advises while it is pending.
          "xcover-dcim" = { label = "XcoverPro-DCIM"; devices = [ "xcoverpro" "servalws" "crucible" ]; type = "receiveonly"; }
            // (if rig then onRig "xcoverpro/DCIM" else { path = "${home}/Pictures/Phone"; });
        };
      gui.address = "0.0.0.0:8384";   # LAN-reachable GUI; auth is POST's patch
      options.urAccepted = -1;        # no usage reporting
    };
  };

  # What the laptop's Desktop does NOT send (the rsync SYNC_EXCLUDES
  # rationale in Network/RemoteAccess): git working trees sync via git,
  # never file-level; the rest are per-machine or deliberately local.
  home.file."Desktop/.stignore" = lib.mkIf laptop {
    text = ''
      Projects/flux
      Crucible
      LLMs-from-scratch
      secrets
      bert-size-reco
      **/.git
      (?d).sync*
      (?d)*.sync-conflict-*
    '';
  };
}
