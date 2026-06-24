DEB_URLS += https://installers.lmstudio.ai/linux/x64/0.4.7-4/LM-Studio-0.4.7-4-x64.deb

DESKTOP_PKG_code   := code
DESKTOP_FLAGS_code := --disable-gpu

PKG_APPS += \
  /usr/share/applications/code.desktop \
  /usr/bin/gh \
  /usr/bin/npm \
  /usr/bin/lmstudio \
  /usr/share/applications/pycharm-community.desktop

/usr/share/applications/code.desktop: /usr/bin/code

/etc/apt/sources.list.d/code.list: /usr/share/keyrings/microsoft.gpg
	echo 'deb [arch=amd64 signed-by=$<] https://packages.microsoft.com/repos/code stable main' > $@

/usr/share/keyrings/microsoft.gpg:
	mkdir -p $(dir $@)
	curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > $@

/usr/bin/lmstudio: | $(DOWNLOADS_DIR)/LM-Studio-0.4.7-4-x64.deb
	$(APT) install -y $(DOWNLOADS_DIR)/LM-Studio-0.4.7-4-x64.deb
	sed -i 's|Exec=/opt/LM-Studio/lm-studio|Exec=/opt/LM-Studio/lm-studio --use-gl=desktop|' /usr/share/applications/lm-studio.desktop

define PYCHARM_DESKTOP
[Desktop Entry]
Name=PyCharm Community Edition
Type=Application
Exec=/opt/pycharm-community/bin/pycharm.sh %f
Icon=/opt/pycharm-community/bin/pycharm.svg
Terminal=false
Categories=Development;IDE;
MimeType=text/x-python;
endef

/usr/share/applications/pycharm-community.desktop: /opt/pycharm-community/bin/pycharm.sh
	$(file >$@,$(PYCHARM_DESKTOP))
	@echo ">>> PyCharm Community desktop entry created"

PYCHARM_RELEASES_API := https://data.services.jetbrains.com/products/releases?code=PCC&latest=true&type=release

/opt/pycharm-community/bin/pycharm.sh: PYCHARM_URL     = $(shell curl -fsSL '$(PYCHARM_RELEASES_API)' | jq -r '.PCC[0].downloads.linux.link')
/opt/pycharm-community/bin/pycharm.sh: PYCHARM_TARBALL = $(DOWNLOADS_DIR)/$(notdir $(PYCHARM_URL))
/opt/pycharm-community/bin/pycharm.sh: | $(DOWNLOADS_DIR)
	curl -fL --retry 5 --retry-delay 3 --progress-bar -A "Mozilla/5.0" $(PYCHARM_URL) -o $(PYCHARM_TARBALL)
	tar -xz -C /opt --transform 's|^pycharm-[^/]*|pycharm-community|' -f $(PYCHARM_TARBALL)
	@echo ">>> PyCharm Community installed to /opt/pycharm-community"
