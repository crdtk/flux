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
#       (see III), then act on it in a dot-prefixed non-phony target. A sentinel is
#       a show of ignorance, not a workaround: if you cannot name the outcome, you
#       do not understand the action. An action without a traceable execution
#       consequence is madness.
# II.   IDEMPOTENCY & STAGING. Re-runs converge to one truth; the protocol is
#       `make clean && make | sudo bash` (make prints the POST plan — XXII).
#       Bootstrap deps are order-only so auto-updates never rebuild; multi-phase
#       work stages across runs.
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
# VIII. PRIVILEGE. No sudo inside recipes — a target either runs at the caller's
#       privilege or names the escalation explicitly in its documented invocation
#       (make agent-login). Prefer user-space, escalate only when the path demands it.
#       Package installation is POST's alone (XXI) — make recipes never apt.
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
# XIV.  CASCADE ORDERING. State the top-level requirement first, then resolve each
#       dependency one level deeper in the targets below. Targets appear from most
#       dependent to most foundational (dependents before prerequisites). No
#       intermediate variables for target paths — write the literal path where Make
#       tracks it. The cascade reads as a demand chain: "to build X, you need Y; to
#       build Y, you need Z."
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
#       specifications.freedesktop.org/menu — e.g. Settings/Panels, System/Filesystem).
#       Root and user actions live in system.mk and user.mk — privilege (VIII) stays
#       auditable as the filename. The top routers find-include every system.mk then
#       every user.mk at any depth, so adding a capability is dropping a directory —
#       no include edits (VI, XI). Since XXI, a feature module holds only what POST
#       cannot: timestamp-dependent builds and manual/destructive operations. Shared
#       variables live in the Makefile head, parsed before the globs.
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
# --- POST (post/post.pl, included via mk/post.mk) ---------
#
# XXI.  POST OWNS STATE. POST alone provisions, detects and repairs drift-state;
#       make keeps only what POST cannot express: timestamp-dependent builds
#       (venvs rebuilt when requirements.txt changes), inverses (clean, eject),
#       and interactive targets (agent-login). Every stateful outcome
#       the setup depends on earns a POST rule: an unprivileged, read-only,
#       cheap check probing the CONTENT that matters — an existence-only check
#       is a sentinel in the sense of I (a kwalletrc that existed but lacked
#       Enabled=false passed for weeks) — paired with an idempotent fix that
#       the next run re-verifies. Duplicating a POST-owned state in a make
#       recipe is a defect, not redundancy.
# XXII. PIPE IS ACCEPTANCE. stderr is the human-readable plan, stdout the fix
#       commands; nothing applies without `make | sudo bash`, and the human
#       pipes — never an agent (sudo is denied to agents in depth: sudoers
#       timestamp_timeout=0, Claude deny rule, ai-agent sandbox). Generation
#       runs unprivileged. Secrets come from the invoking environment
#       (TS_AUTHKEY, OPENCODE_ZEN_KEY): a rule gates on getenv and simply does
#       not exist without its key — keyless runs WARN where naming helps.
# XXIII. GATED FACTS, BACKTRACKED CHOICES. A conditional rule is a clause whose
#       body fails when inapplicable (has_nvidia, has_bmc): absent, not failing —
#       POST's form of III. Competing options (display managers, sessions) are
#       ranked candidates behind live viability probes: clause order is
#       preference, first survivor wins, losers stay standby-ready, every
#       demotion names its evidence. Never hardcode the winner.
# XXIV. HUMAN-ONLY STEPS WARN. A fix needing interaction (OAuth login, greeter
#       choice) is never emitted as a command — diagnose WARNs and names the make
#       target the human runs (make agent-login). Build-rule deps
#       are single-level, each goal declaring only its immediate predecessor —
#       the chain encodes causality, as XIV does for prerequisites.
# XXV.  FILE BY FATE. post/post.pl is the generic engine (sensing, diagnosis,
#       selection, planning, emission); all knowledge lives in
#       post/features/<arena>/<decision>.pl modules, loaded by glob — dropping a
#       file in adds a capability, deleting it revokes the decision. Arenas are
#       this build's own vocabulary (base, platform, net, desktop, dev, agents,
#       project), not an external ontology. A module is ONE revocable decision:
#       a fact lives with the decision whose reversal would delete it, so
#       "remove all X logic" touches at most one module. Ranked candidate/2
#       clauses of one domain never split across modules (clause order is rank);
#       story-local probes stay with their story, shared gates live in the
#       engine; a fact folds into its arena's tools module until it accretes a
#       gate or a second fact type.
#
# ==========================================================

MAKEFLAGS += --no-builtin-rules
.SUFFIXES:

# Default goal — declared before any include so `make` can never fall through
# to another target (clean.mk parses first). The recipe lives in mk/post.mk:
# `make` prints the POST plan, `make | sudo bash` applies it (XXII).
.PHONY: all
all:

# ----------------------------------------------------------
# Shared variables (referenced across all includes)
# ----------------------------------------------------------

USER_HOME       := $(shell getent passwd $${SUDO_USER:-$$(whoami)} | cut -d: -f6)
DOWNLOADS_DIR   := $(USER_HOME)/Downloads
UBUNTU_CODENAME := $(shell lsb_release -cs 2>/dev/null)
RUN_AS_USER     := $(or $(SUDO_USER),$(USER))

# ----------------------------------------------------------
# Modules. Provisioning and drift repair are POST's (XXI); the feature tree
# keeps only timestamp-dependent builds and manual/destructive operations.
# ----------------------------------------------------------

include mk/clean.mk
include $(shell find mk/features -name system.mk | sort)
include $(shell find mk/features -name user.mk | sort)
include mk/post.mk

COLAB_NB     := demos/prefix-caching/prefix_caching_demo.ipynb
GITHUB_REPO  := crdtk/flux
COLAB_BRANCH := main

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

# Bootstrap prerequisite (XVIII) — POST also converges this via user_tool(kaggle);
# the rule keeps kaggle-run self-sufficient on a box POST hasn't converged yet.
$(KAGGLE): | $(UV)
	$(UV) tool install kaggle

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
