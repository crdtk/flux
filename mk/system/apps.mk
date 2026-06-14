DEB_URLS += \
  https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
  https://installers.lmstudio.ai/linux/x64/0.4.7-4/LM-Studio-0.4.7-4-x64.deb

IMAGETHUMB_DESKTOP     := /usr/share/kservices5/imagethumbnail.desktop
HEIF_THUMB_TARGET      := $(and $(filter 0,$(shell grep -c 'image/heif' $(IMAGETHUMB_DESKTOP) 2>/dev/null)),$(IMAGETHUMB_DESKTOP))
.PHONY: $(HEIF_THUMB_TARGET)
KIMG_HEIF_SO           := /usr/lib/x86_64-linux-gnu/qt5/plugins/imageformats/kimg_heif.so
KUBUNTU_BACKPORTS_LIST := /etc/apt/sources.list.d/kubuntu-ppa-ubuntu-backports-$(UBUNTU_CODENAME).sources
OBS_PPA_LIST           := /etc/apt/sources.list.d/obsproject-ubuntu-obs-studio-$(UBUNTU_CODENAME).sources
SDDM_LAST_SESSION      := $(wildcard /var/lib/sddm/state.conf)

DESKTOP_PKG_google-chrome  := google-chrome-stable
DESKTOP_PKG_code           := code
DESKTOP_FLAGS_google-chrome := --use-gl=desktop
DESKTOP_FLAGS_code          := --disable-gpu

PKG_APPS += \
  /usr/share/applications/code.desktop \
  /usr/share/applications/google-chrome.desktop \
  /usr/bin/digikam \
  /usr/bin/kdenlive \
  /usr/bin/flameshot \
  /usr/bin/gh \
  /usr/bin/gwenview \
  /usr/bin/heif-convert \
  /usr/bin/lmstudio \
  /usr/bin/mc \
  /usr/bin/npm \
  /usr/bin/obs \
  /usr/bin/plank \
  /usr/share/plasma/plasmoids/org.kde.plasma.weather/metadata.json \
  $(HEIF_THUMB_TARGET) \
  /etc/sddm.conf.d/30-x11-session.conf

/usr/share/applications/%.desktop:
	test -f $@ || $(APT) install -y --reinstall $(DESKTOP_PKG_$*)
	sed -i 's|^\(Exec=[^ ]*\)|\1 $(DESKTOP_FLAGS_$*)|g' $@

/usr/share/applications/code.desktop: /usr/bin/code

## Global menu needs X11 — KWin on Wayland lacks the appmenu protocol (Qt, GTK and Electron alike)
define SDDM_X11_CONF
[Autologin]
Session=plasmax11
endef

/etc/sddm.conf.d/30-x11-session.conf: /usr/share/xsessions/plasmax11.desktop
	sed -i '/^Session=plasma$$/d' /etc/sddm.conf
ifneq ($(SDDM_LAST_SESSION),)
	sed -i 's|^Session=.*|Session=$<|' $(SDDM_LAST_SESSION)
endif
	$(file >$@,$(SDDM_X11_CONF))
	@echo ">>> SDDM boots Plasma (X11) — global menu active after next login"

/etc/apt/sources.list.d/code.list: /usr/share/keyrings/microsoft.gpg
	echo 'deb [arch=amd64 signed-by=$<] https://packages.microsoft.com/repos/code stable main' > $@

/usr/share/keyrings/microsoft.gpg:
	mkdir -p $(dir $@)
	curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > $@

/usr/share/applications/google-chrome.desktop: /usr/bin/google-chrome

/usr/bin/google-chrome: | $(DOWNLOADS_DIR)/google-chrome-stable_current_amd64.deb
	$(APT) install -y $(DOWNLOADS_DIR)/google-chrome-stable_current_amd64.deb

/usr/bin/lmstudio: | $(DOWNLOADS_DIR)/LM-Studio-0.4.7-4-x64.deb
	$(APT) install -y $(DOWNLOADS_DIR)/LM-Studio-0.4.7-4-x64.deb
	sed -i 's|Exec=/opt/LM-Studio/lm-studio|Exec=/opt/LM-Studio/lm-studio --use-gl=desktop|' /usr/share/applications/lm-studio.desktop

/usr/bin/digikam /usr/bin/kdenlive: $(KUBUNTU_BACKPORTS_LIST)
	$(APT) update
	$(APT) install -y $(@F)

$(KUBUNTU_BACKPORTS_LIST):
	add-apt-repository -y ppa:kubuntu-ppa/backports

/usr/bin/obs: $(OBS_PPA_LIST)
	$(APT) update
	$(APT) install -y obs-studio

$(OBS_PPA_LIST):
	add-apt-repository -y ppa:obsproject/obs-studio


$(IMAGETHUMB_DESKTOP): $(KIMG_HEIF_SO)
	grep -q 'image/heif' $@ || sed -i 's|image/avif;|image/avif;image/heif;image/heic;|' $@
	@echo ">>> HEIF added to KIO imagethumbnail plugin"

$(KIMG_HEIF_SO):
	$(APT) install -y kimageformat-plugins
