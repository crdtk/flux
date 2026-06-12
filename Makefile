# ==========================================================
# Ubuntu Setup
# ==========================================================
#
# DESIGN PRINCIPLES — follow these when extending this file:
#
# 1. Names declare why, not what.
#    Every variable name explains why items are grouped together.
#
# 2. Packages install two ways: bulk at bootstrap, per-target on demand.
#    Both paths are valid; idempotency makes the overlap safe.
#
# 3. Grow by addition, not modification.
#    Appending to a group list works on fresh and existing systems alike.
#
# 4. Gate hardware-specific groups at parse time.
#    Use named capability variables; never inline magic numbers.
#
# 5. No sentinel files.
#    Every recipe produces a real outcome. Use that as the target.
#    If no file is created, gate with a parse-time check instead.
#
# 6. Bootstrapper dependencies are order-only.
#    A dependency that auto-updates after install must not drive
#    timestamp-based rebuilds of what it installed.
#
# 7. Provisioning scope only.
#    Targets that do not change system state do not belong here.
#
# 8. One clean, privilege-branched.
#    Root cleans system state; user cleans user-space artifacts.
#
# 9. Top-down order: variables before use, prerequisite recipes after dependents.
#    Declare each variable just above its first reference.
#    Write dependents before the prerequisites they depend on.
#
# 10. .PHONY opens the section.
#     Place it above the variables and recipe it declares.
#
# 11. List only the outermost target in each group.
#     Intermediates already cascade through the prerequisite chain.
#
# 12. Name every shell subexpression used in a recipe.
#     A $$(…) that does not depend on $@ belongs in a named variable above.
#
# 13. Inline single-use intermediates; derive paths from parent variables.
#     A variable used only once inlines. $(PARENT)/suffix, not a literal.
#
# 14. One privilege gate.
#     Compute IS_ROOT once at parse time; never repeat $(shell id -u).
#
# 15. Audit for dead code.
#     Explicit recipes shadow pattern rules — remove from LAZILY_RESOLVED.
#     Targets always present when INSTALL runs never build — remove from groups.
#
# 16. Order-only prerequisites make $< empty.
#     With |, reference the dependency path explicitly in the recipe.
#     $< is only set by normal prerequisites, not order-only ones.
#
# 17. Multi-line file content lives in define…endef.
#     Write configs and unit files as named define blocks.
#     Emit with $(file >$@,$(VAR)) — no heredocs, no quoting issues.
#
# 18. Target the decision, not the payload.
#     A feature's target is the config that switches it on.
#     Files a package merely ships are prerequisites, not targets.
#
# 19. Lazy resolution extends to any apt-file-mappable path.
#     A prerequisite outside /usr/bin earns its own pattern rule,
#     not an explicit install recipe.
#
# 20. Minimal targets, minimal lines, maximal automation.
#     The cheapest target is a file the action creates anyway: it
#     encodes done-ness for free, replacing a gate variable, a .PHONY
#     declaration and a phony name. Reshape the action until it
#     produces one (delete what overrides, then own the drop-in).
#
# 21. No nested $(MAKE).
#     Recursion exists only to dodge stale parse-time gates. The honest
#     protocol is `make clean && make`: clean owns the deletions that
#     reopen gates; the second invocation re-parses them fresh.
#
# ==========================================================

MAKEFLAGS += --no-builtin-rules
.SUFFIXES:

IS_ROOT := $(filter 0,$(shell id -u))

.PHONY: all
all: $(if $(IS_ROOT),system,user)

# ----------------------------------------------------------
# Package install (sudo make)
# ----------------------------------------------------------

APT := DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=-1

.PHONY: system ## Installs INSTALL targets not yet present on this machine

USER_HOME     := $(shell getent passwd $${SUDO_USER:-$$(whoami)} | cut -d: -f6)
DOWNLOADS_DIR := $(USER_HOME)/Downloads
DEB_URLS      := https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
                 https://installers.lmstudio.ai/linux/x64/0.4.7-4/LM-Studio-0.4.7-4-x64.deb

# ----------------------------------------------------------
# HARDENING — system stability: freeze/crash prevention, driver fixes, boot config
# ----------------------------------------------------------

HAS_BMC      := $(shell dmidecode -t 38 2>/dev/null | grep -c 'IPMI Device Information')
GRUB_TIMEOUT := 3
PAM_SSS_FILES   := $(shell grep -rl pam_sss /etc/pam.d/ 2>/dev/null)
GRUB_TIMEOUT_OK := $(shell grep -qx 'GRUB_TIMEOUT=$(GRUB_TIMEOUT)' /etc/default/grub 2>/dev/null && echo 1)

