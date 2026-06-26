DEB_URLS += https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb

DESKTOP_PKG_google-chrome   := google-chrome-stable
# force-dark-mode darkens Chrome's own UI; WebContentsForceDark darkens web pages
# (dark gray — for true #000000 pages add the Dark Reader extension per-profile).
DESKTOP_FLAGS_google-chrome := --use-gl=desktop --force-dark-mode --enable-features=WebContentsForceDark

PKG_APPS += /usr/share/applications/google-chrome.desktop

/usr/share/applications/google-chrome.desktop: /usr/bin/google-chrome

/usr/bin/google-chrome: | $(DOWNLOADS_DIR)/google-chrome-stable_current_amd64.deb
	$(APT) install -y $(DOWNLOADS_DIR)/google-chrome-stable_current_amd64.deb
