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
  $(USER_HOME)/Downloads/nixos-graphical-26.05.7675.02e08985a27c-x86_64-linux.iso \
  $(USER_HOME)/Downloads/CaptureScreen.jpeg \
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

## Reclaim user-owned space: caches + spent installers (root half: sudo make disk-clean-root).
.PHONY: disk-clean
disk-clean:
	rm -rf $(DISK_CLEAN_USER)
	-uv cache clean
	-flatpak uninstall -y de.bund.ausweisapp.ausweisapp2; flatpak uninstall --unused -y
	@df -h / | tail -1

# Chronological photo filing — the 2026-08-16 laptop sweep (4433 files),
# encoded so crucible runs the identical procedure. Two passes, both
# NON-recursive (only loose files at the Pictures root move; the YYYY/MM
# tree is never re-touched): EXIF date first (DateTimeOriginal wins over
# CreateDate — it names capture, not file creation), then a filename-date
# fallback for EXIF-less media (WhatsApp IMG-YYYYMMDD-*, screenshots,
# YYYYMMDD_HHMMSS.mp4). mv -n: a name collision leaves the file loose
# and reported rather than overwriting. Leftovers print at the end —
# an empty list is the pass. digiKam needs a rescan afterwards.
PICS_DIR := $(USER_HOME)/Pictures
PICS_EXT := -ext jpg -ext jpeg -ext png -ext heic -ext heif -ext gif \
  -ext webp -ext bmp -ext tif -ext tiff -ext dng \
  -ext mp4 -ext mov -ext avi -ext 3gp -ext mts -ext m4v -ext webm

## File loose media at ~/Pictures root into YYYY/MM (EXIF date, filename fallback).
.PHONY: pics-organize
pics-organize:
	@command -v exiftool >/dev/null || { echo ">>> exiftool missing — run the POST first"; exit 1; }
# exiftool exits nonzero for files it cannot date; those are exactly what
# the fallback pass is for — continue, never mask the messages.
	-exiftool $(PICS_EXT) '-Directory<CreateDate' '-Directory<DateTimeOriginal' \
	  -d '$(PICS_DIR)/%Y/%m' $(PICS_DIR)
	@cd $(PICS_DIR) && for f in *.*; do \
	  test -f "$$f" || continue; \
	  d=$$(echo "$$f" | grep -oE '20[0-9]{6}' | head -1); test -n "$$d" || continue; \
	  y=$$(echo "$$d" | cut -c1-4); m=$$(echo "$$d" | cut -c5-6); \
	  test "$$m" -ge 01 -a "$$m" -le 12 2>/dev/null || continue; \
	  mkdir -p "$$y/$$m" && mv -n -- "$$f" "$$y/$$m/" && echo "filed $$f -> $$y/$$m/"; \
	done
	@echo ">>> media leftovers at $(PICS_DIR) root (no date found — file by hand):"
# only media counts as a leftover — digiKam's DBs live at the root by design
	@cd $(PICS_DIR) && ls -p | grep -iE '\.(jpe?g|png|hei[cf]|gif|webp|bmp|tiff?|dng|mp4|mov|avi|3gp|mts|m4v|webm)$$' || echo "(none)"
