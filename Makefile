# ==========================================================
# Ubuntu Setup
# ==========================================================
#
# DESIGN PRINCIPLES — a constitution, foundational → mechanical. Follow when extending.
#
# I.    IDEMPOTENCY & STAGING. Re-runs converge to one truth; the protocol is
#       `make clean && make`. Bootstrap deps are order-only so auto-updates never
#       rebuild; multi-phase work stages across runs.
# II.   DECIDE AT PARSE TIME. Sense capability into named variables — no magic
#       numbers. Gate the decision, not the payload. What the makefile installs is
#       the source of truth — derive config from it, never re-sense runtime.
# III.  RESILIENCE & AUTOMATION. Automate every step (a manual step is a defect).
#       Never exit — sense, act, warn, continue. If the recipe copes with absence,
#       don't also gate it.
# IV.   TARGETS ARE THE REAL FILE. Make the target the file the action creates. For
#       a transient action with no file (pinhole, mount, auth, in-place edit), use a
#       NON-phony, fileless target that re-runs — not .PHONY, which a pattern rule
#       skips. Reserve explicit .PHONY for named aggregate actions; sentinels last.
# V.    MAP, DON'T ENUMERATE. An apt-file-mappable path earns a `%` pattern rule, not
#       an explicit recipe. A per-item action is $(foreach) building the target list
#       + one `%` rule — never $(eval) or a shell `for`.
# VI.   DEPENDENCY SHAPE. Expose only outermost targets; intermediates cascade.
#       Order-only (|) voids $< — reference paths explicitly.
# VII.  PRIVILEGE. One IS_ROOT gate at parse time; no sudo inside recipes (branch
#       instead). Prefer user-space, escalate only when the path demands it. Packages
#       enter only through INSTALL gates. Provisioning scope only — no stateless targets.
# VIII. VARIABLE LOCALITY. Define each variable just above and before its first use;
#       name every shell subexpression; inline single-use values, derive paths from
#       parents. A := accumulator expands += immediately, so a derived append follows
#       its inputs, in a later-parsed include.
# IX.   CONTENT & LAYOUT. Multi-line content lives in define…endef, emitted with
#       $(file >$@,$(VAR)). .PHONY opens its section.
# X.    HYGIENE. Names declare why, not what; grow by addition, not modification;
#       audit dead code — shadowed and pre-built rules waste lines.
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
DISPLAY_CONFIG :=
USER_FILES :=

# ----------------------------------------------------------
# Feature modules
# ----------------------------------------------------------

include mk/clean.mk
include mk/display.mk
include mk/system/system.mk
include mk/user/user.mk

# ----------------------------------------------------------
# Infrastructure — pattern rules and download target
# ----------------------------------------------------------

UNTRACKED_PKGS  := git avahi-daemon arp-scan nmap appmenu-gtk3-module appmenu-registrar python3-venv
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
