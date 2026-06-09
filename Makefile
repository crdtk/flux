# ==========================================================
# Ubuntu Setup
# ==========================================================
#
# DESIGN PRINCIPLES — follow these when extending this file:
#
# 1. Intention-revealing names
#    Variable names declare WHY items are grouped, not just what they are.
#    UNTRACKED_PKGS  = no Make file target; install state invisible to Make.
#    LAZILY_RESOLVED = has a /usr/bin file target; resolved on demand by the
#                      apt-file pattern rule.
#    CUDA_SYMLINK    = real symlink path, not a sentinel file.
#
# 2. Eager-lazy duality with idempotent overlap
#    Packages in LAZILY_RESOLVED install two ways: bulk at bootstrap (one
#    apt call, fast on fresh systems) and per file-target on demand (correct
#    on existing systems). apt idempotency makes the overlap safe — the lazy
#    path is the authority; the eager path is an optimisation.
#    Rule: /usr/bin file target in INSTALL → also add to LAZILY_RESOLVED.
#
# 3. Append-safe extensibility
#    The system grows by addition, not modification. Append a file target to
#    any group list (HARDENING / MANAGEMENT / PKG_APPS / COMPUTE / STORAGE)
#    and it works on both fresh and existing systems with no bootstrap changes.
#    Rule: new apt package with /usr/bin target → append to group list and
#    LAZILY_RESOLVED. Package with no /usr/bin target → UNTRACKED_PKGS only.
#
# 4. Hardware-gated groups
#    Expensive or hardware-specific target groups are conditionally included
#    in INSTALL using parse-time shell checks on real hardware properties.
#    COMPUTE_CAPABLE gates on GPU SM ≥ 75 (Turing+, Tensor Cores present).
#    Rule: use a named capability variable (COMPUTE_CAPABLE, not a magic
#    number inline) so the threshold and its reason are self-documenting.
#
# ==========================================================

MAKEFLAGS += --no-builtin-rules
.SUFFIXES:

.PHONY: all
all: $(if $(filter 0,$(shell id -u)),system,user)

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

HARDENING := \
  /etc/systemd/system/packagekit.service \
  /etc/systemd/system/suspend.target \
  /etc/modprobe.d/blacklist-nouveau.conf \
  /etc/modprobe.d/blacklist-parport.conf \
  /etc/modprobe.d/nvidia-power.conf \
  /etc/systemd/system/openipmi.service \
  /etc/apt/preferences.d/no-snapd \
  .sentinel/pam-sss-fixed \
  .sentinel/grub-timeout-set

# ----------------------------------------------------------
# MANAGEMENT — remote access and observability
# ----------------------------------------------------------

MACHINE_IP   := $(shell hostname -I | awk '{print $$1}')
LAN_SUBNET   := $(shell ip route | awk '/proto kernel/ && !/wl|ww|lo|vir|br-|docker/{print $$1; exit}')
PRINTER_NAME := hp-laserjet-mfp-2604sdw
PRINTER_PPD  := /etc/cups/ppd/$(PRINTER_NAME).ppd
PRINTER_IP   := $(shell avahi-browse -t -r -p _ipp._tcp 2>/dev/null | awk -F';' '/^=/ && /2604sdw/{print $$8; exit}')
PRINTER_URI  := ipp://$(PRINTER_IP)/ipp/print
PROJECTS     := $(USER_HOME)/Desktop/Projects
RUN_AS_USER  := $(or $(SUDO_USER),$(USER))
RUN_AS_UID   := $(shell id -u $(RUN_AS_USER))
ST_USER      ?= $(RUN_AS_USER)
ST_PASS      ?= change-me
ST_API_URL   := http://localhost:8384
ST_CONFIG_XML = $(USER_HOME)/.config/syncthing/config.xml
ST_STATE_XML  = $(USER_HOME)/.local/state/syncthing/config.xml
ST_GUI_JSON   = {"address":"0.0.0.0:8384","user":"$(ST_USER)","password":"$(ST_PASS)"}
ST_WANTS     := $(USER_HOME)/.config/systemd/user/default.target.wants/syncthing.service