HARDENING := \
  /etc/systemd/system/packagekit.service \
  /etc/systemd/system/suspend.target \
  /etc/modprobe.d/blacklist-nouveau.conf \
  /etc/modprobe.d/blacklist-parport.conf \
  /etc/modprobe.d/nvidia-power.conf \
  /etc/systemd/system/openipmi.service \
  /etc/apt/preferences.d/no-snapd \
  /etc/sysctl.d/90-inotify.conf \
  $(if $(PAM_SSS_FILES),fix-pam-sss,) \
  $(if $(GRUB_TIMEOUT_OK),,set-grub-timeout)

# ----------------------------------------------------------
# MANAGEMENT — remote access and observability
# ----------------------------------------------------------

PRINTER_NAME := hp-laserjet-mfp-2604sdw
PRINTER_PPD  := /etc/cups/ppd/$(PRINTER_NAME).ppd
RUN_AS_USER  := $(or $(SUDO_USER),$(USER))
ST_USER      ?= $(RUN_AS_USER)
ST_PASS      ?= change-me
ST_CONFIG_XML = $(USER_HOME)/.config/syncthing/config.xml
ST_STATE_XML  = $(USER_HOME)/.local/state/syncthing/config.xml
ST_GUI_REMOTE_OK := $(shell grep -ql '0\.0\.0\.0:8384' $(ST_CONFIG_XML) $(ST_STATE_XML) 2>/dev/null && echo 1)

MANAGEMENT := \
  /etc/ddclient.conf \
  /etc/systemd/system/sockets.target.wants/cockpit.socket \
  /etc/ssh/sshd_config.d/lan-password.conf \
  /etc/NetworkManager/conf.d/captive-portal.conf \
  $(PRINTER_PPD) \
  $(if $(ST_GUI_REMOTE_OK),,configure-syncthing-gui) \
  /usr/bin/rclone

# ----------------------------------------------------------
# PKG_APPS — desktop applications
# ----------------------------------------------------------

IMAGETHUMB_DESKTOP       := /usr/share/kservices5/imagethumbnail.desktop
HEIF_THUMB_TARGET        := $(and $(filter 0,$(shell grep -c 'image/heif' $(IMAGETHUMB_DESKTOP) 2>/dev/null)),$(IMAGETHUMB_DESKTOP))
.PHONY: $(HEIF_THUMB_TARGET)
KIMG_HEIF_SO             := /usr/lib/x86_64-linux-gnu/qt5/plugins/imageformats/kimg_heif.so
DESKTOP_PKG_google-chrome := google-chrome-stable
DESKTOP_PKG_code          := code
DESKTOP_FLAGS_google-chrome := --use-gl=desktop
DESKTOP_FLAGS_code          := --disable-gpu

PKG_APPS := \
  /usr/share/applications/code.desktop \
  /usr/share/applications/google-chrome.desktop \
  /usr/bin/digikam \
  /usr/bin/flameshot \
  /usr/bin/gh \
  /usr/bin/gwenview \
  /usr/bin/heif-convert \
  /usr/bin/lmstudio \
  /usr/bin/mc \
  /usr/bin/npm \
  /usr/share/plasma/plasmoids/org.kde.plasma.weather/metadata.json \
  $(HEIF_THUMB_TARGET) \
  /etc/sddm.conf.d/30-x11-session.conf

# ----------------------------------------------------------
# COMPUTE — GPU compute stack (large downloads, runs last)
# ----------------------------------------------------------

UBUNTU_VER     := $(shell lsb_release -rs 2>/dev/null | tr -d '.')
UBUNTU_CODENAME := $(shell lsb_release -cs 2>/dev/null)
SYS_SM         := $(shell nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 | tr -d '.' | grep -oE '^[0-9]+')
NVCC           := /usr/local/cuda/bin/nvcc
CUDA_LIST      := /etc/apt/sources.list.d/cuda-ubuntu$(UBUNTU_VER)-x86_64.list
UV             := $(USER_HOME)/.local/bin/uv
WHISPER_VENV   := $(USER_HOME)/.local/share/whisper-venv
WHISPER_TARGET := $(WHISPER_VENV)/lib/python3.12/site-packages/faster_whisper

COMPUTE := \
  /usr/bin/nvidia-smi \
  $(NVCC) \
  /usr/bin/cmake \
  /usr/bin/g++-14 \
  $(WHISPER_TARGET)

# ----------------------------------------------------------

