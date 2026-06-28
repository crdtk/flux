PKG_APPS += \
  /usr/share/plasma/plasmoids/org.kde.plasma.weather/metadata.json \
  /etc/sddm.conf.d/30-x11-session.conf

## Global menu needs X11 — KWin on Wayland lacks the appmenu protocol (Qt, GTK and Electron alike)
define SDDM_X11_CONF
[Autologin]
Session=plasmax11
endef

SDDM_LAST_SESSION := $(wildcard /var/lib/sddm/state.conf)
/etc/sddm.conf.d/30-x11-session.conf: /usr/share/xsessions/plasmax11.desktop
	sed -i '/^Session=plasma$$/d' /etc/sddm.conf
ifneq ($(SDDM_LAST_SESSION),)
	sed -i 's|^Session=.*|Session=$<|' $(SDDM_LAST_SESSION)
endif
	$(file >$@,$(SDDM_X11_CONF))
	@echo ">>> SDDM boots Plasma (X11) — global menu active after next login"