MANAGEMENT := \
  /etc/ddclient.conf \
  /etc/systemd/system/sockets.target.wants/cockpit.socket \
  /etc/ssh/sshd_config.d/lan-password.conf \
  /etc/NetworkManager/conf.d/captive-portal.conf \
  $(PRINTER_PPD) \
  .sentinel/syncthing-gui-remote \
  /usr/bin/rclone

# ----------------------------------------------------------
# PKG_APPS — desktop applications
# ----------------------------------------------------------

IMAGETHUMB_DESKTOP       := /usr/share/kservices5/imagethumbnail.desktop
HEIF_THUMB_OK            := $(shell grep -c 'image/heif' $(IMAGETHUMB_DESKTOP) 2>/dev/null)
HEIF_THUMB_TARGET        := $(and $(filter 0,$(HEIF_THUMB_OK)),$(IMAGETHUMB_DESKTOP))
.PHONY: $(HEIF_THUMB_TARGET)
KIMG_HEIF_SO             := /usr/lib/x86_64-linux-gnu/qt5/plugins/imageformats/kimg_heif.so
DESKTOP_PKG_google-chrome := google-chrome-stable
DESKTOP_PKG_code          := code
DESKTOP_FLAGS_google-chrome := --use-gl=desktop
DESKTOP_FLAGS_code          := --disable-gpu

PKG_APPS := \
  /usr/share/applications/code.desktop \
  /usr/share/applications/google-chrome.desktop \
  /usr/bin/gwenview \
  /usr/bin/heif-convert \
  /usr/bin/lmstudio \
  /usr/bin/mc \
  /usr/bin/npm \
  $(KIMG_HEIF_SO) \
  $(HEIF_THUMB_TARGET)

# ----------------------------------------------------------
# COMPUTE — GPU compute stack (large downloads, runs last)
# ----------------------------------------------------------

UBUNTU_VER            := $(shell lsb_release -rs 2>/dev/null | tr -d '.')
SYS_SM                := $(shell nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 | tr -d '.' | grep -oE '^[0-9]+')
CUDA_PKG              ?= cuda-toolkit
NVCC                  := /usr/local/cuda/bin/nvcc
CUDA_LIST             := /etc/apt/sources.list.d/cuda-ubuntu$(UBUNTU_VER)-x86_64.list
CUDA_SYMLINK := /usr/local/cuda
CUDA_REPO              = https://developer.download.nvidia.com/compute/cuda/repos/ubuntu$(UBUNTU_VER)/x86_64
CUDA_KEYRING_DEB      := $(DOWNLOADS_DIR)/cuda-keyring_1.1-1_all.deb
CURRENT_UID           := $(shell id -u)
UV                    := $(USER_HOME)/.local/bin/uv
WHISPER_VENV          := $(USER_HOME)/.local/share/whisper-venv
WHISPER_PIP            = VIRTUAL_ENV=$(WHISPER_VENV) $(UV) pip install
WHISPER_TARGET        := $(USER_HOME)/.local/share/whisper-venv/lib/python3.12/site-packages/faster_whisper

COMPUTE := \
  /usr/bin/nvidia-smi \
  $(CUDA_LIST) \
  $(NVCC) \
  $(CUDA_SYMLINK) \
  /usr/bin/cmake \
  /usr/bin/g++-14 \
  $(WHISPER_TARGET)

# ----------------------------------------------------------

COMPUTE_CAPABLE := $(shell [ -n "$(SYS_SM)" ] && [ "$(SYS_SM)" -ge 75 ] && echo 1)
SN8100_PRESENT  := $(shell test -e /dev/disk/by-label/backup && echo 1)
SN8100_DEV      := $(shell lsblk -dno NAME,MODEL 2>/dev/null | awk '/SN8100/{print $$1; exit}')

INSTALL := $(HARDENING) $(MANAGEMENT) $(PKG_APPS) $(if $(COMPUTE_CAPABLE),$(COMPUTE),) $(if $(SN8100_PRESENT),$(STORAGE),)
PENDING := $(filter-out $(wildcard $(INSTALL)),$(INSTALL))