COMPUTE_CAPABLE := $(shell [ -n "$(SYS_SM)" ] && [ "$(SYS_SM)" -ge 75 ] && echo 1)
SN8100_PRESENT  := $(shell test -e /dev/disk/by-label/backup && echo 1)

STORAGE := /etc/systemd/system/multi-user.target.wants/mnt-backup.automount

INSTALL := $(HARDENING) $(MANAGEMENT) $(PKG_APPS) $(if $(COMPUTE_CAPABLE),$(COMPUTE),) $(if $(SN8100_PRESENT),$(STORAGE),)
PENDING := $(filter-out $(wildcard $(INSTALL)),$(INSTALL))

system: $(PENDING)
	update-initramfs -u
	$(APT) autoremove


# ----------------------------------------------------------
# HARDENING recipes
# ----------------------------------------------------------

/etc/systemd/system/packagekit.service:
	rm -f /etc/apt/sources.list.d/jammy-backports.list
	systemctl disable --now ollama touchegg 2>/dev/null || true
	$(APT) purge -y ollama touchegg cockpit-packagekit 2>/dev/null || true
	rm -f /usr/local/bin/ollama /etc/systemd/system/ollama.service
	systemctl stop packagekit 2>/dev/null || true
	systemctl mask packagekit
	mkdir -p /etc/PackageKit
	dpkg-divert --divert /etc/PackageKit/20packagekit.distrib --rename /etc/apt/apt.conf.d/20packagekit 2>/dev/null || true
	systemctl daemon-reload
	@echo ">>> debloat complete"

/etc/sysctl.d/90-inotify.conf:
	printf 'fs.inotify.max_user_watches=524288\n' > $@
	sysctl -p $@
	@echo ">>> inotify watches set to 524288 (VS Code file watcher)"

/etc/apt/preferences.d/no-snapd:
	mkdir -p $(dir $@)
	snap list --all 2>/dev/null | awk 'NR>1{print $$1}' | xargs -r snap remove --purge 2>/dev/null || true
	$(APT) purge -y snapd 2>/dev/null || true
	rm -rf /snap /var/snap /var/lib/snapd /var/cache/snapd ~/snap
	printf 'Package: snapd\nPin: release *\nPin-Priority: -1\n' > $@
	@echo ">>> snap purged and pinned out"

/etc/systemd/system/suspend.target:
	systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
	@echo ">>> Suspend disabled"

define BLACKLIST_NOUVEAU
blacklist nouveau
options nouveau modeset=0
endef

/etc/modprobe.d/blacklist-nouveau.conf:
	$(file >$@,$(BLACKLIST_NOUVEAU))
	@echo ">>> nouveau blacklisted"

define BLACKLIST_PARPORT
# lp/parport crash kernel 7.0.0-22 with NULL deref in parport_register_dev_model
blacklist lp
blacklist ppdev
blacklist parport_pc
blacklist parport
endef

/etc/modprobe.d/blacklist-parport.conf:
	$(file >$@,$(BLACKLIST_PARPORT))
	@echo ">>> parport/lp blacklisted (kernel 7.0.0-22 NULL deref bug)"

define NVIDIA_POWER_CONF
options nvidia NVreg_PreserveVideoMemoryAllocations=1
options nvidia NVreg_TemporaryFilePath=/tmp
endef

/etc/modprobe.d/nvidia-power.conf:
	$(file >$@,$(NVIDIA_POWER_CONF))
	@echo ">>> NVIDIA power options set"

/etc/systemd/system/openipmi.service:
ifeq ($(HAS_BMC),0)
	@echo ">>> No BMC detected — masking and purging openipmi"
	systemctl mask openipmi
	apt purge -y openipmi 2>/dev/null || true
else
	@echo ">>> BMC detected — enabling openipmi"
	apt install -y openipmi
	systemctl enable --now openipmi
endif

.PHONY: fix-pam-sss
fix-pam-sss:
	grep -rl pam_sss /etc/pam.d/ 2>/dev/null | xargs -r sed -i '/pam_sss/d'
	@echo ">>> pam_sss removed from PAM"

.PHONY: set-grub-timeout
set-grub-timeout:
	sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=$(GRUB_TIMEOUT)/' /etc/default/grub
	update-grub
	@echo ">>> GRUB timeout = $(GRUB_TIMEOUT)"


# ----------------------------------------------------------
# MANAGEMENT recipes
# ----------------------------------------------------------

PROJECTS := $(USER_HOME)/Desktop/Projects

