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

## Reclaim user-owned space: caches + spent installers (root half: sudo make disk-clean-root).
.PHONY: disk-clean
disk-clean:
	rm -rf $(DISK_CLEAN_USER)
	-uv cache clean
	-flatpak uninstall -y de.bund.ausweisapp.ausweisapp2; flatpak uninstall --unused -y
	@df -h / | tail -1
