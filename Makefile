# ==========================================================
# Ubuntu Setup
# ==========================================================
#
# DESIGN PRINCIPLES — follow these when extending this file:
#
# NAMING
# 1.  Names declare why, not what.
# 2.  Two install paths, one truth — idempotency makes both safe.
# 3.  Grow by addition, not modification.
# 9.  Top-down: variables before use, dependents before prerequisites.
# 13. Single-use variables inline. Paths derive from parent variables.
#
# TARGETS
# 4.  Gate hardware at parse time. Named capability variables, no magic numbers.
# 5.  Targets are real files — no sentinels, no .PHONY for real outcomes.
# 6.  Bootstrapper dependencies are order-only — auto-updates must not rebuild.
# 10. .PHONY opens its section.
# 11. Outermost targets only — intermediates cascade.
# 15. Audit dead code. Shadowed rules and pre-built targets waste lines.
# 16. Order-only (|) voids $<. Reference paths explicitly in the recipe.
# 17. Multi-line content in define…endef. Emit with $(file >$@,$(VAR)).
# 18. Target the decision, not the payload — config enables the feature.
# 19. Any apt-file-mappable path earns a pattern rule, not an explicit recipe.
# 20. The cheapest target is the file the action creates anyway.
#
# PRIVILEGE
# 7.  Provisioning scope only — targets that change no state do not belong.
# 8.  One clean, privilege-branched. No sudo in recipes.
# 12. Name every shell subexpression. $$(…) not tied to $@ belongs above.
# 14. One privilege gate: IS_ROOT, computed once at parse time.
# 23. Packages via INSTALL gates only. Add to group, sudo make, done.
# 25. Prefer user-space installs. Escalate to root only when the path requires it.
#
# AUTOMATION
# 21. No nested $(MAKE). Protocol: make clean && make.
# 22. Automate, do not ask. Every manual step is a defect.
# 24. Stage across runs. make && make beats $(eval) every time.
#
# ==========================================================

MAKEFLAGS += --no-builtin-rules
.SUFFIXES:

IS_ROOT := $(filter 0,$(shell id -u))

.PHONY: all
all: $(if $(IS_ROOT),system,user)

# ----------------------------------------------------------
# Shared variables (referenced across all includes)
# ----------------------------------------------------------

APT             := DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=-1
USER_HOME       := $(shell getent passwd $${SUDO_USER:-$$(whoami)} | cut -d: -f6)
DOWNLOADS_DIR   := $(USER_HOME)/Downloads
UBUNTU_VER      := $(shell lsb_release -rs 2>/dev/null | tr -d '.')
UBUNTU_CODENAME := $(shell lsb_release -cs 2>/dev/null)
PLASMOIDS       := $(USER_HOME)/.local/share/plasma/plasmoids

# Accumulator seeds — must appear before includes so += works correctly
DEB_URLS   :=
PKG_APPS   :=
HARDENING  :=
MANAGEMENT :=
COMPUTE    :=
STORAGE    :=

# ----------------------------------------------------------
# Feature modules
# ----------------------------------------------------------

include mk/clean.mk
include mk/system/albert.mk
include mk/system/apps.mk
include mk/system/compute.mk
include mk/system/hardening.mk
include mk/system/management.mk
include mk/system/pycharm.mk
include mk/system/storage.mk
include mk/user/albert.mk
include mk/user/claude.mk
include mk/user/panels.mk
include mk/user/plasmoids.mk
include mk/user/references.mk

# ----------------------------------------------------------
# System target — computed after all includes accumulate lists
# ----------------------------------------------------------

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

# ----------------------------------------------------------
# Infrastructure — pattern rules and download target
# ----------------------------------------------------------

UNTRACKED_PKGS  := git avahi-daemon arp-scan nmap appmenu-gtk3-module appmenu-registrar
LAZILY_RESOLVED := syncthing npm mc libheif-examples gwenview ddclient cockpit cockpit-files \
                   cmake g++-14 rclone plasma-session-x11 flameshot gh plasma-widgets-addons

/usr/bin/apt-file: | /etc/systemd/system/packagekit.service
	$(APT) update
	$(APT) install -y apt-file $(UNTRACKED_PKGS) $(LAZILY_RESOLVED)
	apt-file update
	@echo ">>> apt-file ready"

## Resolve packages by Custom Repository URL
/usr/bin/%: /etc/apt/sources.list.d/%.list
	$(APT) update
	$(APT) install -y $*

## Resolve packages using apt-file global search
/usr/bin/%: | /usr/bin/apt-file
	$(APT) install -y $$(apt-file search $@ 2>/dev/null | awk -F': ' '{print $$1}' | head -1)

/usr/share/xsessions/%.desktop: | /usr/bin/apt-file
	$(APT) install -y $$(apt-file search $@ 2>/dev/null | awk -F': ' '{print $$1}' | head -1)

/usr/share/plasma/plasmoids/%/metadata.json: | /usr/bin/apt-file
	$(APT) install -y $$(apt-file search $@ 2>/dev/null | awk -F': ' '{print $$1}' | head -1)

$(DOWNLOADS_DIR)/%: | $(DOWNLOADS_DIR)
	curl -fL --retry 5 --retry-delay 3 --progress-bar -A "Mozilla/5.0" $(filter %/$*,$(DEB_URLS)) -o $@

$(DOWNLOADS_DIR):
	mkdir -p $@