/etc/ddclient.conf: $(PROJECTS)/secrets/ddclient.conf /usr/bin/ddclient
	systemctl disable --now dynv6-update.timer dynv6-update.service 2>/dev/null || true
	rm -f /etc/systemd/system/dynv6-update.service /etc/systemd/system/dynv6-update.timer
	ln -sf $< $@
	systemctl enable --now ddclient
	@echo ">>> ddclient configured and enabled"

$(PROJECTS)/secrets/ddclient.conf: | $(PROJECTS)
	sudo -u $(RUN_AS_USER) git clone git@github.com:crdtk/secrets.git $(PROJECTS)/secrets

$(PROJECTS):
	mkdir -p $@

define NM_CAPTIVE_PORTAL_CONF
[connectivity]
uri=http://nmcheck.gnome.org/check_network_status.txt
response=NetworkManager is online
interval=60
endef

/etc/NetworkManager/conf.d/captive-portal.conf:
	mkdir -p $(dir $@)
	$(file >$@,$(NM_CAPTIVE_PORTAL_CONF))
	systemctl reload NetworkManager
	@echo ">>> Captive portal detection enabled"

MACHINE_IP := $(shell hostname -I | awk '{print $$1}')

/etc/systemd/system/sockets.target.wants/cockpit.socket: /usr/bin/cockpit
	systemctl enable --now cockpit.socket
	@echo ">>> Cockpit: https://$(MACHINE_IP):9090"


LAN_SUBNET := $(shell ip route | awk '/proto kernel/ && !/wl|ww|lo|vir|br-|docker/{print $$1; exit}')

define SSH_LAN_PASSWORD_CONF
PasswordAuthentication no

Match Address $(LAN_SUBNET),127.0.0.1
	PasswordAuthentication yes
endef

/etc/ssh/sshd_config.d/:
	mkdir -p $@

/etc/ssh/sshd_config.d/lan-password.conf: | /etc/ssh/sshd_config.d/
	$(file >$@,$(SSH_LAN_PASSWORD_CONF))
	systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
	@echo ">>> SSH password auth restricted to LAN ($(LAN_SUBNET))"

PRINTER_IP  := $(shell avahi-browse -t -r -p _ipp._tcp 2>/dev/null | awk -F';' '/^=/ && /2604sdw/{print $$8; exit}')
PRINTER_URI := ipp://$(PRINTER_IP)/ipp/print

$(PRINTER_PPD):
	lpadmin -p $(PRINTER_NAME) -E -v $(PRINTER_URI) -m everywhere
	lpoptions -d $(PRINTER_NAME)
	@echo ">>> Printer $(PRINTER_NAME) added at $(PRINTER_URI)"

RUN_AS_UID := $(shell id -u $(RUN_AS_USER))

.PHONY: configure-syncthing-gui
ST_API_URL     := http://localhost:8384
ST_GUI_JSON     = {"address":"0.0.0.0:8384","user":"$(ST_USER)","password":"$(ST_PASS)"}
ST_API_KEY      = $(shell grep -rh '<apikey>' $(ST_CONFIG_XML) $(ST_STATE_XML) 2>/dev/null | sed -n 's:.*<apikey>\(.*\)</apikey>.*:\1:p' | head -1)
configure-syncthing-gui: wait-syncthing-api
	@curl -sS -X PATCH $(ST_API_URL)/rest/config/gui \
		-H "X-API-Key: $(ST_API_KEY)" \
		-H "Content-Type: application/json" \
		-d '$(ST_GUI_JSON)'
	@echo ">>> Syncthing GUI remote enabled"

.PHONY: wait-syncthing-api
ST_API_RETRIES := 30
wait-syncthing-api: $(USER_HOME)/.config/systemd/user/default.target.wants/syncthing.service
	@echo ">>> Waiting for Syncthing API..."
	@for i in $(shell seq $(ST_API_RETRIES)); do curl -sf $(ST_API_URL)/rest/noauth/health >/dev/null 2>&1 && break || sleep 1; done

$(USER_HOME)/.config/systemd/user/default.target.wants/syncthing.service: /usr/bin/syncthing
	loginctl enable-linger $(RUN_AS_USER)
	sudo -u $(RUN_AS_USER) env XDG_RUNTIME_DIR=/run/user/$(RUN_AS_UID) \
		systemctl --user enable --now syncthing
	@echo ">>> Syncthing enabled"

# ----------------------------------------------------------
# PKG_APPS recipes
# ----------------------------------------------------------

/usr/share/applications/%.desktop:
	test -f $@ || $(APT) install -y --reinstall $(DESKTOP_PKG_$*)
	sed -i 's|^\(Exec=[^ ]*\)|\1 $(DESKTOP_FLAGS_$*)|g' $@

