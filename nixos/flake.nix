{
  # NixOS-alongside for the laptop (serval): one flake, two outputs.
  #   - nixosConfigurations.serval    — the target system, installed into a
  #     NEW logical volume VG/nixos next to the untouched Kubuntu VG/root
  #   - packages.x86_64-linux.iso     — a self-installing USB image whose
  #     `serval-nixos-install` command encodes the whole offline procedure
  #     (fsck → ext4 shrink → lvreduce → lvcreate → btrfs → nixos-install)
  # Build with `make nixos-iso`, write with `make nixos-usb DEV=/dev/sdX`.
  #   - homeConfigurations."<user>@<host>" — Home Manager on the UBUNTU
  #     hosts: the user-owned half of the setup, one file (home/home.nix)
  #     with roles declared from user and host. Applied by POST
  #     (base/home-manager.pl) in each user's pipe. Same nixpkgs pin as the
  #     ISOs, and the same file the NixOS side consumes later — migrated
  #     once, for both.
  description = "Serval NixOS-alongside: target system + self-installing USB + Home Manager on Ubuntu";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  inputs.home-manager.url = "github:nix-community/home-manager/release-25.05";
  inputs.home-manager.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { self, nixpkgs, home-manager }:
    let
      system = "x86_64-linux";
      lib = nixpkgs.lib;
      # The fleet as data. Nix cannot sense users or hosts (pure eval), so
      # both are declared; home.nix derives roles from the names. Adding a
      # user or a host is one list entry — every user@host pair is generated.
      users = [ "m" ];
      hosts = [ "servalws" "crucible" ];
      home = user: host: home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.${system};
        extraSpecialArgs = { inherit user host; };
        modules = [ ./home/home.nix ];
      };
    in {
      homeConfigurations = lib.listToAttrs (map
        ({ user, host }: { name = "${user}@${host}"; value = home user host; })
        (lib.cartesianProduct { user = users; host = hosts; }));

      nixosConfigurations.serval = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [ ./serval.nix ];
      };

      nixosConfigurations.installer = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [ ./installer.nix { _module.args.flakeSelf = self; } ];
      };

      # Live-desktop clone of the provisioned environment (reproduced
      # from POST's catalog via packages.nix, never copied).
      nixosConfigurations.live = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [ ./live.nix { _module.args.flakeSelf = self; } ];
      };

      packages.${system} = {
        iso = self.nixosConfigurations.installer.config.system.build.isoImage;
        live-iso = self.nixosConfigurations.live.config.system.build.isoImage;
      };
    };
}
