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
#       + one `%` rule — never $(eval) or a shell `for`. Per-item decomposition also
#       dissolves quoting/escaping: one trivial artifact per item (a single plain
#       command) has no loop → no pipeline → no nested quotes → no escaping. When an
#       embedded pipeline demands escape gymnastics, decompose — don't escape harder.
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
# XIII. STRUCTURED OUTPUT FIRST. Before scraping a command's human-readable text, vet it
#       for a structured mode (--json, -j, --format=json) and parse that with jq (XII).
#       Check every new command on adoption — text-scraping (awk/sed on colorized output,
#       ANSI-stripping) is the fallback, never the first reach.
# XIV.  CASCADE ORDERING. State the top-level requirement first (MANAGEMENT += /path),
#       then resolve each dependency one level deeper in the targets below. Only
#       leaf requirements go into accumulator variables — if target Y exists solely
#       as a prerequisite of target X, and X is already in MANAGEMENT, then Y must
#       not also appear in MANAGEMENT (Make resolves Y through X's dependency chain).
#       Targets appear from most dependent to most foundational (dependents before
#       prerequisites, enforced by p9). No intermediate variables for target paths
#       — write the literal path where Make tracks it. The cascade reads as a demand
#       chain: "to build X, you need Y; to build Y, you need Z."
# XV.   COMMENT SCOPE. Module headers describe what that module does — not how.
#       General conventions (ordering, naming, privilege) are stated once in this
#       constitution and referenced by number (e.g. "XIV") in module comments when
#       a specific application of a principle needs a footnote. Avoid restating the
#       principle itself.
# XVI.  COMPOSE, DON'T BRANCH. Prefer Make's functional forms ($(if ...), $(or ...),
#       $(foreach ...), $(filter ...)) over imperative control-flow directives
#       (ifneq/endif, ifdef/endif). A conditional should yield a value, not gate a
#       block. Functional forms are shorter, composable at the expression level, and
#       keep variable definitions as single-line declarations rather than multi-line
#       sections.
# XVII. FEATURE MODULES. One capability per directory, classified by the freedesktop.org
#       menu taxonomy: mk/features/<MainCategory>/<AdditionalCategory>/ (see
#       specifications.freedesktop.org/menu — e.g. Network/RemoteAccess, Development/IDE,
#       System/Security). An Additional category may nest a specific application one
#       level deeper (Development/IDE/VS-Code/), each app a leaf with its own
#       system.mk/user.mk. Its root and user artifacts live in system.mk and user.mk —
#       privilege (VIII) stays auditable as the filename: "what runs as root" is every
#       system.mk. The top routers find-include every system.mk then every user.mk at
#       any depth (Main/Additional, optionally /App, /App/Variant), so adding a
#       capability is dropping a directory — no include edits (VI, XI). A
#       single-privilege feature has only one of the two files; a feature's extra parts
#       are included by its own entry file. Cross-feature infrastructure lives in
#       mk/common.mk (parsed before the globs); mk/aggregate.mk (parsed after) rolls the
#       accumulators into the system:/user: targets. The intra-feature contract (shared
#       path/var) is declared in its system.mk, which the user glob sees because
#       */*/system.mk parses first.
# XVIII. INVARIANTS AS PREREQUISITES. A file that must exist for a target to be correctly
#       deployed — not just present, but safe and complete — is a prerequisite of that
#       target, not an independent accumulator entry. Accumulator entries declare
#       independent capabilities; prerequisites declare invariants. If removing Y would
#       leave X broken or unsafe, Y belongs on X's prerequisite line, not in the
#       accumulator.
# XIX.  THERE IS NOWHERE BEYOND. The Makefile is the only interface; this directory is
#       its boundary. Solutions live in `make <target>` — never in standalone scripts
#       or entry points installed outside this tree. The Makefile may write system
#       configuration (sudoers, services, modprobe) and packages to system paths —
#       that is its job. It must not install workflow artifacts (wrappers, launchers,
#       convenience scripts) whose sole purpose is making a make target callable from
#       elsewhere. When something needs to be callable from anywhere, emit a shell
#       alias into ~/.bashrc via a make target. Do not reach beyond.
# XX.   SIMPLEST RECIPE FIRST. A recipe is one bash command until there is a demonstrated
#       reason for two. No wrappers, no indirection, no helper files, no intermediate
#       variables unless the problem demands them. Complexity must be justified by a
#       concrete failure of the simpler form — not by anticipating one.
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
PROJECTS        := $(USER_HOME)/Desktop/Projects
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
include mk/common.mk
include $(shell find mk/features -name system.mk | sort)
include $(shell find mk/features -name user.mk | sort)