/usr/share/applications/code.desktop: /usr/bin/code

## Global menu needs X11 — KWin on Wayland lacks the appmenu protocol (Qt, GTK and Electron alike)
define SDDM_X11_CONF
[Autologin]
Session=plasmax11
endef

SDDM_LAST_SESSION := $(wildcard /var/lib/sddm/state.conf)

## SDDM reads /etc/sddm.conf last — its Session line must go for conf.d to decide
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

KUBUNTU_BACKPORTS_LIST := /etc/apt/sources.list.d/kubuntu-ppa-ubuntu-backports-$(UBUNTU_CODENAME).sources

/usr/bin/digikam: $(KUBUNTU_BACKPORTS_LIST)
	$(APT) update
	$(APT) install -y digikam

$(KUBUNTU_BACKPORTS_LIST):
	add-apt-repository -y ppa:kubuntu-ppa/backports

/usr/share/applications/google-chrome.desktop: /usr/bin/google-chrome

/usr/bin/google-chrome: | $(DOWNLOADS_DIR)/google-chrome-stable_current_amd64.deb
	$(APT) install -y $(DOWNLOADS_DIR)/google-chrome-stable_current_amd64.deb

/usr/bin/lmstudio: | $(DOWNLOADS_DIR)/LM-Studio-0.4.7-4-x64.deb
	$(APT) install -y $(DOWNLOADS_DIR)/LM-Studio-0.4.7-4-x64.deb
	sed -i 's|Exec=/opt/LM-Studio/lm-studio|Exec=/opt/LM-Studio/lm-studio --use-gl=desktop|' /usr/share/applications/lm-studio.desktop

$(IMAGETHUMB_DESKTOP): $(KIMG_HEIF_SO)
	grep -q 'image/heif' $@ || sed -i 's|image/avif;|image/avif;image/heif;image/heic;|' $@
	@echo ">>> HEIF added to KIO imagethumbnail plugin"

$(KIMG_HEIF_SO):
	$(APT) install -y kimageformat-plugins

# ----------------------------------------------------------
# COMPUTE recipes
# ----------------------------------------------------------

/usr/bin/nvidia-smi:
	ubuntu-drivers install

CUDA_PKG ?= cuda-toolkit
$(NVCC): | $(CUDA_LIST)
	@[ -n "$(IS_ROOT)" ] || { echo ">>> CUDA install requires root. Run: sudo make"; exit 1; }
	$(APT) update
	$(APT) install -y $(CUDA_PKG)

CUDA_KEYRING_DEB := $(DOWNLOADS_DIR)/cuda-keyring_1.1-1_all.deb
$(CUDA_LIST): $(CUDA_KEYRING_DEB)
	@[ -n "$(IS_ROOT)" ] || { echo ">>> CUDA repo setup requires root. Run: sudo make"; exit 1; }
	$(APT) install -y $<

CUDA_REPO = https://developer.download.nvidia.com/compute/cuda/repos/ubuntu$(UBUNTU_VER)/x86_64
$(CUDA_KEYRING_DEB): | $(DOWNLOADS_DIR)
	curl -fsSL $(CUDA_REPO)/cuda-keyring_1.1-1_all.deb -o $@

WHISPER_PIP = VIRTUAL_ENV=$(WHISPER_VENV) $(UV) pip install
$(WHISPER_TARGET): | $(WHISPER_VENV)
	$(WHISPER_PIP) faster-whisper openai-whisper
	@echo ">>> faster-whisper + openai-whisper installed"

$(WHISPER_VENV): $(UV)
	$(UV) venv $(WHISPER_VENV) --python 3.12
	@echo ">>> whisper venv at $(WHISPER_VENV)"

$(UV):
	curl -LsSf https://astral.sh/uv/install.sh | UV_INSTALL_DIR=$(dir $(UV)) sh
	@echo ">>> uv installed to $(UV)"

# ----------------------------------------------------------
# User setup (make, no sudo)
# ----------------------------------------------------------

.PHONY: user

CLAUDE_BIN := $(USER_HOME)/.local/bin/claude
SSH_KEY    := $(USER_HOME)/.ssh/id_ed25519

