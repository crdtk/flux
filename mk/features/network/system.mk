DEB_URLS += https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb

DESKTOP_PKG_google-chrome   := google-chrome-stable
DESKTOP_FLAGS_google-chrome := --use-gl=desktop

PKG_APPS += /usr/share/applications/google-chrome.desktop

/usr/share/applications/google-chrome.desktop: /usr/bin/google-chrome

/usr/bin/google-chrome: | $(DOWNLOADS_DIR)/google-chrome-stable_current_amd64.deb
	$(APT) install -y $(DOWNLOADS_DIR)/google-chrome-stable_current_amd64.deb
