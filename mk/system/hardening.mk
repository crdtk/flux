HAS_BMC       := $(shell dmidecode -t 38 2>/dev/null | grep -c 'IPMI Device Information')
GRUB_TIMEOUT  := 3
PAM_SSS_FILES := $(shell grep -rl pam_sss /etc/pam.d/ 2>/dev/null)

HARDENING += \
  /etc/systemd/system/packagekit.service \
  /etc/systemd/system/suspend.target \
  /etc/modprobe.d/blacklist-nouveau.conf \
  /etc/modprobe.d/blacklist-parport.conf \
  /etc/modprobe.d/nvidia-power.conf \
  /etc/systemd/system/openipmi.service \
  /etc/apt/preferences.d/no-snapd \
  /etc/sysctl.d/90-inotify.conf \
  /etc/default/grub.d/99-timeout.cfg \
  $(if $(PAM_SSS_FILES),fix-pam-sss,)

/etc/systemd/system/packagekit.service:
	rm -f /etc/apt/sources.list.d/jammy-backports.list
	systemctl disable --now ollama touchegg 2>/dev/null || true
	$(APT) purge -y ollama touchegg cockpit-packagekit 2>/dev/null || true
	rm -f /usr/local/bin/ollama /etc/systemd/system/ollama.service
	systemctl stop packagekit 2>/dev/null || true
	systemctl mask packagekit
	mkdir -p /etc/PackageKit
	dpkg-divert --divert /etc/PackageKit/20packagekit.distrib --rename /etc/apt/apt.conf.d/20packagekit 2>/dev/null || true
	systemctl daemon-reload
	@echo ">>> debloat complete"

/etc/sysctl.d/90-inotify.conf:
	printf 'fs.inotify.max_user_watches=524288\n' > $@
	sysctl -p $@
	@echo ">>> inotify watches set to 524288 (VS Code file watcher)"

/etc/apt/preferences.d/no-snapd:
	mkdir -p $(dir $@)
	snap list --all 2>/dev/null | awk 'NR>1{print $$1}' | xargs -r snap remove --purge 2>/dev/null || true
	$(APT) purge -y snapd 2>/dev/null || true
	rm -rf /snap /var/snap /var/lib/snapd /var/cache/snapd ~/snap
	printf 'Package: snapd\nPin: release *\nPin-Priority: -1\n' > $@
	@echo ">>> snap purged and pinned out"

/etc/systemd/system/suspend.target:
	systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
	@echo ">>> Suspend disabled"

define BLACKLIST_NOUVEAU
blacklist nouveau
options nouveau modeset=0
endef

/etc/modprobe.d/blacklist-nouveau.conf:
	$(file >$@,$(BLACKLIST_NOUVEAU))
	@echo ">>> nouveau blacklisted"

define BLACKLIST_PARPORT
# lp/parport crash kernel 7.0.0-22 with NULL deref in parport_register_dev_model
blacklist lp
blacklist ppdev
blacklist parport_pc
blacklist parport
endef

/etc/modprobe.d/blacklist-parport.conf:
	$(file >$@,$(BLACKLIST_PARPORT))
	@echo ">>> parport/lp blacklisted (kernel 7.0.0-22 NULL deref bug)"

define NVIDIA_POWER_CONF
options nvidia NVreg_PreserveVideoMemoryAllocations=1
options nvidia NVreg_TemporaryFilePath=/tmp
endef

/etc/modprobe.d/nvidia-power.conf:
	$(file >$@,$(NVIDIA_POWER_CONF))
	@echo ">>> NVIDIA power options set"

/etc/systemd/system/openipmi.service:
ifeq ($(HAS_BMC),0)
	@echo ">>> No BMC detected — masking and purging openipmi"
	systemctl mask openipmi
	apt purge -y openipmi 2>/dev/null || true
else
	@echo ">>> BMC detected — enabling openipmi"
	apt install -y openipmi
	systemctl enable --now openipmi
endif

/etc/default/grub.d/99-timeout.cfg:
	mkdir -p $(dir $@)
	printf 'GRUB_TIMEOUT=$(GRUB_TIMEOUT)\n' > $@
	update-grub
	@echo ">>> GRUB timeout = $(GRUB_TIMEOUT)"

.PHONY: fix-pam-sss
fix-pam-sss:
	grep -rl pam_sss /etc/pam.d/ 2>/dev/null | xargs -r sed -i '/pam_sss/d'
	@echo ">>> pam_sss removed from PAM"
