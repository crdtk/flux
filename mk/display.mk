# ==========================================================
# Display configuration — multi-GPU X11 setup
# ==========================================================

HAS_NVIDIA_A4000 := $(shell lspci 2>/dev/null | grep -q "GA104GL" && echo 1 || echo 0)
HAS_ASPEED_VGA   := $(shell lspci 2>/dev/null | grep -q "ASPEED" && echo 1 || echo 0)

DISPLAY_CONFIG := $(if $(filter 1,$(HAS_NVIDIA_A4000) $(HAS_ASPEED_VGA)),/etc/X11/xorg.conf)

define XORG_NVIDIA_ASPEED
Section "Device"
    Identifier "NVIDIA A4000"
    Driver     "nvidia"
    Option     "AllowEmptyInitialConfiguration" "true"
EndSection

Section "Device"
    Identifier "ASPEED VGA"
    Driver     "vesa"
    BusID      "PCI:15:0:0"
EndSection

Section "Screen"
    Identifier "Screen0"
    Device     "NVIDIA A4000"
EndSection

Section "Screen"
    Identifier "Screen1"
    Device     "ASPEED VGA"
EndSection

Section "ServerLayout"
    Identifier "Layout0"
    Screen     "Screen0"
    Screen     "Screen1" RightOf "Screen0"
EndSection
endef

/etc/X11/xorg.conf:
	$(file >$@,$(XORG_NVIDIA_ASPEED))
	systemctl restart lightdm
	@echo ">>> X11 configured for NVIDIA A4000 + ASPEED VGA. LightDM restarted."
