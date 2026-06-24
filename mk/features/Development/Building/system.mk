DEB_URLS += https://installers.lmstudio.ai/linux/x64/0.4.7-4/LM-Studio-0.4.7-4-x64.deb

PKG_APPS += \
  /usr/bin/gh \
  /usr/bin/npm \
  /usr/bin/lmstudio

/usr/bin/lmstudio: | $(DOWNLOADS_DIR)/LM-Studio-0.4.7-4-x64.deb
	$(APT) install -y $(DOWNLOADS_DIR)/LM-Studio-0.4.7-4-x64.deb
	sed -i 's|Exec=/opt/LM-Studio/lm-studio|Exec=/opt/LM-Studio/lm-studio --use-gl=desktop|' /usr/share/applications/lm-studio.desktop
