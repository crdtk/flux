ifndef _PLASMASHELL_MK
_PLASMASHELL_MK := 1

## Removes all top/bottom panel containments from appletsrc, then restarts plasmashell.
## evaluateScript panel.remove() is deferred and plasmashell restores from appletsrc via KConfig
## file watchers — JS cannot reliably delete panels. Editing the file is the authoritative fix.
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

APPLETSRC := $(USER_HOME)/.config/plasma-org.kde.plasma.desktop-appletsrc

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

## Operational maintenance — call explicitly: make reset-panels
.PHONY: reset-panels

## Strips panel entries from appletsrc and restarts plasmashell so it reads clean config.
reset-panels:
	@python3 -c "$$STRIP_PANELS_PY" $(APPLETSRC) 2>/dev/null || true
	@systemctl --user restart plasma-plasmashell.service
	@until systemctl --user is-active plasma-plasmashell.service >/dev/null 2>&1; do sleep 1; done
	@echo ">>> plasmashell restarted with clean panel config"

## Start plasmashell if not running — handles both inactive and failed states at runtime.
.PHONY: ensure-plasmashell
ensure-plasmashell:
	@systemctl --user is-active plasma-plasmashell.service >/dev/null 2>&1 || \
	  (systemctl --user reset-failed plasma-plasmashell.service 2>/dev/null || true; \
	   systemctl --user start plasma-plasmashell.service; \
	   until systemctl --user is-active plasma-plasmashell.service >/dev/null 2>&1; do sleep 1; done; \
	   echo ">>> plasmashell started")

user:: ensure-plasmashell

endif
