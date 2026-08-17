# NixOS-alongside (laptop): build the self-installing USB from nixos/flake.nix.
# nix itself (nix-bin + daemon + group) is POST-provisioned; these targets are
# builds and a destructive interactive write — the make-side of the split.

NIX := nix --extra-experimental-features 'nix-command flakes'
NIXOS_ISO_LINK := nixos/result

## Build the self-installing NixOS ISO (result symlink at nixos/result).
.PHONY: nixos-iso
nixos-iso:
	@command -v nix >/dev/null || { echo ">>> nix missing — run the POST first (make | sudo bash)"; exit 1; }
	cd nixos && $(NIX) build .#iso -o result
	@ls -lh $(NIXOS_ISO_LINK)/iso/*.iso

## Write the ISO to a USB stick: make nixos-usb DEV=/dev/sdX  (DESTROYS the stick).
.PHONY: nixos-usb
nixos-usb: nixos-iso
	@test -n "$(DEV)" || { echo ">>> usage: make nixos-usb DEV=/dev/sdX"; exit 1; }
	@test -b "$(DEV)" || { echo ">>> $(DEV) is not a block device"; exit 1; }
# fence: whole-disk removable devices only — never a partition, never the NVMe
	@test "$$(cat /sys/block/$(notdir $(DEV))/removable 2>/dev/null)" = 1 \
	  || { echo ">>> $(DEV) is not a removable whole-disk device — refusing"; exit 1; }
	@echo ">>> writing $$(ls $(NIXOS_ISO_LINK)/iso/*.iso) to $(DEV) in 5s (ctrl-c to abort)"; sleep 5
	sudo dd if=$$(ls $(NIXOS_ISO_LINK)/iso/*.iso) of=$(DEV) bs=4M conv=fsync status=progress
	@echo ">>> done — boot the laptop from it and run: sudo serval-nixos-install"

# packages.nix is GENERATED: POST's binary_pkg facts are the single
# catalog; deb2nix.pl maps deb names to nixpkgs attrs (skips = services
# and apt plumbing; unmapped facts surface as TODO comments — the
# mechanically-discovered migration gap list).
nixos/packages.nix: nixos/deb2nix.pl $(wildcard post/features/*/*.pl) post/post.pl
	swipl -q -g export_nix -t halt nixos/deb2nix.pl >/dev/null

## Build the live-desktop ISO — the provisioned environment, reproduced on a stick.
.PHONY: nixos-live-iso
nixos-live-iso: nixos/packages.nix
	@command -v nix >/dev/null || { echo ">>> nix missing — run the POST first (make | sudo bash)"; exit 1; }
	cd nixos && $(NIX) build .#live-iso -o result-live
	@ls -lh nixos/result-live/iso/*.iso
