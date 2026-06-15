IMAGETHUMB_DESKTOP := /usr/share/kservices5/imagethumbnail.desktop
HEIF_THUMB_TARGET  := $(and $(filter 0,$(shell grep -c 'image/heif' $(IMAGETHUMB_DESKTOP) 2>/dev/null)),$(IMAGETHUMB_DESKTOP))
.PHONY: $(HEIF_THUMB_TARGET)
KIMG_HEIF_SO       := /usr/lib/x86_64-linux-gnu/qt5/plugins/imageformats/kimg_heif.so

PKG_APPS += \
  /usr/bin/digikam \
  /usr/bin/flameshot \
  /usr/bin/gwenview \
  /usr/bin/heif-convert \
  $(HEIF_THUMB_TARGET)

/usr/bin/digikam: $(KUBUNTU_BACKPORTS_LIST)
	$(APT) update
	$(APT) install -y $(@F)

$(IMAGETHUMB_DESKTOP): $(KIMG_HEIF_SO)
	grep -q 'image/heif' $@ || sed -i 's|image/avif;|image/avif;image/heif;image/heic;|' $@
	@echo ">>> HEIF added to KIO imagethumbnail plugin"

$(KIMG_HEIF_SO):
	$(APT) install -y kimageformat-plugins