system: $(PENDING)
	update-initramfs -u
	$(APT) autoremove

# ----------------------------------------------------------
# Infrastructure — pattern rules, downloads, sentinels
# ----------------------------------------------------------

UNTRACKED_PKGS  := git avahi-daemon arp-scan nmap appmenu-gtk3-module appmenu-registrar
LAZILY_RESOLVED := syncthing npm mc libheif-examples gwenview ddclient cockpit cockpit-files cmake g++-14 rclone

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

$(DOWNLOADS_DIR)/%: | $(DOWNLOADS_DIR)
	curl -fL --retry 5 --retry-delay 3 --progress-bar -A "Mozilla/5.0" $(filter %/$*,$(DEB_URLS)) -o $@

$(DOWNLOADS_DIR):
	mkdir -p $@

.sentinel:
	mkdir -p $@

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

.sentinel/pam-sss-fixed: | .sentinel
	grep -rl pam_sss /etc/pam.d/ 2>/dev/null | xargs -r sed -i '/pam_sss/d'
	touch $@
	@echo ">>> pam_sss removed from PAM"

.sentinel/grub-timeout-set: | .sentinel
	@test -f /etc/default/grub && sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=$(GRUB_TIMEOUT)/' /etc/default/grub && update-grub && echo ">>> GRUB timeout = $(GRUB_TIMEOUT)" || echo ">>> /etc/default/grub not found, skipping"
	touch $@


# ----------------------------------------------------------
# MANAGEMENT recipes
# ----------------------------------------------------------

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

/etc/systemd/system/sockets.target.wants/cockpit.socket: /usr/bin/cockpit
	systemctl enable --now cockpit.socket
	@echo ">>> Cockpit: https://$(MACHINE_IP):9090"


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

$(PRINTER_PPD):
	lpadmin -p $(PRINTER_NAME) -E -v $(PRINTER_URI) -m everywhere
	lpoptions -d $(PRINTER_NAME)
	@echo ">>> Printer $(PRINTER_NAME) added at $(PRINTER_URI)"

$(ST_WANTS): /usr/bin/syncthing
	loginctl enable-linger $(RUN_AS_USER)
	sudo -u $(RUN_AS_USER) env XDG_RUNTIME_DIR=/run/user/$(RUN_AS_UID) \
		systemctl --user enable --now syncthing
	@echo ">>> Syncthing enabled"

.sentinel/syncthing-gui-remote: $(ST_WANTS) | .sentinel
	@echo ">>> Waiting for Syncthing API..."
	@for i in $$(seq 30); do curl -sf $(ST_API_URL)/rest/noauth/health >/dev/null 2>&1 && break || sleep 1; done
	@curl -sS -X PATCH $(ST_API_URL)/rest/config/gui \
		-H "X-API-Key: $$(grep -rh '<apikey>' $(ST_CONFIG_XML) $(ST_STATE_XML) 2>/dev/null | sed -n 's:.*<apikey>\(.*\)</apikey>.*:\1:p' | head -1)" \
		-H "Content-Type: application/json" \
		-d '$(ST_GUI_JSON)'
	@touch $@
	@echo ">>> Syncthing GUI remote enabled"

# ----------------------------------------------------------
# PKG_APPS recipes
# ----------------------------------------------------------

/usr/share/applications/%.desktop:
	test -f $@ || $(APT) install -y --reinstall $(DESKTOP_PKG_$*)
	sed -i 's|^\(Exec=[^ ]*\)|\1 $(DESKTOP_FLAGS_$*)|g' $@

/usr/share/applications/code.desktop: /usr/bin/code

/etc/apt/sources.list.d/code.list: /usr/share/keyrings/microsoft.gpg
	echo 'deb [arch=amd64 signed-by=$<] https://packages.microsoft.com/repos/code stable main' > $@

/usr/share/keyrings/microsoft.gpg:
	mkdir -p $(dir $@)
	curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > $@

/usr/share/applications/google-chrome.desktop: /usr/bin/google-chrome

