# SN8100 backup-drive units are owned by POST (post/post.pl: service_check
# backup_mount, XXI). This module keeps only the hotplug hand actions.

SN8100_DEV := $(shell lsblk -dno NAME,MODEL 2>/dev/null | awk '/SN8100/{print $$1; exit}')

## Software-eject the SN8100 before physically pulling it.
.PHONY: eject
eject:
	@if [ -n "$(SN8100_DEV)" ]; then \
	   echo 1 > /sys/block/$(SN8100_DEV)/device/remove; \
	   echo ">>> Ejected $(SN8100_DEV)"; \
	 else echo ">>> SN8100 not found — nothing to eject"; fi

## Re-detect a hot-inserted SN8100 without rebooting (inverse of eject).
.PHONY: rescan
rescan:
	@echo 1 > /sys/bus/pci/rescan; sleep 1; lsblk -d -o NAME,SIZE,MODEL | grep -E 'nvme|SN8100' || true
