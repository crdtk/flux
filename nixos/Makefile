# NixOS-alongside (laptop): build the self-installing USB from flake.nix.
# nix itself (nix-bin + daemon + group + flakes enabled system-wide,
# base/tools.pl nix_flakes_enabled) is POST-provisioned; these targets are
# builds and a destructive interactive write — the make-side of the split.
# Operates from both root (make nixos-iso) and cd nixos && make nixos-iso.
# "experimental feature 'nix-command' is disabled" means the root POST
# pass has not run yet on this machine — not a flag to add here.

# Shared variables (passed when included from root; defaults when run standalone).
USER_HOME  ?= $(shell getent passwd $${SUDO_USER:-$$(whoami)} | cut -d: -f6)
NIXOS_DIR  := $(dir $(lastword $(MAKEFILE_LIST)))

NIX := nix

## Build the self-installing NixOS ISO (result symlink at nixos/result).
.PHONY: nixos-iso
nixos-iso:
	@command -v nix >/dev/null || { echo ">>> nix missing — run the POST first (make | sudo bash)"; exit 1; }
	cd $(NIXOS_DIR) && $(NIX) build .#iso -o result
	@ls -lh $(NIXOS_DIR)result/iso/*.iso

## Write the ISO to a USB stick: make nixos-usb DEV=/dev/sdX  (DESTROYS the stick).
.PHONY: nixos-usb
nixos-usb: nixos-iso
	@test -n "$(DEV)" || { echo ">>> usage: make nixos-usb DEV=/dev/sdX"; exit 1; }
	@test -b "$(DEV)" || { echo ">>> $(DEV) is not a block device"; exit 1; }
# fence: whole-disk removable devices only — never a partition, never the NVMe
	@test "$$(cat /sys/block/$(notdir $(DEV))/removable 2>/dev/null)" = 1 \
	  || { echo ">>> $(DEV) is not a removable whole-disk device — refusing"; exit 1; }
	@echo ">>> writing $$(ls $(NIXOS_DIR)result/iso/*.iso) to $(DEV) in 5s (ctrl-c to abort)"; sleep 5
	sudo dd if=$$(ls $(NIXOS_DIR)result/iso/*.iso) of=$(DEV) bs=4M conv=fsync status=progress
	@echo ">>> done — boot the laptop from it and run: sudo serval-nixos-install"

# packages.nix is GENERATED: POST's binary_pkg facts are the single
# catalog; deb2nix.pl maps deb names to nixpkgs attrs (skips = services
# and apt plumbing; unmapped facts surface as TODO comments — the
# mechanically-discovered migration gap list).
$(NIXOS_DIR)packages.nix: $(NIXOS_DIR)deb2nix.pl $(wildcard post/features/*/*.pl) post/post.pl
	cd $(NIXOS_DIR) && swipl -q -g export_nix -t halt deb2nix.pl >/dev/null

## Build the live-desktop ISO — the provisioned environment, reproduced on a stick.
.PHONY: nixos-live-iso
nixos-live-iso: $(NIXOS_DIR)packages.nix
	@command -v nix >/dev/null || { echo ">>> nix missing — run the POST first (make | sudo bash)"; exit 1; }
	cd $(NIXOS_DIR) && $(NIX) build .#live-iso -o result-live
	@ls -lh $(NIXOS_DIR)result-live/iso/*.iso

# VM rehearsal: boot a built ISO in UEFI QEMU (KVM) with a throwaway
# 20G scratch disk — the artifact meets virtual hardware before real.
# Installer ISO by default; ISO=live boots the live-desktop one.
$(NIXOS_DIR)vm-disk.qcow2:
	qemu-img create -f qcow2 $@ 20G

## Boot the built ISO in a UEFI VM: make nixos-vm [ISO=live]
.PHONY: nixos-vm
nixos-vm: $(NIXOS_DIR)vm-disk.qcow2
	@command -v qemu-system-x86_64 >/dev/null || { echo ">>> qemu missing — run the POST first (make | sudo bash)"; exit 1; }
	@iso=$$(ls $(NIXOS_DIR)result$(if $(filter live,$(ISO)),-live,)/iso/*.iso 2>/dev/null); \
	  test -n "$$iso" || { echo ">>> no ISO built — run: make nixos-$(if $(filter live,$(ISO)),live-,)iso"; exit 1; }; \
	  qemu-system-x86_64 -enable-kvm -cpu host -smp 4 -m 6144 \
	    -bios /usr/share/ovmf/OVMF.fd \
	    -drive file=$(NIXOS_DIR)vm-disk.qcow2,if=virtio \
	    -cdrom "$$iso" -boot d -vga virtio
