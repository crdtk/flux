PKG_APPS += \
  /usr/share/plasma/plasmoids/org.kde.plasma.weather/metadata.json \
  /etc/sddm.conf.d/30-x11-session.conf \
  /usr/share/wayland-sessions/lomiri.desktop

## Lomiri (Unity 8 successor, Mir-based Wayland compositor) — install and register as a session.
/usr/share/wayland-sessions/lomiri.desktop:
	$(APT) install -y lomiri && echo ">>> Lomiri installed — select it at the SDDM greeter (Wayland)"

## Kill the stuck Unity session so SDDM reclaims the greeter.
.PHONY: kill-unity-session
kill-unity-session:
	systemctl --user stop unity-session.target 2>/dev/null || true
	pkill -u m cinnamon-session 2>/dev/null || true
	pkill -u m compiz 2>/dev/null || true

## Restore SDDM as active display manager after a competing DM (e.g. lightdm from unity) took over.
.PHONY: reconfigure-display-manager
reconfigure-display-manager:
	echo "/usr/bin/sddm" > /etc/X11/default-display-manager
	DEBIAN_FRONTEND=noninteractive dpkg-reconfigure sddm
	systemctl disable lightdm 2>/dev/null || true
	systemctl enable sddm
	systemctl reset-failed sddm 2>/dev/null || true
	systemctl start sddm && echo ">>> SDDM started"

## Global menu needs X11 — KWin on Wayland lacks the appmenu protocol (Qt, GTK and Electron alike).
## DisplayServer=x11 overrides 10-wayland.conf (kwin_wayland greeter) which leaks WAYLAND_DISPLAY
## into the session environment, causing plasmashell/kscreen-doctor to pick the wayland Qt platform
## plugin, fail to connect (no compositor running), and crash with qFatal on every login.
define SDDM_X11_CONF
[General]
DisplayServer=x11

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
