# ==========================================================
# Ubuntu Setup
# ==========================================================
#
# DESIGN PRINCIPLES — a constitution, foundational → mechanical. Follow when extending.
#
# I.    REAL CONSEQUENCES. Every recipe must produce a real, measurable consequence
#       — a file written, a setting applied, a port open, any state that can be
#       independently verified. A file is the form Make tracks natively (see V). For
#       non-file outcomes, sense the condition into a gated variable at parse time
#       (see III), then act on it in a dot-prefixed non-phony target inserted into
#       the system: or user: flow. A sentinel is a show of ignorance, not a
#       workaround: if you cannot name the outcome, you do not understand the action.
#       An action without a traceable execution consequence is madness.
# II.   IDEMPOTENCY & STAGING. Re-runs converge to one truth; the protocol is
#       `make clean && make`. Bootstrap deps are order-only so auto-updates never
#       rebuild; multi-phase work stages across runs.
# III.  DECIDE AT PARSE TIME. Sense capability into named variables — no magic
#       numbers. Gate the decision, not the payload. What the makefile installs is
#       the source of truth — derive config from it, never re-sense runtime.
# IV.   RESILIENCE & AUTOMATION. Automate every step (a manual step is a defect).
#       Never exit — sense, act, warn, continue. If the recipe copes with absence,
#       don't also gate it.
# V.    TARGETS ARE THE REAL FILE. Make the target the file the action creates. For
#       non-file outcomes (service running, config applied, port open), sense the
#       condition into a gated variable (see III) and use a dot-prefixed non-phony
#       target — dot targets are fileless so Make always re-evaluates them, the gate
#       makes them a no-op when the condition is already met. Reserve explicit .PHONY
#       for named aggregate actions (system, user, clean).
# VI.   MAP, DON'T ENUMERATE. An apt-file-mappable path earns a `%` pattern rule, not
#       an explicit recipe. A per-item action is $(foreach) building the target list
#       + one `%` rule — never $(eval) or a shell `for`.
# VII.  DEPENDENCY SHAPE. Expose only outermost targets; intermediates cascade.
#       Order-only (|) voids $< — reference paths explicitly.
# VIII. PRIVILEGE. One IS_ROOT gate at parse time; no sudo inside recipes (branch
#       instead). Prefer user-space, escalate only when the path demands it. Packages
#       enter only through INSTALL gates. Provisioning scope only — no stateless targets.
# IX.   VARIABLE LOCALITY. Define each variable just above and before its first use;
#       name every shell subexpression; inline single-use values, derive paths from
#       parents. A := accumulator expands += immediately, so a derived append follows
#       its inputs, in a later-parsed include.
# X.    CONTENT & LAYOUT. Multi-line content lives in define…endef, emitted with
#       $(file >$@,$(VAR)). .PHONY opens its section.
# XI.   HYGIENE. Names declare why, not what; grow by addition, not modification;
#       audit dead code — shadowed and pre-built rules waste lines.
# XII.  RIGHT TOOL. Use CLI specialists over general-purpose interpreters for
#       single operations: jq for JSON, xmllint for XML, awk/sed for text.
#       Spawning python3 for a jq-expressible operation is an avoidable
#       dependency and a readability cost.
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

COLAB_NB     := demos/prefix-caching/prefix_caching_demo.ipynb
GITHUB_REPO  := crdtk/flux
COLAB_BRANCH := main

UV       := $(USER_HOME)/.local/bin/uv
VENV     := $(CURDIR)/.venv
VENV_PY  := $(VENV)/bin/python3
VENV_PIP  = VIRTUAL_ENV=$(VENV) $(UV) pip install

TQ_KERNEL := $(USER_HOME)/.local/share/jupyter/kernels/turboquant/kernel.json

$(VENV_PY): | $(UV)
	$(UV) venv $(VENV) --python 3.12
	@echo ">>> venv at $(VENV) (python 3.12)"

$(TQ_KERNEL): $(VENV_PY)
	$(VENV_PIP) ipykernel jupyter
	$(VENV_PY) -m ipykernel install --user --name turboquant --display-name "TurboQuant"
	@echo ">>> TurboQuant kernel ready"

.PHONY: demo-notebook
demo-notebook: | $(TQ_KERNEL)
	cd demos/prefix-caching && $(VENV)/bin/jupyter notebook prefix_caching_demo.ipynb

.PHONY: demo-clean
demo-clean:
	rm -rf $(USER_HOME)/.local/share/jupyter/kernels/turboquant

.PHONY: colab-upload
colab-upload: $(COLAB_NB)
	git push origin $(COLAB_BRANCH)
	xdg-open "https://colab.research.google.com/github/$(GITHUB_REPO)/blob/$(COLAB_BRANCH)/$(COLAB_NB)"
	@echo ">>> https://colab.research.google.com/github/$(GITHUB_REPO)/blob/$(COLAB_BRANCH)/$(COLAB_NB)"
