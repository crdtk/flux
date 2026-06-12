include mk/system/albert.mk
include mk/system/apps.mk
include mk/system/compute.mk
include mk/system/hardening.mk
include mk/system/management.mk
include mk/system/pycharm.mk
include mk/system/storage.mk

.PHONY: system

COMPUTE_CAPABLE := $(shell [ -n "$(SYS_SM)" ] && [ "$(SYS_SM)" -ge 75 ] && echo 1)
SN8100_PRESENT  := $(shell test -e /dev/disk/by-label/backup && echo 1)

INSTALL := $(HARDENING) $(MANAGEMENT) $(PKG_APPS) \
           $(if $(COMPUTE_CAPABLE),$(COMPUTE),) \
           $(if $(SN8100_PRESENT),$(STORAGE),)
PENDING := $(filter-out $(wildcard $(INSTALL)),$(INSTALL))

system: $(PENDING)
	update-initramfs -u
	$(APT) autoremove
