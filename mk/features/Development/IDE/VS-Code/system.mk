# VS Code — root half: install the `code` package from Microsoft's apt repo. The user
# half (extensions, settings.json) lives in user.mk. code.desktop resolves via the
# common %.desktop pattern (DESKTOP_PKG_code) and /usr/bin/code via the .list pattern.
DESKTOP_PKG_code   := code
DESKTOP_FLAGS_code := --disable-gpu

PKG_APPS += /usr/share/applications/code.desktop

/usr/share/applications/code.desktop: /usr/bin/code

/etc/apt/sources.list.d/code.list: /usr/share/keyrings/microsoft.gpg
	echo 'deb [arch=amd64 signed-by=$<] https://packages.microsoft.com/repos/code stable main' > $@

/usr/share/keyrings/microsoft.gpg:
	mkdir -p $(dir $@)
	curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > $@
