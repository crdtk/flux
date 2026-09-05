# Network/RemoteAccess — everything that reaches the rig (crucible) from
# this laptop: file sync (rsync, git-excluded), checksum verification,
# out-of-band power (BMC/IPMI with TPM-sealed credential, Wake-on-LAN),
# and remote POST convergence. Manual operations only — drift is POST's.

# ----------------------------------------------------------
# Manual one-shot file sync with the rig, nondestructive by design:
# -a keeps metadata, -u never overwrites anything newer on the
# receiving side, and no --delete exists here. --info=progress2 shows
# one whole-transfer progress bar. Projects/flux is excluded — the repo
# syncs via git (origin is the peer clone). DIR picks the subtree.
# ----------------------------------------------------------

SYNC_DIR  ?= Desktop
# Empty SYNC_DIR would expand the remote side to `crucible.local:/` —
# the rig's ROOT — so it collapses to `.` (home), which is also the
# supported way to sync at home level: make sync-push SYNC_DIR=.
SYNC_PATH  = $(if $(SYNC_DIR),$(SYNC_DIR),.)
# Git working trees living on BOTH machines sync via git, never rsync:
# file-level newest-wins interleaves two clones into a tree no commit
# describes, and mixing .git internals corrupts the repo. Excluded by
# NAME (unanchored), so the patterns hold at any depth and under any
# SYNC_DIR scope. Union of `find -name .git` on serval + crucible,
# 2026-08-09 — a new repo cloned to both machines must be added here.
# Machine-identity excludes make home-level safe: each machine keeps
# its own ssh keypair (peer auth depends on it), Claude credentials,
# Syncthing device id, gnupg, and cache. Downloads syncs deliberately:
# a LAN copy is cheaper than a fresh download.
# --no-owner --no-group: ownership is per-machine identity; non-root
# rsync cannot chgrp what the user does not own (a root-owned leftover
# under $HOME failed the first pull with error 23).
SYNC_EXCLUDES := \
             --exclude=flux --exclude=Crucible \
             --exclude=LLMs-from-scratch --exclude=secrets \
             --exclude=bert-size-reco --exclude=gehaltsabrechnung \
             --exclude=.ssh --exclude=.gnupg --exclude=.claude \
             --exclude=.config/syncthing --exclude=.cache
SYNC      := rsync -auh --no-owner --no-group --info=progress2 $(SYNC_EXCLUDES)

.PHONY: sync-push
sync-push:
	$(SYNC) $(USER_HOME)/$(SYNC_PATH)/ crucible.local:$(SYNC_PATH)/

.PHONY: sync-pull
sync-pull:
	$(SYNC) crucible.local:$(SYNC_PATH)/ $(USER_HOME)/$(SYNC_PATH)/

# Both directions in one go, at HOME level, skipping hidden entries at
# the home root (anchored /.* — dotfiles deeper down, like a project's
# .git, still sync). Newest copy wins on both sides, nothing deleted.
# Target-specific vars propagate to the two prerequisite legs.
.PHONY: sync
sync: SYNC_DIR = .
sync: SYNC += --exclude=/.*
sync: sync-push sync-pull

# Read-only proof that every local file exists BYTE-IDENTICAL on the rig:
# -n never writes, -c reads and checksums both sides (slow = honest —
# mtime/size alone can lie after tool-driven moves). Per-machine digiKam
# DBs are excluded (deliberately .stignore'd, never expected remotely).
# Report lines: `<f+++++++++` = missing on crucible, `<fc...` = content
# differs; an empty report is the pass.
SYNC_VERIFY_REPORT := /tmp/sync-verify.txt

## Checksum-verify local files against crucible (no writes): make sync-verify SYNC_DIR=Pictures
.PHONY: sync-verify
sync-verify:
	rsync -rnc --itemize-changes --out-format='%i %n' \
	  $(SYNC_EXCLUDES) \
	  --exclude='digikam4*.db' --exclude='recognition*.db' \
	  --exclude='similarity*.db' --exclude='thumbnails-digikam*.db' \
	  --exclude='.sync*' --exclude='*.sync-conflict-*' \
	  $(USER_HOME)/$(SYNC_PATH)/ crucible.local:$(SYNC_PATH)/ \
	  | grep -v '^\.d\|^cd' | tee $(SYNC_VERIFY_REPORT); \
	if test -s $(SYNC_VERIFY_REPORT); then \
	  echo ">>> $$(wc -l < $(SYNC_VERIFY_REPORT)) file(s) missing or different on crucible — $(SYNC_VERIFY_REPORT)"; \
	else echo ">>> PASS: every local file under $(SYNC_PATH) is byte-identical on crucible"; fi

