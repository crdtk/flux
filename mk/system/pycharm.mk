PKG_APPS += /usr/share/applications/pycharm-community.desktop

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
