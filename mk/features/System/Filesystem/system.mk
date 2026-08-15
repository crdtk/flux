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

# Root half of the disk cleanup (sensed 2026-08-14: 284G/468G). Explicit
# literal paths only — no globs — so nothing outside this list can ever
# be touched. /opt/pycharm-2025.3 goes because the desktop entry proves
# /opt/pycharm-community is the live IDE (Exec= checked 2026-08-14).
# The dead CUDA toolkit + Nsight (7.1G) are APT state, so their removal
# is POST's (platform/nvidia.pl no_dead_cuda, XXI) — rm here would
# desynchronize dpkg and fight the package rules.
DISK_CLEAN_ROOT := /opt/pycharm-2025.3
# ~/Pictures and ~/Desktop/Backup are family data — structurally
# untouchable: the build refuses if either ever enters a clean list.
$(if $(filter $(USER_HOME)/Pictures% $(USER_HOME)/Desktop/Backup%,$(DISK_CLEAN_ROOT)),$(error disk-clean: protected path in DISK_CLEAN_ROOT))

## Reclaim root-owned space: duplicate IDE, journal >200M, apt archives.
.PHONY: disk-clean-root
disk-clean-root:
	rm -rf $(DISK_CLEAN_ROOT)
	journalctl --vacuum-size=200M
	apt-get clean
	@df -h / | tail -1
