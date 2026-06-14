SN8100_DEV := $(shell lsblk -dno NAME,MODEL 2>/dev/null | awk '/SN8100/{print $$1; exit}')

# Device-activated mount, NOT an automount. An automount mountpoint blocks any
# caller that touches it (the desktop file picker) until the mount attempt
# resolves — and device-timeout does not apply to that autofs trigger path, so a
# missing SN8100 freezes the picker. Binding the mount to the device unit instead
# means /mnt/backup is a plain empty dir when the drive is absent (listed
# instantly) and mounts automatically the moment the device appears. The enable
# is ungated (MANAGEMENT) so hotplug works anytime; chmod-on-mount is gated.
MANAGEMENT += /etc/systemd/system/mnt-backup.mount
STORAGE    += mount-backup

.PHONY: mount-backup
mount-backup: /etc/systemd/system/mnt-backup.mount
	systemctl start mnt-backup.mount
	chmod 1777 /mnt/backup
	@echo ">>> SN8100 mounted at /mnt/backup"

# dev-disk-by\x2dlabel-backup.device is the systemd unit for /dev/disk/by-label/backup
# (systemd escapes '-' as '\x2d'). WantedBy that device auto-starts the mount on hotplug.
define BACKUP_MOUNT_UNIT
[Unit]
Description=NVMe backup drive (SN8100)

[Mount]
What=/dev/disk/by-label/backup
Where=/mnt/backup
Type=ext4
Options=defaults,noatime,nofail

[Install]
WantedBy=dev-disk-by\x2dlabel-backup.device
endef

/etc/systemd/system/mnt-backup.mount:
	sed -i '\|/mnt/backup|d' /etc/fstab 2>/dev/null || true
	mkdir -p /mnt/backup
	$(file >$@,$(BACKUP_MOUNT_UNIT))
	systemctl daemon-reload
	systemctl enable mnt-backup.mount
	@echo ">>> SN8100 mount armed (device-activated; empty dir when absent, no picker hang)"

.PHONY: detect-sn8100
detect-sn8100:
	@echo 1 > /sys/bus/pci/rescan
	@sleep 1
	@lsblk -d -o NAME,SIZE,MODEL | grep -E 'nvme|SN8100' || true

.PHONY: eject
eject:
	@[ -n "$(SN8100_DEV)" ] || { echo "SN8100 not found"; exit 1; }
	echo 1 > /sys/block/$(SN8100_DEV)/device/remove
	@echo ">>> Ejected $(SN8100_DEV)"
