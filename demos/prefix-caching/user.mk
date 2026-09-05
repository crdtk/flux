# prefix-caching demo — three execution vehicles for one notebook:
# local Jupyter (demo-notebook, TurboQuant kernel installed into the
# single repo venv), Colab (colab-upload, via GitHub mirror), and Kaggle
# (kaggle-run, headless T4 with polled status + output download).
# Included by root Makefile's demos glob; $(UV) comes from
# Science/ComputerScience; single repo venv managed by root Makefile.

.PHONY: demo-notebook
demo-notebook: | $(VENV_PY)
	cd demos/prefix-caching && $(VENV)/bin/jupyter notebook prefix_caching_demo.ipynb

COLAB_NB     := demos/prefix-caching/prefix_caching_demo.ipynb
GITHUB_REPO  := crdtk/flux
COLAB_BRANCH := main

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
