# Terminator — pure-black background on the default profile, so every program in the
# terminal (lynx included) sits on #000000. No config exists yet, so we write a minimal
# one; Terminator fills in its other defaults and preserves these when you save prefs.
TERMINATOR_CFG := $(USER_HOME)/.config/terminator/config
USER_FILES += $(TERMINATOR_CFG)

define TERMINATOR_CONFIG
[profiles]
  [[default]]
    background_color = "#000000"
    background_type = solid
    foreground_color = "#ffffff"
endef

$(TERMINATOR_CFG): | $(USER_HOME)/.config/terminator
	$(file >$@,$(TERMINATOR_CONFIG))
	@echo ">>> Terminator: pure-black (#000000) background on default profile"

$(USER_HOME)/.config/terminator:
	mkdir -p $@