## Title widget: text-only normally; close/min/max appear far-left only when
## maximized — the one state borderless windows lack their own buttons (Unity).
## AppName source, 10pt = default panel font: one continuous text band, no icons.
## Clock: far right, date | time on one line, 24h, manual 14pt. The | is an
## unquoted Qt format literal — the JS must stay single-quote-free, since the
## recipe wraps $(strip TOP_PANEL_JS) in shell single quotes.
## Weather: stock org.kde.plasma.weather (plasma-widgets-addons), provider dwd,
## station Berlin-Alexanderplatz (10389, DWD MOSMIX catalogue), temp shown in
## panel. placeInfo format is place_name|station_id (ion_dwd.cpp fetchForecast);
## the name is display-only, the id drives the API. Flex Hub stays factory-default.
## Tray must never host weather: its hidden auto-instance segfaults plasmashell on
## exit (upstream 6.6.5). knownItems pre-seeds weather as known-but-disabled;
## emptied extraItems is repopulated by tray auto-add on the post-script restart.
## Enum formats differ per widget: antroids stores ints, digitalclock stores names.
define TOP_PANEL_JS
  var p = new Panel;
  p.location = "top";
  p.addWidget("com.github.chrtall.kppleMenu");
  var t = p.addWidget("com.github.antroids.application-title-bar");
  t.currentConfigGroup = ["Appearance"];
  t.writeConfig("widgetElements", ["windowTitle"]);
  t.writeConfig("overrideElementsMaximized", true);
  t.writeConfig("widgetElementsMaximized", ["windowCloseButton", "windowMinimizeButton", "windowMaximizeButton", "windowTitle"]);
  t.writeConfig("windowTitleSource", 0);
  t.writeConfig("windowTitleSourceMaximized", 0);
  t.writeConfig("windowTitleFontSize", 10);
  t.writeConfig("windowTitleUndefined", "Plasma");
  p.addWidget("org.kde.plasma.appmenu");
  p.addWidget("org.kde.plasma.panelspacer");
  var w = p.addWidget("org.kde.plasma.weather");
  w.currentConfigGroup = ["WeatherStation"];
  w.writeConfig("provider", "dwd");
  w.writeConfig("placeInfo", "Berlin-Alex.|10389");
  w.writeConfig("placeDisplayName", "Berlin-Alex.");
  w.currentConfigGroup = ["Appearance"];
  w.writeConfig("showTemperatureInCompactMode", true);
  var s = p.addWidget("org.kde.plasma.systemtray");
  s.currentConfigGroup = ["General"];
  s.writeConfig("extraItems", "");
  s.writeConfig("knownItems", ["org.kde.plasma.weather"]);
  p.addWidget("Plasma.Flex.Hub");
  var c = p.addWidget("org.kde.plasma.digitalclock");
  c.currentConfigGroup = ["Appearance"];
  c.writeConfig("dateDisplayFormat", "BesideTime");
  c.writeConfig("use24hFormat", 2);
  c.writeConfig("autoFontAndSize", false);
  c.writeConfig("fontSize", 14);
  c.writeConfig("dateFormat", "custom");
  c.writeConfig("customDateFormat", "dd.MM.yy |");
endef

PLASMOIDS := $(USER_HOME)/.local/share/plasma/plasmoids

DOLPHIN_PREVIEW_OK := $(shell grep -c '^Show Preview=true' $(USER_HOME)/.config/kdeglobals 2>/dev/null)
GLOBALMENU_OK      := $(shell grep -c 'org.kde.plasma.appmenu' $(USER_HOME)/.config/plasma-org.kde.plasma.desktop-appletsrc 2>/dev/null)
KWIN_BORDERLESS_OK := $(shell grep -c '^BorderlessMaximizedWindows=true' $(USER_HOME)/.config/kwinrc 2>/dev/null)
user: $(CLAUDE_BIN) $(USER_HOME)/.ssh/authorized_keys make-completion \
      $(PLASMOIDS)/com.github.antroids.application-title-bar/metadata.json \
      $(PLASMOIDS)/Plasma.Flex.Hub/metadata.json \
      $(PLASMOIDS)/com.github.chrtall.kppleMenu/metadata.json
ifeq ($(DOLPHIN_PREVIEW_OK),0)
	kwriteconfig5 --file kdeglobals --group "KFileDialog Settings" --key "Show Preview" true
	@echo ">>> Dolphin show preview enabled"
endif
ifeq ($(GLOBALMENU_OK),0)
	gdbus call --session --dest org.kde.plasmashell --object-path /PlasmaShell \
	  --method org.kde.PlasmaShell.evaluateScript '$(strip $(TOP_PANEL_JS))' >/dev/null
## addWidget builds each applet from default config before writeConfig lands;
## a restart makes every widget initialize from the final on-disk config
	systemctl --user restart plasma-plasmashell.service
	@echo ">>> Top bar with global menu created"
