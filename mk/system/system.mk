KUBUNTU_BACKPORTS_LIST := /etc/apt/sources.list.d/kubuntu-ppa-ubuntu-backports-$(UBUNTU_CODENAME).sources

$(KUBUNTU_BACKPORTS_LIST):
	add-apt-repository -y ppa:kubuntu-ppa/backports

/usr/share/applications/%.desktop:
	test -f $@ || $(APT) install -y --reinstall $(DESKTOP_PKG_$*)
	sed -i 's|^\(Exec=[^ ]*\)|\1 $(DESKTOP_FLAGS_$*)|g' $@

include mk/system/audiovideo/audiovideo.mk
include mk/system/development/development.mk
include mk/system/graphics/graphics.mk
include mk/system/network/network.mk
include mk/system/settings/settings.mk
include mk/system/utility/utility.mk
include mk/system/compute.mk
include mk/system/hardening.mk
include mk/system/management.mk
include mk/system/storage.mk
include mk/system/tailscale.mk

.PHONY: system

COMPUTE_CAPABLE := $(shell [ -n "$(SYS_SM)" ] && [ "$(SYS_SM)" -ge 75 ] && echo 1)
SN8100_PRESENT  := $(shell test -e /dev/disk/by-label/backup && echo 1)

INSTALL := $(HARDENING) $(MANAGEMENT) $(PKG_APPS) $(DISPLAY_CONFIG) \
           $(if $(COMPUTE_CAPABLE),$(COMPUTE),) \
           $(if $(SN8100_PRESENT),$(STORAGE),)
PENDING := $(filter-out $(wildcard $(INSTALL)),$(INSTALL))

system: $(PENDING)
	update-initramfs -u
	$(APT) autoremove
