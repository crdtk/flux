# Cross-feature infrastructure shared by more than one feature module. Parsed before
# the feature globs so features may reference these (Kubuntu backports source used by
# graphics + audiovideo; the .desktop pattern rule used by development + network).

KUBUNTU_BACKPORTS_LIST := /etc/apt/sources.list.d/kubuntu-ppa-ubuntu-backports-$(UBUNTU_CODENAME).sources

$(KUBUNTU_BACKPORTS_LIST):
	add-apt-repository -y ppa:kubuntu-ppa/backports

# DESKTOP_PKG_<name> / DESKTOP_FLAGS_<name> live in the owning feature (III).
/usr/share/applications/%.desktop:
	test -f $@ || $(APT) install -y --reinstall $(DESKTOP_PKG_$*)
	sed -i 's|^\(Exec=[^ ]*\)|\1 $(DESKTOP_FLAGS_$*)|g' $@