endif
ifeq ($(KWIN_BORDERLESS_OK),0)
	kwriteconfig6 --file kwinrc --group Windows --key BorderlessMaximizedWindows true
	gdbus call --session --dest org.kde.KWin --object-path /KWin --method org.kde.KWin.reconfigure >/dev/null
	@echo ">>> Borderless maximized windows enabled"
endif
	/usr/bin/kbuildsycoca6

$(USER_HOME)/.ssh/authorized_keys: $(SSH_KEY)
	cat $(SSH_KEY).pub >> $@
	chmod 600 $@
	@echo ">>> SSH key authorized for localhost"

$(SSH_KEY):
	ssh-keygen -t ed25519 -f $@ -N ""
	@echo ">>> SSH key generated: $@"



$(CLAUDE_BIN):
	mkdir -p $(dir $@)
	@command -v npm >/dev/null 2>&1 || { echo ">>> npm not found — run: sudo make first"; exit 1; }
	npm install --prefix $(USER_HOME)/.local -g @anthropic-ai/claude-code

.PHONY: make-completion
BASHRC          = $(USER_HOME)/.bashrc
MAKE_COMPLETION = /usr/share/bash-completion/completions/make
make-completion:
	@grep -q 'bash-completion/completions/make' $(BASHRC) 2>/dev/null || echo 'source $(MAKE_COMPLETION)' >> $(BASHRC)
	@echo ">>> Make autocomplete enabled"

## KDE Store widgets — repo URL and package subdir, keyed by plugin id
WIDGET_SRC_com.github.antroids.application-title-bar := https://github.com/antroids/application-title-bar package
WIDGET_SRC_Plasma.Flex.Hub                           := https://github.com/zayronxio/Plasma.Flex.Hub .
WIDGET_SRC_com.github.chrtall.kppleMenu              := https://github.com/ChrTall/kppleMenu package

$(PLASMOIDS)/%/metadata.json:
	rm -rf /tmp/$*
	git clone --depth 1 $(word 1,$(WIDGET_SRC_$*)) /tmp/$*
	kpackagetool6 -t Plasma/Applet -i /tmp/$*/$(word 2,$(WIDGET_SRC_$*))
	rm -rf /tmp/$*
	@echo ">>> Widget $* installed"


# ----------------------------------------------------------
# SN8100
# ----------------------------------------------------------

/etc/systemd/system/multi-user.target.wants/mnt-backup.automount: /etc/systemd/system/mnt-backup.automount
	systemctl enable --now mnt-backup.automount
	systemctl start mnt-backup.mount
	chmod 1777 /mnt/backup
	@echo ">>> SN8100 automount enabled at /mnt/backup"

define BACKUP_AUTOMOUNT_UNIT
[Unit]
Description=Automount NVMe backup drive (SN8100)

[Automount]
Where=/mnt/backup
TimeoutIdleSec=0

[Install]
WantedBy=multi-user.target
endef
/etc/systemd/system/mnt-backup.automount: /etc/systemd/system/mnt-backup.mount
	$(file >$@,$(BACKUP_AUTOMOUNT_UNIT))


define BACKUP_MOUNT_UNIT
[Unit]
Description=NVMe backup drive (SN8100)

[Mount]
What=/dev/disk/by-label/backup
Where=/mnt/backup
Type=ext4
Options=defaults,noatime

[Install]
WantedBy=multi-user.target
endef
/etc/systemd/system/mnt-backup.mount:
	sed -i '\|/mnt/backup|d' /etc/fstab 2>/dev/null || true
	$(file >$@,$(BACKUP_MOUNT_UNIT))
	systemctl daemon-reload

.PHONY: detect-sn8100
detect-sn8100:
	@echo 1 > /sys/bus/pci/rescan
	@sleep 1
	@lsblk -d -o NAME,SIZE,MODEL | grep -E 'nvme|SN8100' || true

.PHONY: eject
SN8100_DEV := $(shell lsblk -dno NAME,MODEL 2>/dev/null | awk '/SN8100/{print $$1; exit}')
eject:
	@[ -n "$(SN8100_DEV)" ] || { echo "SN8100 not found"; exit 1; }
	echo 1 > /sys/block/$(SN8100_DEV)/device/remove
	@echo ">>> Ejected $(SN8100_DEV)"


# ----------------------------------------------------------
# Infrastructure — pattern rules, downloads
# ----------------------------------------------------------

UNTRACKED_PKGS  := git avahi-daemon arp-scan nmap appmenu-gtk3-module appmenu-registrar
LAZILY_RESOLVED := syncthing npm mc libheif-examples gwenview ddclient cockpit cockpit-files cmake g++-14 rclone plasma-session-x11 flameshot gh plasma-widgets-addons

