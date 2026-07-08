# kickerdash is the sentinel plasma-widgets-addons actually ships a
# metadata.json for (verified via dpkg -L — the weather applet is a compiled
# plugin with no metadata.json). Display-manager session defaults are owned by
# the POST system (post/post.pl, SELECTION section), which keeps GDM, SDDM and
# LightDM all standby-ready instead of forcing one of them.
PKG_APPS += \
  /usr/share/plasma/plasmoids/org.kde.plasma.kickerdash/metadata.json \
  /usr/share/wayland-sessions/lomiri.desktop

## Lomiri (Unity 8 successor, Mir-based Wayland compositor) — install and register as a session.
/usr/share/wayland-sessions/lomiri.desktop:
	$(APT) install -y lomiri && echo ">>> Lomiri installed — select it at the greeter (Wayland)"

## Kill the stuck Unity session so SDDM reclaims the greeter.
.PHONY: kill-unity-session
kill-unity-session:
	systemctl --user stop unity-session.target 2>/dev/null || true
	pkill -u m cinnamon-session 2>/dev/null || true
	pkill -u m compiz 2>/dev/null || true