/usr/bin/google-chrome: $(DOWNLOADS_DIR)/google-chrome-stable_current_amd64.deb
	$(APT) install -y $<

/usr/bin/lmstudio: $(DOWNLOADS_DIR)/LM-Studio-0.4.7-4-x64.deb
	$(APT) install -y $<
	sed -i 's|Exec=/opt/LM-Studio/lm-studio|Exec=/opt/LM-Studio/lm-studio --use-gl=desktop|' /usr/share/applications/lm-studio.desktop

$(KIMG_HEIF_SO):
	$(APT) install -y kimageformat-plugins

$(IMAGETHUMB_DESKTOP): $(KIMG_HEIF_SO)
	grep -q 'image/heif' $@ || sed -i 's|image/avif;|image/avif;image/heif;image/heic;|' $@
	@echo ">>> HEIF added to KIO imagethumbnail plugin"

# ----------------------------------------------------------
# COMPUTE recipes
# ----------------------------------------------------------

/usr/bin/nvidia-smi:
	ubuntu-drivers install

$(CUDA_KEYRING_DEB): | $(DOWNLOADS_DIR)
	curl -fsSL $(CUDA_REPO)/cuda-keyring_1.1-1_all.deb -o $@

$(CUDA_LIST): $(CUDA_KEYRING_DEB)
	@test $(CURRENT_UID) -eq 0 || { echo ">>> CUDA repo setup requires root. Run: sudo make"; exit 1; }
	$(APT) install -y $<

$(NVCC): | $(CUDA_LIST)
	@test $(CURRENT_UID) -eq 0 || { echo ">>> CUDA install requires root. Run: sudo make"; exit 1; }
	$(APT) update
	$(APT) install -y $(CUDA_PKG)

/usr/local/cuda:
	@test $(CURRENT_UID) -eq 0 || { echo ">>> CUDA symlink requires root. Run: sudo make"; exit 1; }
	ln -sfn $$(ls -d /usr/local/cuda-* 2>/dev/null | sort -V | tail -1) $@


$(WHISPER_TARGET): | $(WHISPER_VENV)
	$(WHISPER_PIP) faster-whisper openai-whisper
	@echo ">>> faster-whisper + openai-whisper installed"

$(UV):
	curl -LsSf https://astral.sh/uv/install.sh | UV_INSTALL_DIR=$(dir $(UV)) sh
	@echo ">>> uv installed to $(UV)"

$(WHISPER_VENV): $(UV)
	$(UV) venv $(WHISPER_VENV) --python 3.12
	@echo ">>> whisper venv at $(WHISPER_VENV)"

# ----------------------------------------------------------
# User setup (make, no sudo)
# ----------------------------------------------------------

.PHONY: user

DIGIKAM_VERSION := 9.0.0
DIGIKAM_URL     := https://download.kde.org/stable/digikam/$(DIGIKAM_VERSION)/digiKam-$(DIGIKAM_VERSION)-Qt6-x86-64.appimage
APPS_URLS = $(DIGIKAM_URL)
APPS_DIR  = $(USER_HOME)/.local/share/AppImages
APPS      = $(foreach u,$(APPS_URLS),$(APPS_DIR)/$(notdir $(u)))
ICONS_DIR := $(USER_HOME)/.local/share/icons
DESK_DIR  := $(USER_HOME)/.local/share/applications

CLAUDE_BIN := $(USER_HOME)/.local/bin/claude
SSH_KEY    := $(USER_HOME)/.ssh/id_ed25519

DOLPHIN_PREVIEW_OK     := $(shell grep -c '^Show Preview=true' $(USER_HOME)/.config/kdeglobals 2>/dev/null)
DOLPHIN_PREVIEW_TARGET := $(and $(filter 0,$(DOLPHIN_PREVIEW_OK)),.sentinel/dolphin-show-preview)
KBUILDSYCOCA           := /usr/bin/kbuildsycoca6

