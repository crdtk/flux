DEB_URLS += https://installers.lmstudio.ai/linux/x64/0.4.7-4/LM-Studio-0.4.7-4-x64.deb

# Build system (cmake) + language toolchains: g++-14 (C++), swipl (SWI-Prolog).
# freedesktop has no programming-language category — compilers/interpreters live under
# Building per the spec. Universal, resolved via the apt-file %-rule (swipl → swi-prolog-core).
# Python is intentionally absent here: base python3 ships with the OS and the project's
# Python is the uv-managed 3.12 venv (demos feature); /usr/bin/python3 also mis-resolves
# under the %-rule's substring match (→ python3-activipy), so it must not go through it.
PKG_APPS += \
  /usr/bin/cmake \
  /usr/bin/g++-14 \
  /usr/bin/swipl \
  /usr/bin/gh \
  /usr/bin/npm \
  /usr/bin/lmstudio

/usr/bin/lmstudio: | $(DOWNLOADS_DIR)/LM-Studio-0.4.7-4-x64.deb
	$(APT) install -y $(DOWNLOADS_DIR)/LM-Studio-0.4.7-4-x64.deb; sed -i 's|Exec=/opt/LM-Studio/lm-studio|Exec=/opt/LM-Studio/lm-studio --use-gl=desktop|' /usr/share/applications/lm-studio.desktop
