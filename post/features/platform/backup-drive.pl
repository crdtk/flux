%% platform/backup-drive — the SN8100 as hot-pluggable backup storage.
%% Device-activated mount, NOT an automount: /mnt/backup is a plain empty
%% dir when the SN8100 is absent (no file-picker hang) and mounts on
%% hotplug. Only applicable while the labelled device is visible. The
%% manual hand actions (make eject / make rescan) live in
%% mk/features/System/Filesystem/system.mk.

service_check(backup_mount, Check, Fix) :-
    shell_ok("test -e /dev/disk/by-label/backup"),
    Check = "test -f /etc/systemd/system/mnt-backup.mount && test -f /etc/systemd/system/mnt-backup-chmod.service",
    Fix = "mkdir -p /mnt/backup && sed -i '\\|/mnt/backup|d' /etc/fstab && printf '%s\\n' '[Unit]' 'Description=NVMe backup drive (SN8100)' '' '[Mount]' 'What=/dev/disk/by-label/backup' 'Where=/mnt/backup' 'Type=ext4' 'Options=defaults,noatime,nofail' '' '[Install]' 'WantedBy=dev-disk-by\\x2dlabel-backup.device' > /etc/systemd/system/mnt-backup.mount && printf '%s\\n' '[Unit]' 'Description=Set /mnt/backup permissions on mount' 'After=mnt-backup.mount' 'Requires=mnt-backup.mount' '' '[Service]' 'Type=oneshot' 'ExecStart=/bin/chmod 1777 /mnt/backup' 'RemainAfterExit=yes' '' '[Install]' 'WantedBy=mnt-backup.mount' > /etc/systemd/system/mnt-backup-chmod.service && systemctl daemon-reload && systemctl enable mnt-backup.mount mnt-backup-chmod.service".
