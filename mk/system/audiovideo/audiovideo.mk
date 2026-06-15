OBS_PPA_LIST := /etc/apt/sources.list.d/obsproject-ubuntu-obs-studio-$(UBUNTU_CODENAME).sources

PKG_APPS += \
  /usr/bin/kdenlive \
  /usr/bin/obs

/usr/bin/kdenlive: $(KUBUNTU_BACKPORTS_LIST)
	$(APT) update
	$(APT) install -y $(@F)

/usr/bin/obs: $(OBS_PPA_LIST)
	$(APT) update
	$(APT) install -y obs-studio

$(OBS_PPA_LIST):
	add-apt-repository -y ppa:obsproject/obs-studio
