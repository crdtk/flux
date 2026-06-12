define ALBERT_AUTOSTART
[Desktop Entry]
Exec=albert
Icon=albert
Name=Albert
Type=Application
X-KDE-autostart-enabled=true
endef

user: $(USER_HOME)/.config/autostart/albert.desktop

$(USER_HOME)/.config/autostart/albert.desktop:
	mkdir -p $(dir $@)
	$(file >$@,$(ALBERT_AUTOSTART))
