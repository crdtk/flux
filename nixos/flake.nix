{
  # NixOS-alongside for the laptop (serval): one flake, two outputs.
  #   - nixosConfigurations.serval    — the target system, installed into a
  #     NEW logical volume VG/nixos next to the untouched Kubuntu VG/root
  #   - packages.x86_64-linux.iso     — a self-installing USB image whose
  #     `serval-nixos-install` command encodes the whole offline procedure
  #     (fsck → ext4 shrink → lvreduce → lvcreate → btrfs → nixos-install)
  # Build with `make nixos-iso`, write with `make nixos-usb DEV=/dev/sdX`.
  description = "Serval NixOS-alongside: target system + self-installing USB";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

  outputs = { self, nixpkgs }:
    let system = "x86_64-linux";
    in {
      nixosConfigurations.serval = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [ ./serval.nix ];
      };

      nixosConfigurations.installer = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [ ./installer.nix { _module.args.flakeSelf = self; } ];
      };

      packages.${system}.iso =
        self.nixosConfigurations.installer.config.system.build.isoImage;
    };
}
