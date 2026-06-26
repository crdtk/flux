# Cross-feature infrastructure shared by more than one feature module. Parsed before
# the feature globs so features may reference these (Kubuntu backports source used by
# graphics + audiovideo; the .desktop pattern rule used by development + network).

# Fleet capability sense (III): probe GPU *presence* via lspci — works on a bare box
# before any driver exists, unlike nvidia-smi. Used by both ParallelComputing (driver +
# CUDA) and Security (nouveau/nvidia modprobe), so it lives here, parsed before the globs.
HAS_NVIDIA := $(shell lspci 2>/dev/null | grep -qi nvidia && echo 1)

KUBUNTU_BACKPORTS_LIST := /etc/apt/sources.list.d/kubuntu-ppa-ubuntu-backports-$(UBUNTU_CODENAME).sources

$(KUBUNTU_BACKPORTS_LIST):
	add-apt-repository -y ppa:kubuntu-ppa/backports

# DESKTOP_PKG_<name> / DESKTOP_FLAGS_<name> live in the owning feature (III).
/usr/share/applications/%.desktop:
	test -f $@ || $(APT) install -y --reinstall $(DESKTOP_PKG_$*)
	sed -i 's|^\(Exec=[^ ]*\)|\1 $(DESKTOP_FLAGS_$*)|g' $@
