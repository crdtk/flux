IMAGETHUMB_DESKTOP := /usr/share/kservices5/imagethumbnail.desktop
PKG_APPS           += /usr/bin/digikam /usr/bin/flameshot /usr/bin/gwenview /usr/bin/heif-convert

/usr/bin/digikam: $(KUBUNTU_BACKPORTS_LIST)
	@$(APT) update && $(APT) install -y $(@F)

HEIF_MIME_OK := $(shell grep -c 'image/heif' $(IMAGETHUMB_DESKTOP) 2>/dev/null)
PKG_APPS     += /usr/lib/x86_64-linux-gnu/qt5/plugins/imageformats/kimg_heif.so
/usr/lib/x86_64-linux-gnu/qt5/plugins/imageformats/kimg_heif.so:
	$(APT) install -y kimageformat-plugins
ifeq ($(HEIF_MIME_OK),0)
	@sed -i 's|image/avif;|image/avif;image/heif;image/heic;|' $(IMAGETHUMB_DESKTOP) && echo ">>> HEIF added to KIO imagethumbnail plugin"
endif