# ----------------------------------------------------------
# Privilege roll-up — parsed after every feature module so the accumulators
# (HARDENING/MANAGEMENT/PKG_APPS/DISPLAY_CONFIG/COMPUTE/STORAGE, USER_FILES) are
# complete. Branches of the IS_ROOT gate (VIII): `system` builds root artifacts,
# `user` builds the user's. Capability senses (SYS_SM, GPU_BDF, SN8100) come from the
# features that own them — defined before this file by the feature globs.
# ----------------------------------------------------------

# ---- system (root) ----
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

# ---- user (non-root) ----
.PHONY: user

USER_PENDING := $(filter-out $(wildcard $(USER_FILES)),$(USER_FILES))

user:: $(USER_PENDING) \
    configure-top-panel \
    configure-bottom-panel
	/usr/bin/kbuildsycoca6
	@systemctl --user reset-failed plasma-plasmashell.service 2>/dev/null || true
	@systemctl --user restart plasma-plasmashell.service 2>/dev/null || true
	@echo ">>> plasmashell restarted — system tray indicators (keyboard layout, volume, etc.) will auto-populate"
	@[ -z "$(GPU_BDF)" ] || echo ">>> GPU $(GPU_BDF) PCIe link: $$(cat /sys/bus/pci/devices/$(GPU_BDF)/current_link_speed) x$$(cat /sys/bus/pci/devices/$(GPU_BDF)/current_link_width) (want 8.0 GT/s x4; 2.5 GT/s = reseat/swap cable)"
	@echo
	@echo "=== Tailscale Status ==="
	@tailscale status 2>/dev/null || echo "NOT CONNECTED"
	@echo
	@echo "=== Interface ==="
	@ip addr show tailscale0 2>/dev/null | awk '/inet /{print "  IP: " $$2}' || echo "  No tailscale0 interface"
	@echo
	@echo "=== Peers ==="
	@tailscale status 2>/dev/null | awk 'NR>1{print "  " $$0}' | head -5 || echo "  No peers"

# ----------------------------------------------------------
# Infrastructure — pattern rules and download target
# ----------------------------------------------------------

UNTRACKED_PKGS  := git avahi-daemon arp-scan nmap appmenu-gtk3-module appmenu-registrar pciutils dmidecode
LAZILY_RESOLVED := syncthing npm mc libheif-examples gwenview cockpit cockpit-files \
                   rclone plasma-session-x11 flameshot gh plasma-widgets-addons xclip

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

KAGGLE_SLUG    := prefix-caching-demo
KAGGLE_META    := demos/prefix-caching/kernel-metadata.json
KAGGLE_KERNEL  := demos/prefix-caching/.kaggle-kernel
KAGGLE_OUT_DIR := demos/prefix-caching/output
KAGGLE         := $(USER_HOME)/.local/bin/kaggle

# KAGGLE_USERNAME / KAGGLE_API_TOKEN come from the environment (Make auto-imports env
# vars). kaggle-run checks they're set and errors clearly if not.

define KAGGLE_META_JSON
{"id":"$(KAGGLE_USERNAME)/$(KAGGLE_SLUG)","title":"Prefix Caching Demo","code_file":"prefix_caching_demo.ipynb",
 "language":"python","kernel_type":"notebook","is_private":true,
 "enable_gpu":true,"enable_internet":true,
 "dataset_sources":[],"competition_sources":[],"kernel_sources":[]}
endef

$(KAGGLE_META):
	@test -n "$(KAGGLE_USERNAME)"  || { echo ">>> KAGGLE_USERNAME not set";  exit 1; }
	@test -n "$(KAGGLE_API_TOKEN)" || { echo ">>> KAGGLE_API_TOKEN not set"; exit 1; }
	@mkdir -p $(dir $@)
	$(file >$@,$(KAGGLE_META_JSON))
	@echo ">>> $@ written"