user: $(APPS) $(CLAUDE_BIN) $(USER_HOME)/.ssh/authorized_keys $(DOLPHIN_PREVIEW_TARGET) make-completion $(ST_WANTS)
	$(KBUILDSYCOCA)

$(USER_HOME)/.ssh/authorized_keys: $(SSH_KEY)
	cat $(SSH_KEY).pub >> $@
	chmod 600 $@
	@echo ">>> SSH key authorized for localhost"

$(SSH_KEY):
	ssh-keygen -t ed25519 -f $@ -N ""
	@echo ">>> SSH key generated: $@"

.sentinel/dolphin-show-preview: | .sentinel
	kwriteconfig5 --file kdeglobals --group "KFileDialog Settings" --key "Show Preview" true
	touch $@
	@echo ">>> Dolphin show preview enabled"

$(APPS_DIR)/%: | $(APPS_DIR)
	curl -fL --retry 5 --retry-delay 3 --progress-bar -A "Mozilla/5.0" $(filter %/$*,$(APPS_URLS)) -o $@
	chmod +x $@
	@APPIMAGE=$@; STEM=$$(basename $$APPIMAGE); SCRATCH=$$(mktemp -d); \
	$$APPIMAGE --appimage-extract '*.desktop' --appimage-extract 'usr/share/icons/*/*/apps/*.png' 2>/dev/null; \
	DESK=$$(ls squashfs-root/*.desktop 2>/dev/null | head -1); \
	ICON=$$(find squashfs-root/usr/share/icons -name '*.png' 2>/dev/null | head -1); \
	if [ -n "$$DESK" ]; then \
		mkdir -p $(DESK_DIR) $(ICONS_DIR); \
		sed "s|Exec=AppRun|Exec=$$APPIMAGE|" "$$DESK" > $(DESK_DIR)/$$(basename $$DESK); \
		[ -n "$$ICON" ] && cp "$$ICON" $(ICONS_DIR)/; \
		echo ">>> Integrated $$STEM"; \
	fi; \
	rm -rf squashfs-root

$(APPS_DIR):
	mkdir -p $@

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

.PHONY: clear-thumbs
clear-thumbs:
	rm -rf $(USER_HOME)/.cache/thumbnails/fail/
	@echo ">>> Thumbnail fail cache cleared — reopen Dolphin to regenerate"

# ----------------------------------------------------------
# Merge incoming trees
# ----------------------------------------------------------

.PHONY: merge
INCOMING ?= /mnt/backup/incoming
MERGED   ?= /mnt/backup/merged
merge:
	@mkdir -p $(MERGED)
	@find $(INCOMING) -mindepth 3 -maxdepth 3 -type f 2>/dev/null | \
	while read f; do \
		rel=$${f#$(INCOMING)/}; \
		dev=$${rel%%/*}; \
		rest=$${rel#*/}; \
		folder=$${rest%%/*}; \
		file=$${rest#*/}; \
		mkdir -p "$(MERGED)/$$folder"; \
		ln -sf "$$f" "$(MERGED)/$$folder/$${dev}_$$file"; \
	done
	@echo ">>> Merge complete"

# ----------------------------------------------------------
# Network
# ----------------------------------------------------------

BMC_MAC := 9c:6b:00:47:28:34

.PHONY: check-ssh
check-ssh:
	@echo "=== sshd service ==="
	@systemctl is-active ssh sshd 2>/dev/null || echo "neither ssh nor sshd active"
	@echo "=== listening on :22 ==="
	@ss -tlnp | grep :22 || echo "nothing listening on :22"
	@echo "=== ufw status ==="
	@ufw status 2>/dev/null || echo "ufw not installed"
	@echo "=== openssh-server installed? ==="
	@dpkg -l openssh-server 2>/dev/null | tail -1
	@echo "=== auth methods ==="
	@grep -E 'PasswordAuthentication|PubkeyAuthentication|PermitRootLogin|AuthenticationMethods' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null | grep -v '^#'

.PHONY: find-bmc
find-bmc:
	@sudo nmap -sn $(shell ip route | awk '/proto kernel/{print $$1}' | head -1) 2>/dev/null | grep -B1 -i '$(BMC_MAC)' || echo "BMC not found — try: sudo arp-scan --localnet | grep $(BMC_MAC)"

