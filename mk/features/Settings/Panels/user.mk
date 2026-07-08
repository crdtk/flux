# Panel state (creation, widgets, plasmashell recovery) is owned by POST
# (post/post.pl: user_config top_panel/bottom_panel/plasmashell_active, XXI).
# This module keeps only the destructive/manual operations POST must not do.

APPLETSRC := $(USER_HOME)/.config/plasma-org.kde.plasma.desktop-appletsrc

## Removes all top/bottom panel containments from appletsrc, then restarts plasmashell.
## evaluateScript panel.remove() is deferred and plasmashell restores from appletsrc via
## KConfig file watchers — JS cannot reliably delete panels. Editing the file is the
## authoritative fix.
define STRIP_PANELS_PY
import configparser, re, sys

path = sys.argv[1]
with open(path) as f:
    raw = f.read()

# KDE uses nested group headers like [Containments][1] — not valid INI.
# Split into blocks on any top-level [Containments][N] header (with optional sub-groups).
# Identify panel blocks: those containing location=3 or location=4.
blocks = re.split(r'(?=^\[Containments\]\[\d+\](?!\[))', raw, flags=re.MULTILINE)

def is_panel(block):
    loc = re.search(r'^location=(\d+)$$', block, re.MULTILINE)
    return loc and loc.group(1) in ('3', '4')

kept = [b for b in blocks if not is_panel(b)]
with open(path, 'w') as f:
    f.write(''.join(kept))
endef
export STRIP_PANELS_PY

PLASMA_BACKUP_DIR := backups/plasma-$(shell date +%Y%m%d-%H%M%S)
PLASMA_CFG        := $(USER_HOME)/.config

## Snapshot current plasma config before any destructive operation.
.PHONY: backup-plasma
backup-plasma:
	mkdir -p $(PLASMA_BACKUP_DIR)
	cp $(APPLETSRC)                                     $(PLASMA_BACKUP_DIR)/ 2>/dev/null || true
	cp $(PLASMA_CFG)/kwinrc                             $(PLASMA_BACKUP_DIR)/ 2>/dev/null || true
	cp $(PLASMA_CFG)/kglobalshortcutsrc                $(PLASMA_BACKUP_DIR)/ 2>/dev/null || true
	cp $(PLASMA_CFG)/kdeglobals                        $(PLASMA_BACKUP_DIR)/ 2>/dev/null || true
	cp $(PLASMA_CFG)/plasmashellrc                     $(PLASMA_BACKUP_DIR)/ 2>/dev/null || true
	cp $(PLASMA_CFG)/plasmarc                          $(PLASMA_BACKUP_DIR)/ 2>/dev/null || true
	cp -r $(USER_HOME)/.local/share/kscreen            $(PLASMA_BACKUP_DIR)/ 2>/dev/null || true
	@echo ">>> plasma config backed up to $(PLASMA_BACKUP_DIR)"

## Strips panel entries from appletsrc and restarts plasmashell so it reads clean
## config; POST then recreates the panels.
.PHONY: reset-panels
reset-panels:
	@python3 -c "$$STRIP_PANELS_PY" $(APPLETSRC) 2>/dev/null || true
	@systemctl --user restart plasma-plasmashell.service
	@until systemctl --user is-active plasma-plasmashell.service >/dev/null 2>&1; do sleep 1; done
	@echo ">>> plasmashell restarted with clean panel config — run POST to recreate panels"