$(KAGGLE_KERNEL): $(COLAB_NB) $(KAGGLE_META) | $(KAGGLE)
	@export KAGGLE_API_TOKEN="$(KAGGLE_API_TOKEN)"; \
	PUSH=$$($(KAGGLE) kernels push -p demos/prefix-caching 2>&1); echo "$$PUSH"; \
	KERNEL=$$(echo "$$PUSH" | grep -oP 'kaggle\.com/\K\S+'); \
	[ -n "$$KERNEL" ] || { echo ">>> push failed — check output above"; exit 1; }; \
	echo "$$KERNEL" > $@

.PHONY: kaggle-run
kaggle-run: $(KAGGLE_KERNEL) | $(KAGGLE)
	@export KAGGLE_API_TOKEN="$(KAGGLE_API_TOKEN)"; \
	KERNEL=$$(cat $(KAGGLE_KERNEL)); \
	xdg-open "https://www.kaggle.com/$$KERNEL"; \
	echo ">>> kernel queued — polling every 30s (typically 5–10 min on T4)"; \
	STATUS=""; \
	until [ "$$STATUS" = "complete" ] || [ "$$STATUS" = "error" ]; do \
	  STATUS=$$($(KAGGLE) kernels status $$KERNEL 2>/dev/null | tail -1 | awk '{print $$NF}'); \
	  printf "  [%s] %s\n" "$$(date +%H:%M:%S)" "$$STATUS"; \
	  [ "$$STATUS" != "complete" ] && [ "$$STATUS" != "error" ] && sleep 30; \
	done; \
	[ "$$STATUS" = "error" ] && { echo ">>> kernel failed — https://www.kaggle.com/$$KERNEL"; exit 1; }; \
	mkdir -p $(KAGGLE_OUT_DIR); \
	$(KAGGLE) kernels output $$KERNEL -p $(KAGGLE_OUT_DIR); \
	echo ">>> output → $(KAGGLE_OUT_DIR)/"

# ----------------------------------------------------------
# LLM-Intensive Applications demo — local Qwen3.5-0.8B, no cloud GPU.
# Runs in the central venv ($(VENV)) on the TurboQuant kernel. qwen3_5_kv.py is a
# local module, so papermill executes with --cwd in the demo dir; -k overrides the
# notebook's own kernelspec. The notebook self-installs tokenizers/hf_hub/safetensors,
# but they're added here too so the first run isn't slowed by pip.
# ----------------------------------------------------------

LLMI_DIR  := demos/llm-intensive-applications
LLMI_OUT  := $(LLMI_DIR)/llm_intensive_demo.out.ipynb

RASCHKA_SRC   := /home/m/Desktop/Projects/LLMs-from-scratch
RASCHKA_LINK  := demos/LLMs-from-scratch
RASCHKA_QWEN  := $(RASCHKA_LINK)/ch05/16_qwen3.5/qwen3_5_transformers.py

# HF_TOKEN for authenticated downloads — optional, from the environment.

# Symlink to the existing Raschka checkout at $(RASCHKA_SRC), then fetch upstream so
# ch05/16_qwen3.5/qwen3_5_transformers.py (imported by qwen3_5_kv.py) is available.
$(RASCHKA_QWEN):
	@test -L $(RASCHKA_LINK) || ln -s $(RASCHKA_SRC) $(RASCHKA_LINK)
	cd $(RASCHKA_SRC) && git fetch --depth 1 origin && git checkout origin/main -- ch05/16_qwen3.5/
	@echo ">>> ready: $@"

# Headless papermill execution via uv run (auto-resolves deps). --log-output streams
# each cell's stdout/stderr to the console; the executed notebook is the durable record.
# -k overrides the notebook's kernelspec; --cwd makes qwen3_5_kv.py importable.
.PHONY: llm-intensive-demo
llm-intensive-demo: $(RASCHKA_QWEN)
	HF_TOKEN=$(HF_TOKEN) \
	LD_LIBRARY_PATH=$(HOME)/Desktop/.lmstudio/extensions/backends/vendor/linux-llama-cuda12-vendor-v1:$$LD_LIBRARY_PATH \
	$(UV) run \
	  --with torch --with tokenizers --with huggingface_hub --with safetensors \
	  --with papermill --with flash-linear-attention --with causal-conv1d \
	  papermill --log-output \
	  $(LLMI_DIR)/llm_intensive_demo.ipynb $(LLMI_OUT) -k turboquant --cwd $(LLMI_DIR)
	@echo ">>> executed → $(LLMI_OUT)"
