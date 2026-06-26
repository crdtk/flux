# Lynx (console web browser) — black background with light text for every account.
# Appended to the system lynx.cfg (read by default, no env var). COLOR:0 is the default
# text style; its background field is the screen background, so white-on-black there
# paints the whole screen black. A removal/append has no positive file artifact and the
# package owns lynx.cfg, so this is a presence-gated dot-target (V): the grep gate makes
# it a no-op once the line is in, so re-runs never duplicate it.
LYNX_CFG_FILE := /etc/lynx/lynx.cfg
LYNX_BG_SET   := $(shell grep -qs '^COLOR:0:white:black' $(LYNX_CFG_FILE) && echo 1)

MANAGEMENT += $(if $(LYNX_BG_SET),,.lynx-black-background)

.lynx-black-background:
	printf 'COLOR:0:white:black\n' >> $(LYNX_CFG_FILE)
	@echo ">>> lynx: black background (white on black) in $(LYNX_CFG_FILE)"
