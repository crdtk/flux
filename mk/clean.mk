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
	rm -rf $(CURDIR)/.venv
	rm -rf $(CURDIR)/demos/LLMs-from-scratch/venv
	rm -f /usr/share/applications/code.desktop /usr/share/applications/pycharm-community.desktop
	rm -f $(CUDA_KEYRING_DEB) /etc/apt/sources.list.d/cuda-ubuntu*-x86_64.list
	rm -f /etc/apt/preferences.d/no-snapd
	rm -f /etc/systemd/system/packagekit.service
	systemctl disable --now mnt-backup.automount mnt-backup.mount 2>/dev/null || true
	rm -f /etc/systemd/system/mnt-backup.automount /etc/systemd/system/mnt-backup.mount
	systemctl disable --now disable-gpu-aspm.service 2>/dev/null || true
	rm -f /etc/systemd/system/disable-gpu-aspm.service /usr/local/sbin/disable-gpu-aspm
	systemctl disable --now tailscaled 2>/dev/null || true
	rm -f /etc/apt/sources.list.d/tailscale.list /usr/share/keyrings/tailscale-archive-keyring.gpg
	systemctl daemon-reload 2>/dev/null || true
else
	rm -rf $(USER_HOME)/.cache/thumbnails/fail/
	rm -f $(USER_HOME)/.local/share/applications/pycharm-community.desktop
	rm -f $(USER_HOME)/.config/kwalletrc
	rm -f $(USER_HOME)/.config/autostart/enable-*.desktop
	rm -rf $(USER_HOME)/.local/share/jupyter/kernels/turboquant
	kpackagetool6 -t Plasma/Applet -r com.github.antroids.application-title-bar 2>/dev/null || true
	kpackagetool6 -t Plasma/Applet -r Plasma.Flex.Hub 2>/dev/null || true
	kpackagetool6 -t Plasma/Applet -r com.github.chrtall.kppleMenu 2>/dev/null || true
	gdbus call --session --dest org.kde.plasmashell --object-path /PlasmaShell \
	  --method org.kde.PlasmaShell.evaluateScript '$(strip $(REMOVE_PANELS_JS))' >/dev/null || true
endif