/usr/bin/apt-file: | /etc/systemd/system/packagekit.service
	$(APT) update
	$(APT) install -y apt-file $(UNTRACKED_PKGS) $(LAZILY_RESOLVED)
	apt-file update
	@echo ">>> apt-file ready"

## Resolve packages by Custom Repository URL
/usr/bin/%: /etc/apt/sources.list.d/%.list
	$(APT) update
	$(APT) install -y $*

## Resolve packages using apt-file global search
/usr/bin/%: | /usr/bin/apt-file
	$(APT) install -y $$(apt-file search $@ 2>/dev/null | awk -F': ' '{print $$1}' | head -1)

/usr/share/xsessions/%.desktop: | /usr/bin/apt-file
	$(APT) install -y $$(apt-file search $@ 2>/dev/null | awk -F': ' '{print $$1}' | head -1)

/usr/share/plasma/plasmoids/%/metadata.json: | /usr/bin/apt-file
	$(APT) install -y $$(apt-file search $@ 2>/dev/null | awk -F': ' '{print $$1}' | head -1)

$(DOWNLOADS_DIR)/%: | $(DOWNLOADS_DIR)
	curl -fL --retry 5 --retry-delay 3 --progress-bar -A "Mozilla/5.0" $(filter %/$*,$(DEB_URLS)) -o $@

$(DOWNLOADS_DIR):
	mkdir -p $@

# ----------------------------------------------------------
# clean
# ----------------------------------------------------------
	
.PHONY: clean
## user clean deletes ALL top panels; `make clean && make` then rebuilds the
## bar from TOP_PANEL_JS through the reopened GLOBALMENU_OK gate (principle 21)
define REMOVE_TOP_PANELS_JS
  var all = panels();
  for (var i = 0; i < all.length; i++) {
    if (all[i].location == "top") {
      all[i].remove();
    }
  }
endef
clean:
ifeq ($(shell id -u),0)
	rm -f /usr/share/applications/google-chrome.desktop /usr/share/applications/code.desktop
	rm -f $(CUDA_KEYRING_DEB) /etc/apt/sources.list.d/cuda-ubuntu*-x86_64.list
	rm -f /etc/apt/preferences.d/no-snapd
	rm -f /etc/systemd/system/packagekit.service
else
	rm -rf $(USER_HOME)/.cache/thumbnails/fail/
	gdbus call --session --dest org.kde.plasmashell --object-path /PlasmaShell \
	  --method org.kde.PlasmaShell.evaluateScript '$(strip $(REMOVE_TOP_PANELS_JS))' >/dev/null || true
endif

# ----------------------------------------------------------
# REFERENCES — download product documentation (not committed)
# ----------------------------------------------------------

.PHONY: references
define REF_LIST
  https://download.asrock.com/Manual/E3C256D4I-2T.pdf
    "References/Motherboard/E3C256D4I-2T.pdf"
  https://dlcdnets.asus.com/pub/ASUS/mb/LGA2066/PRIME_X299-A_II/E15936_PRIME_X299-A_II_UM_V2_WEB.pdf
    "References/Motherboard/ASUS Prime X299-A II.pdf"
  https://phanteks.com/manuals/Enthoo_Pro2_Manual_v1.1.pdf
    "References/Case/ENTHOO PRO II/Enthoo_Pro2_Manual_v1.1.pdf"
  https://documents.sandisk.com/content/dam/asset-library/en_us/assets/public/sandisk/product/internal-drives/wd-black-ssd/data-sheet-wd-black-sn8100-nvme-ssd.pdf
    "References/Storage/SN8100/WD_Black_SN8100_Datasheet.pdf"
  https://global.icydock.com/vancheerfile/files/installation_guide/MB111VP_B_Manual.pdf
    "References/Storage/MB111VP-B/MB111VP_B_Manual.pdf"
  "https://www.icydock.com/Installation%20Guide/MB705M2P-B-webpage_manual.pdf"
    "References/Storage/MB705M2P-B/MB705M2P-B_Manual.pdf"
endef
references:
	@set -- $(strip $(REF_LIST)); \
	while [ "$$#" -ge 2 ]; do \
	  url="$$1"; dest="$$2"; shift 2; \
	  [ -f "$$dest" ] || { mkdir -p "$$(dirname "$$dest")"; curl -fL --progress-bar -o "$$dest" "$$url"; echo ">>> $$dest"; }; \
	done

