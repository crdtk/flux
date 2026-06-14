DOLPHIN_PREVIEW_OK        := $(shell grep -c '^Show Preview=true' $(USER_HOME)/.config/kdeglobals 2>/dev/null)
## Non-empty when panels were created this run and plasmashell needs one restart at the end.
PLASMASHELL_NEEDS_RESTART := $(or $(filter 0,$(GLOBALMENU_OK)),$(filter 0,$(DOCK_OK)),$(filter 0,$(DOCK_CONFIGURED_OK)))
KWIN_BORDERLESS_OK := $(shell grep -c '^BorderlessMaximizedWindows=true' $(USER_HOME)/.config/kwinrc 2>/dev/null)
ALBERT_HOTKEY_OK   := $(shell grep -c '^hotkey=Alt+Space' $(USER_HOME)/.config/albert/albert.conf 2>/dev/null)
KRUNNER_CONFLICT   := $(shell grep -c 'Alt+Space' $(USER_HOME)/.config/kglobalshortcutsrc 2>/dev/null)

.PHONY: configure-panels

configure-panels:
ifeq ($(DOLPHIN_PREVIEW_OK),0)
	kwriteconfig5 --file kdeglobals --group "KFileDialog Settings" --key "Show Preview" true
	@echo ">>> Dolphin show preview enabled"
endif
ifeq ($(KWIN_BORDERLESS_OK),0)
	kwriteconfig6 --file kwinrc --group Windows --key BorderlessMaximizedWindows true
	gdbus call --session --dest org.kde.KWin --object-path /KWin --method org.kde.KWin.reconfigure >/dev/null
	@echo ">>> Borderless maximized windows enabled"
endif
ifneq ($(KRUNNER_CONFLICT),0)
	kwriteconfig6 --file $(USER_HOME)/.config/kglobalshortcutsrc --group "krunner.desktop" --key "_launch" "Alt+F2,,KRunner"
	@echo ">>> KRunner Alt+Space removed (Albert owns this shortcut)"
endif
ifeq ($(ALBERT_HOTKEY_OK),0)
	mkdir -p $(USER_HOME)/.config/albert
	kwriteconfig6 --file $(USER_HOME)/.config/albert/albert.conf --group General --key hotkey "Alt+Space"
	@echo ">>> Albert hotkey set to Alt+Space"
endif
ifneq ($(PLASMASHELL_NEEDS_RESTART),)
	systemctl --user reset-failed plasma-plasmashell.service 2>/dev/null || true
	@systemctl --user restart plasma-plasmashell.service 2>/dev/null \
	  && echo ">>> plasmashell restarted — run make again to apply settings" \
	  || echo ">>> WARNING: plasmashell restart failed (GPU down?) — settings apply on next good boot"
endif
