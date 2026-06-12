SN8100_DEV := $(shell lsblk -dno NAME,MODEL 2>/dev/null | awk '/SN8100/{print $$1; exit}')

STORAGE += /etc/systemd/system/multi-user.target.wants/mnt-backup.automount

/etc/systemd/system/multi-user.target.wants/mnt-backup.automount: /etc/systemd/system/mnt-backup.automount
	systemctl enable --now mnt-backup.automount
	systemctl start mnt-backup.mount
	chmod 1777 /mnt/backup
	@echo ">>> SN8100 automount enabled at /mnt/backup"

define BACKUP_AUTOMOUNT_UNIT
[Unit]
Description=Automount NVMe backup drive (SN8100)

[Automount]
Where=/mnt/backup
TimeoutIdleSec=0

[Install]
WantedBy=multi-user.target
endef

/etc/systemd/system/mnt-backup.automount: /etc/systemd/system/mnt-backup.mount
	$(file >$@,$(BACKUP_AUTOMOUNT_UNIT))

define BACKUP_MOUNT_UNIT
[Unit]
Description=NVMe backup drive (SN8100)

[Mount]
What=/dev/disk/by-label/backup
Where=/mnt/backup
Type=ext4
Options=defaults,noatime

[Install]
WantedBy=multi-user.target
endef

/etc/systemd/system/mnt-backup.mount:
	sed -i '\|/mnt/backup|d' /etc/fstab 2>/dev/null || true
	$(file >$@,$(BACKUP_MOUNT_UNIT))
	systemctl daemon-reload

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
