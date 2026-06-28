# Device-activated mount, NOT an automount. An automount mountpoint blocks any
# caller that touches it (the desktop file picker) until the mount attempt
# resolves — and device-timeout does not apply to that autofs trigger path, so a
# missing SN8100 freezes the picker. Binding the mount to the device unit instead
# means /mnt/backup is a plain empty dir when the drive is absent (listed
# instantly) and mounts automatically the moment the device appears. The chmod
# service fires via WantedBy so permissions are set on every hotplug, not just
# at first setup.
MANAGEMENT += /etc/systemd/system/mnt-backup.mount
MANAGEMENT += /etc/systemd/system/mnt-backup-chmod.service

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

define BACKUP_CHMOD_UNIT
[Unit]
Description=Set /mnt/backup permissions on mount
After=mnt-backup.mount
Requires=mnt-backup.mount

[Service]
Type=oneshot
ExecStart=/bin/chmod 1777 /mnt/backup
RemainAfterExit=yes

[Install]
WantedBy=mnt-backup.mount
endef

# dev-disk-by\x2dlabel-backup.device is the systemd unit for /dev/disk/by-label/backup
# (systemd escapes '-' as '\x2d'). WantedBy that device auto-starts the mount on hotplug.
/etc/systemd/system/mnt-backup.mount:
	sed -i '\|/mnt/backup|d' /etc/fstab 2>/dev/null || true
	mkdir -p /mnt/backup
	$(file >$@,$(BACKUP_MOUNT_UNIT))
	systemctl daemon-reload
	systemctl enable mnt-backup.mount
	@echo ">>> SN8100 mount armed (device-activated; empty dir when absent, no picker hang)"

/etc/systemd/system/mnt-backup-chmod.service:
	$(file >$@,$(BACKUP_CHMOD_UNIT))
	@systemctl daemon-reload && systemctl enable mnt-backup-chmod.service && echo ">>> /mnt/backup chmod service enabled"

SN8100_DEV := $(shell lsblk -dno NAME,MODEL 2>/dev/null | awk '/SN8100/{print $$1; exit}')
system::
ifeq ($(SN8100_DEV),)
	@echo 1 > /sys/bus/pci/rescan && sleep 1 && lsblk -d -o NAME,SIZE,MODEL | grep -E 'nvme|SN8100' || true
endif
.PHONY: eject
eject:
	@if [ -n "$(SN8100_DEV)" ]; then \
	   echo 1 > /sys/block/$(SN8100_DEV)/device/remove; \
	   echo ">>> Ejected $(SN8100_DEV)"; \
	 else echo ">>> SN8100 not found — nothing to eject"; fi