# Out-of-band rig power via the always-on BMC (ASRock Rack, .23; the OS
# rides .24). The password is TPM-sealed on this laptop (make bmc-enroll):
# ciphertext at rest in /etc/credstore.encrypted, decryptable only by
# this machine's TPM, plaintext existing nowhere — not in history, ps
# (-E reads $IPMI_PASSWORD from the environment), files, or transcripts.
# Env IPMI_PASSWORD still works as the no-TPM fallback.
BMC_HOST ?= 192.168.178.23
BMC_USER ?= admin
BMC_CRED := /etc/credstore.encrypted/crucible-bmc.cred
IPMI      = ipmitool -I lanplus -H $(BMC_HOST) -U $(BMC_USER) -E
# Decrypt needs root (TPM access) — hence sudo on the credential path.
IPMI_RUN  = if test -f $(BMC_CRED); then \
	      IPMI_PASSWORD=$$(sudo systemd-creds decrypt $(BMC_CRED) -) $(IPMI) $(1); \
	    elif test -n "$$IPMI_PASSWORD"; then $(IPMI) $(1); \
	    else echo ">>> no TPM credential ($(BMC_CRED)) and no IPMI_PASSWORD in env — run: make bmc-enroll"; exit 1; fi

## One-time: seal the BMC password to this laptop's TPM (typed silently, stored as ciphertext).
.PHONY: bmc-enroll
bmc-enroll:
	@sudo mkdir -p /etc/credstore.encrypted
	@printf 'BMC password for %s (input hidden): ' $(BMC_HOST); \
	  IFS= read -rs pw; echo; \
	  printf '%s' "$$pw" | sudo systemd-creds encrypt --name=crucible-bmc - $(BMC_CRED)
	@sudo systemd-creds decrypt $(BMC_CRED) - >/dev/null && echo ">>> sealed and decrypt-verified: $(BMC_CRED)"

## Power on the rig via BMC (TPM credential, or IPMI_PASSWORD env fallback).
.PHONY: rig-on
rig-on:
	@$(call IPMI_RUN,power status)
	@$(call IPMI_RUN,power on)

## Rig power state via BMC.
.PHONY: rig-status
rig-status:
	@$(call IPMI_RUN,power status)

# Wake-on-LAN: password-free power-on. Needs the rig-side POST rule
# (wol_magic_packet) to have armed the NIC, plus one BIOS setting
# (see rig-wake fence message). RIG_MAC is the OS NIC, not the BMC's
# 9c:6b:00:47:28:34 — sensed from the Fritz!Box device table 2026-08-17
# (.24 = :19 is the ssh port; its twin .25 = :1a is the second X550 port).
RIG_MAC ?= 9c:6b:00:48:57:19

## Sense the rig's wired MAC over ssh (rig must be up) and print the line to persist.
.PHONY: rig-mac
rig-mac:
	@mac=$$(ssh crucible.local "ip -o link show \$$(ip -o route get 1.1.1.1 | sed 's/.* dev \\([^ ]*\\).*/\\1/')" | grep -o 'ether [0-9a-f:]*' | cut -d' ' -f2); \
	test -n "$$mac" && echo ">>> paste into Makefile: RIG_MAC ?= $$mac" || { echo ">>> could not sense — is the rig up?"; exit 1; }

## Power on the rig with a WoL magic packet (no password): make rig-wake
.PHONY: rig-wake
rig-wake:
	@test -n "$(RIG_MAC)" || { echo ">>> RIG_MAC unset — run 'make rig-mac' while the rig is up, then persist it here."; \
	  echo ">>> also check BIOS once: Advanced > ACPI/Chipset > 'PCIE Devices Power On' = Enabled"; exit 1; }
	wakeonlan $(RIG_MAC)
	@echo ">>> magic packet sent to $(RIG_MAC) — sshd on .24 in ~90s if BIOS+NIC are armed"

# Converge POST on the rig from here: root pass then user pass (XXII —
# either order until quiet). ssh -t allocates the TTY sudo needs for
# its password prompt; expect the rig's sudo to ask once.
.PHONY: rig-post
rig-post:
# NEVER `| bash < /dev/null` — the redirect overrides the pipe and bash
# executes NOTHING (a whole afternoon of silent no-op "applies",
# 2026-08-16). Interactivity is solved in the plan itself: emit_plan's
# preamble exports DEBIAN_FRONTEND=noninteractive.
	ssh -t crucible.local 'cd ~/Desktop/Projects/flux && git pull servalws.local:Desktop/Projects/flux main && make | sudo bash && make | bash'
