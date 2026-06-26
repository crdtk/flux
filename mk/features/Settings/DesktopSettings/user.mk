# Whole-desktop truly-black KDE color scheme. Derived from the maintained BreezeDark
# (keeps its light foregrounds + accent colors for contrast) but forces every background
# — window/view/button/tooltip rows and the window-manager titlebars — to pure #000000.
# Applied live with plasma-apply-colorscheme; affects all Qt/KDE apps (Dolphin, panels,
# editors, System Settings). GTK apps keep their own theme (Terminator/Chrome handled
# separately).
SCHEME_DIR  := $(USER_HOME)/.local/share/color-schemes
SCHEME_FILE := $(SCHEME_DIR)/CrucibleBlack.colors
USER_FILES  += $(SCHEME_FILE)

$(SCHEME_FILE): /usr/share/color-schemes/BreezeDark.colors | $(SCHEME_DIR)
	sed -E 's/^(BackgroundNormal|BackgroundAlternate|activeBackground|inactiveBackground)=.*/\1=0,0,0/; s/^Name=.*/Name=Crucible Black/; s/^ColorScheme=.*/ColorScheme=CrucibleBlack/' $< > $@
	plasma-apply-colorscheme CrucibleBlack 2>/dev/null || true
	@echo ">>> Crucible Black: pure-#000000 KDE color scheme applied to all Qt/KDE apps"

$(SCHEME_DIR):
	mkdir -p $@
