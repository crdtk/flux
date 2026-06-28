HARDENING += \
  /etc/systemd/system/packagekit.service \
  /etc/sysctl.d/90-inotify.conf \
  /etc/apt/preferences.d/no-snapd \
  /etc/systemd/system/suspend.target \
  $(if $(HAS_NVIDIA),/etc/modprobe.d/blacklist-nouveau.conf,) \
  /etc/modprobe.d/blacklist-parport.conf \
  $(if $(HAS_NVIDIA),/etc/modprobe.d/nvidia-power.conf,)

/etc/systemd/system/packagekit.service:
	@rm -f /etc/apt/sources.list.d/jammy-backports.list; systemctl disable --now ollama touchegg 2>/dev/null || true; $(APT) purge -y ollama touchegg cockpit-packagekit 2>/dev/null || true; rm -f /usr/local/bin/ollama /etc/systemd/system/ollama.service; systemctl stop packagekit 2>/dev/null || true; systemctl mask packagekit; mkdir -p /etc/PackageKit; dpkg-divert --divert /etc/PackageKit/20packagekit.distrib --rename /etc/apt/apt.conf.d/20packagekit 2>/dev/null || true; systemctl daemon-reload && echo ">>> debloat complete"

/etc/sysctl.d/90-inotify.conf:
	@printf 'fs.inotify.max_user_watches=524288\n' > $@ && sysctl -p $@ && echo ">>> inotify watches: 524288"

/etc/apt/preferences.d/no-snapd:
	@mkdir -p $(dir $@); snap list --all 2>/dev/null | awk 'NR>1{print $$1}' | xargs -r snap remove --purge 2>/dev/null || true; $(APT) purge -y snapd 2>/dev/null || true; rm -rf /snap /var/snap /var/lib/snapd /var/cache/snapd ~/snap; printf 'Package: snapd\nPin: release *\nPin-Priority: -1\n' > $@ && echo ">>> snap purged and pinned out"

/etc/systemd/system/suspend.target:
	@systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target && echo ">>> Suspend disabled"

/etc/modprobe.d/blacklist-nouveau.conf:
	@printf 'blacklist nouveau\noptions nouveau modeset=0\n' > $@ && echo ">>> nouveau blacklisted"

/etc/modprobe.d/blacklist-parport.conf:
	@printf '# lp/parport crash kernel 7.0.0-22 NULL deref\nblacklist lp\nblacklist ppdev\nblacklist parport_pc\nblacklist parport\n' > $@ && echo ">>> parport/lp blacklisted"

/etc/modprobe.d/nvidia-power.conf:
	@printf 'options nvidia NVreg_PreserveVideoMemoryAllocations=1\noptions nvidia NVreg_TemporaryFilePath=/tmp\n' > $@ && echo ">>> NVIDIA power options set"

HAS_BMC  := $(shell dmidecode -t 38 2>/dev/null | grep -c 'IPMI Device Information')
HARDENING += /etc/systemd/system/openipmi.service

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

HARDENING += /etc/default/grub.d/99-timeout.cfg

/etc/default/grub.d/:
	mkdir -p $@

GRUB_TIMEOUT := 3
/etc/default/grub.d/99-timeout.cfg: | /etc/default/grub.d/
	@printf 'GRUB_TIMEOUT=$(GRUB_TIMEOUT)\n' > $@ && update-grub && echo ">>> GRUB timeout = $(GRUB_TIMEOUT)"

PAM_SSS_FILES := $(shell grep -rl pam_sss /etc/pam.d/ 2>/dev/null)
HARDENING     += $(if $(PAM_SSS_FILES),/etc/pam.d/.pam-sss-cleaned,)

/etc/pam.d/.pam-sss-cleaned:
	@grep -rl pam_sss /etc/pam.d/ 2>/dev/null | xargs -r sed -i '/pam_sss/d' && touch $@ && echo ">>> pam_sss removed from PAM"

# Sets the kernel ASPM policy off. NECESSARY BUT NOT SUFFICIENT on this board:
# firmware keeps ASPM control (_OSC denies the OS), so the L1 bits stay set and
# pcie_aspm=off is ignored. disable-gpu-aspm.service below does the real work.
HAS_PLX_SWITCH := $(shell lspci 2>/dev/null | grep -qiE "PLX.*PEX 87" && echo 1)
HARDENING      += \
  $(if $(HAS_PLX_SWITCH),/etc/default/grub.d/99-pcie-aspm.cfg,) \
  $(if $(HAS_PLX_SWITCH),/etc/systemd/system/disable-gpu-aspm.service,)

/etc/default/grub.d/99-pcie-aspm.cfg: | /etc/default/grub.d/
	@printf 'GRUB_CMDLINE_LINUX_DEFAULT="$$GRUB_CMDLINE_LINUX_DEFAULT pcie_aspm=off"\n' > $@ && update-grub && echo ">>> kernel ASPM off (firmware still owns L1)"

# Sets the kernel ASPM policy off. NECESSARY BUT NOT SUFFICIENT on this board:
# firmware keeps ASPM control (_OSC denies the OS), so the L1 bits stay set and
# pcie_aspm=off is ignored. disable-gpu-aspm.service below does the real work.
# define precedes PLX_ASPM_TARGETS: uses lazy expansion, parameters bound at recipe time.
define DISABLE_GPU_ASPM_UNIT
[Unit]
Description=Clear PCIe ASPM L1 on all PLX switch ports (upstream + downstream + GPU)
After=multi-user.target

[Service]
Type=oneshot
RemainAfterExit=yes
$(foreach b,$(PLX_ASPM_TARGETS),ExecStart=/usr/bin/setpci -s $(b) CAP_EXP+0x10.w=0:3
)
[Install]
WantedBy=multi-user.target
endef

PLX_UPSTREAM     := $(shell lspci -D 2>/dev/null | awk '/PLX.*PEX 87/{print $$1; exit}')
PLX_DOWNSTREAMS  := $(if $(PLX_UPSTREAM),$(shell ls /sys/bus/pci/devices/$(PLX_UPSTREAM)/ 2>/dev/null | grep '^0000:'))
PLX_GPU          := $(shell lspci -D 2>/dev/null | awk '/VGA.*NVIDIA/{print $$1}')
PLX_ASPM_TARGETS := $(PLX_UPSTREAM) $(PLX_DOWNSTREAMS) $(PLX_GPU)

# Real consequence (I): unit file written, setpci runs now via enable --now.
# Cleans up the old script file if upgrading from a previous version.
/etc/systemd/system/disable-gpu-aspm.service:
	$(file >$@,$(DISABLE_GPU_ASPM_UNIT))
	@rm -f /usr/local/sbin/disable-gpu-aspm && systemctl daemon-reload && systemctl enable --now disable-gpu-aspm.service && echo ">>> ASPM L1 cleared on all $(words $(PLX_ASPM_TARGETS)) switch ports"
