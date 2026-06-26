# Lynx — force color mode so the system lynx.cfg's COLOR:0:white:black actually paints.
# Lynx ignores COLOR unless in color mode; in color mode it clears the whole screen to
# the COLOR:0 pair, so the background goes black inside lynx regardless of the terminal's
# own background. show_color lives in the per-user ~/.lynxrc ("always" is what the
# options menu's Show color → ALWAYS would save).
LYNX_RC := $(USER_HOME)/.lynxrc
USER_FILES += $(LYNX_RC)

$(LYNX_RC):
	printf 'show_color=always\n' > $@
	@echo ">>> lynx: color mode forced (~/.lynxrc) — COLOR:0:white:black now paints black"
