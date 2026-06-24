# ==========================================================
# Display configuration — single NVIDIA screen
# ==========================================================
# The Dell is on the GPU's DisplayPort and the GPU is healthy, so X drives it
# directly. A second (ASPEED) screen with no monitor parks plasmashell's panels on
# a phantom output — so this is GPU-only.

HAS_NVIDIA_A4000 := $(shell lspci 2>/dev/null | grep -q "GA104GL" && echo 1 || echo 0)

DISPLAY_CONFIG := $(if $(filter 1,$(HAS_NVIDIA_A4000)),/etc/X11/xorg.conf)

define XORG_NVIDIA
Section "Device"
    Identifier "NVIDIA A4000"
    Driver     "nvidia"
    Option     "AllowEmptyInitialConfiguration" "true"
EndSection

Section "Screen"
    Identifier "Screen0"
    Device     "NVIDIA A4000"
EndSection
endef

# No lightdm restart: that tears down the session and resets the KScreen monitor
# layout (blanking the second DisplayPort). The new config applies on next login.
/etc/X11/xorg.conf:
	$(file >$@,$(XORG_NVIDIA))
	@echo ">>> X11 configured for NVIDIA A4000 (single screen) — applies on next login (no session restart)."