.PHONY: check-gpus
check-gpus:
	@echo "=== NVIDIA devices ==="
	@ssh crucible lspci -d 10de: || true
	@echo ""
	@echo "=== PCIe link errors (dmesg) ==="
	@ssh crucible sudo dmesg | grep -iE 'pcie|aer|link|nvidia|nvrm' | tail -30

.PHONY: test-pex
test-pex:
	@echo "=== PCIe tree ==="
	@ssh crucible lspci -t
	@echo ""
	@echo "=== PEX88048 bridges (PLX 10b5:8748) ==="
	@ssh crucible lspci -d 10b5: -v
	@echo ""
	@echo "=== All bridges ==="
	@ssh crucible lspci | grep -i bridge

# ----------------------------------------------------------
# SN8100
# ----------------------------------------------------------

.PHONY: detect-sn8100
detect-sn8100:
	@echo 1 > /sys/bus/pci/rescan
	@sleep 1
	@lsblk -d -o NAME,SIZE,MODEL | grep -E 'nvme|SN8100' || true

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

define BACKUP_AUTOMOUNT_UNIT
[Unit]
Description=Automount NVMe backup drive (SN8100)

[Automount]
Where=/mnt/backup
TimeoutIdleSec=0

[Install]
WantedBy=multi-user.target
endef

STORAGE := \
  /etc/systemd/system/mnt-backup.mount \
  /etc/systemd/system/mnt-backup.automount \
  /etc/systemd/system/multi-user.target.wants/mnt-backup.automount

.PHONY: storage backup-mount
storage backup-mount: $(STORAGE)

/etc/systemd/system/mnt-backup.mount:
	sed -i '\|/mnt/backup|d' /etc/fstab 2>/dev/null || true
	$(file >$@,$(BACKUP_MOUNT_UNIT))
	systemctl daemon-reload

/etc/systemd/system/mnt-backup.automount: /etc/systemd/system/mnt-backup.mount
	$(file >$@,$(BACKUP_AUTOMOUNT_UNIT))

/etc/systemd/system/multi-user.target.wants/mnt-backup.automount: /etc/systemd/system/mnt-backup.automount
	systemctl enable --now mnt-backup.automount
	systemctl start mnt-backup.mount
	chmod 1777 /mnt/backup
	@echo ">>> SN8100 automount enabled at /mnt/backup"

.PHONY: eject
eject:
	@[ -n "$(SN8100_DEV)" ] || { echo "SN8100 not found"; exit 1; }
	echo 1 > /sys/block/$(SN8100_DEV)/device/remove
	@echo ">>> Ejected $(SN8100_DEV)"


# ----------------------------------------------------------
# Deploy / clean
# ----------------------------------------------------------

.PHONY: deploy
deploy:
	@ssh crucible.local mkdir -p ~/Code/hardware
	@rsync -av Makefile crucible.local:~/Code/hardware/
	@ssh -tt crucible.local 'cd ~/Code/hardware && exec $$SHELL'


.PHONY: audit-services
audit-services:
	@systemctl list-units --type=service --state=running --no-pager | grep -vE 'dbus|getty|systemd|udev|network|bluetooth|audio|cups|avahi|ssh|cron|gdm|display|polkit|rtkit|login|accounts|power|udisk|mount|fstrim|kernel|irq|cpu|nvidia|snapd'

## Wipe CUDA repo setup — forces keyring re-download and toolkit reinstall on next run
.PHONY: clean-cuda
clean-cuda:
	rm -f $(CUDA_KEYRING_DEB) /etc/apt/sources.list.d/cuda-ubuntu*-x86_64.list

.PHONY: clean-debloat
clean-debloat:
	rm -f /etc/apt/preferences.d/no-snapd
	rm -f /etc/systemd/system/packagekit.service

.PHONY: clean
clean: clean-cuda clean-debloat
	rm -f /usr/share/applications/google-chrome.desktop /usr/share/applications/code.desktop
