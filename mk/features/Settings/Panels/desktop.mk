DOLPHIN_PREVIEW_OK := $(shell grep -c '^Show Preview=true' $(USER_HOME)/.config/kdeglobals 2>/dev/null)
KWIN_BORDERLESS_OK := $(shell grep -c '^BorderlessMaximizedWindows=true' $(USER_HOME)/.config/kwinrc 2>/dev/null)
user::
ifeq ($(DOLPHIN_PREVIEW_OK),0)
	kwriteconfig5 --file kdeglobals --group "KFileDialog Settings" --key "Show Preview" true
	@echo ">>> Dolphin show preview enabled"
endif
ifeq ($(KWIN_BORDERLESS_OK),0)
	kwriteconfig6 --file kwinrc --group Windows --key BorderlessMaximizedWindows true
	gdbus call --session --dest org.kde.KWin --object-path /KWin --method org.kde.KWin.reconfigure >/dev/null
	@echo ">>> Borderless maximized windows enabled"
endif
ifneq ($(PLASMASHELL_NEEDS_RESTART),)
	systemctl --user reset-failed plasma-plasmashell.service 2>/dev/null || true
	@systemctl --user restart plasma-plasmashell.service 2>/dev/null \
	  && echo ">>> plasmashell restarted — run make again to apply settings" \
	  || echo ">>> WARNING: plasmashell restart failed (GPU down?) — settings apply on next good boot"
endif
