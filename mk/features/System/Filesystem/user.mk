# User half of the disk cleanup (sensed 2026-08-14: tier 1 = regenerable
# caches ~10G, tier 2 = spent installers ~16G). Explicit literal paths
# only — no globs — so nothing outside this list can ever be touched.
# uv's cache goes through its own CLI (it keeps internal state).
DISK_CLEAN_USER := \
  $(USER_HOME)/.cache/google-chrome \
  $(USER_HOME)/.cache/drkonqi \
  $(USER_HOME)/Downloads/ubuntu-26.04-desktop-amd64.iso \
  $(USER_HOME)/Downloads/kubuntu-26.04-desktop-amd64.iso \
  $(USER_HOME)/Downloads/pycharm-2025.3 \
  $(USER_HOME)/Downloads/pycharm-2025.3.tar.gz \
  $(USER_HOME)/Downloads/LM-Studio-0.4.7-4-x64.deb \
  $(USER_HOME)/.local/share/whisper-venv \
  $(USER_HOME)/miniforge3 \
  $(USER_HOME)/snap
# whisper-venv/miniforge3: venvs are BUILDS — rebuildable on demand (uv
# owns environments now); ~/snap is a remnant of the purged snapd. The
# flatpak AusweisApp duplicated the POST-declared deb; uninstalling it
# frees its 2.6G of runtimes via --unused.
# ~/Pictures and ~/Desktop/Backup are family data — structurally
# untouchable: the build refuses if either ever enters a clean list.
$(if $(filter $(USER_HOME)/Pictures% $(USER_HOME)/Desktop/Backup%,$(DISK_CLEAN_USER)),$(error disk-clean: protected path in DISK_CLEAN_USER))

# Headless duplicate scan (czkawka_cli, POST-provisioned): same hash
# engine as the GUI, but writes a reviewable report instead of a
# freezable list. Overridable: make dup-report DUP_DIR=~/Music
DUP_DIR ?= $(USER_HOME)/Pictures
DUP_REPORT := /tmp/dup-report.txt

## Scan DUP_DIR for exact duplicates; report to /tmp/dup-report.txt.
.PHONY: dup-report
dup-report:
# exit 11 = "items found" (czkawka's success-with-results code), not an error
	czkawka_cli dup --directories "$(DUP_DIR)" --file-to-save "$(DUP_REPORT)" || test $$? -eq 11
	@echo ">>> report: $(DUP_REPORT)"

# venvs are BUILDS (rebuildable on demand — the disk-clean rule above),
# so a name-glob is safe here where data globs are not: the pyvenv.cfg
# guard means only real Python venvs match, never a folder merely
# named .venv. Depth-bounded to Desktop; report first, then clean.
VENV_REPORT := /tmp/venv-report.txt

## List every Python .venv under ~/Desktop with sizes (report only).
.PHONY: venv-report
venv-report:
	find $(USER_HOME)/Desktop -maxdepth 6 -type d -name '.venv' -prune | while read -r d; do \
	  test -f "$$d/pyvenv.cfg" && du -sh "$$d"; done | tee $(VENV_REPORT)

## Delete every .venv listed by venv-report (run that first to see).
.PHONY: venv-clean
venv-clean: venv-report
	cut -f2 $(VENV_REPORT) | xargs -r rm -rf --
	@df -h / | tail -1

## Delete LM Studio state (~/Desktop/.lmstudio) — refuses if the app is still installed.
.PHONY: lmstudio-clean
lmstudio-clean:
	@if command -v lmstudio >/dev/null || test -e $(USER_HOME)/.local/share/applications/lm-studio.desktop; then \
	  echo ">>> LM Studio still installed — not removing its state"; exit 1; fi
	rm -rf $(USER_HOME)/Desktop/.lmstudio
	@df -h / | tail -1

## Reclaim user-owned space: caches + spent installers (root half: sudo make disk-clean-root).
.PHONY: disk-clean
disk-clean:
	rm -rf $(DISK_CLEAN_USER)
	-uv cache clean
	-flatpak uninstall -y de.bund.ausweisapp.ausweisapp2; flatpak uninstall --unused -y
	@df -h / | tail -1
