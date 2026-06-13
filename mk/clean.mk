.PHONY: clean
## Removes all top/bottom panels; make clean && make rebuilds from scratch
define REMOVE_PANELS_JS
  var all = panels();
  for (var i = 0; i < all.length; i++) {
    if (all[i].location == 3 || all[i].location == 4) {
      all[i].remove();
    }
  }
endef
clean:
ifeq ($(shell id -u),0)
	rm -f /usr/share/applications/google-chrome.desktop /usr/share/applications/code.desktop /usr/share/applications/pycharm-community.desktop
	rm -f $(CUDA_KEYRING_DEB) /etc/apt/sources.list.d/cuda-ubuntu*-x86_64.list
	rm -f /etc/apt/preferences.d/no-snapd
	rm -f /etc/systemd/system/packagekit.service
else
	rm -rf $(USER_HOME)/.cache/thumbnails/fail/
	rm -f $(USER_HOME)/.config/autostart/albert.desktop
	rm -f $(USER_HOME)/.local/share/applications/pycharm-community.desktop
	kpackagetool6 -t Plasma/Applet -r com.github.antroids.application-title-bar 2>/dev/null || true
	kpackagetool6 -t Plasma/Applet -r Plasma.Flex.Hub 2>/dev/null || true
	kpackagetool6 -t Plasma/Applet -r com.github.chrtall.kppleMenu 2>/dev/null || true
	gdbus call --session --dest org.kde.plasmashell --object-path /PlasmaShell \
	  --method org.kde.PlasmaShell.evaluateScript '$(strip $(REMOVE_PANELS_JS))' >/dev/null || true
endif
