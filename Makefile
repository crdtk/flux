# ==========================================================
# Ubuntu Setup
# ==========================================================

MAKEFLAGS += --no-builtin-rules
.SUFFIXES:

.PHONY: all
ROOT_TARGET := $(if $(wildcard /usr/bin/apt-file),level-1,level-0)
all: $(if $(filter 0,$(shell id -u)),$(ROOT_TARGET),setup)

# ----------------------------------------------------------
# Package install (sudo make)
# ----------------------------------------------------------

APT := apt-get -o DPkg::Lock::Timeout=-1

.PHONY: level-0 ## Foundational packages required for the rest of the packages install
level-0:
	systemctl disable --now pop-shop backuppc urbackup-client urbackupclientbackend apache2 postfix xrdp xrdp-sesman x2goserver rpcbind touchegg webmin ollama nmbd smbd samba pop-upgrade thermald 2>/dev/null || true
	apt purge -y pop-shop backuppc urbackup-client apache2 postfix xrdp x2goserver rpcbind touchegg webmin samba nmbd smbd pop-upgrade thermald cockpit-packagekit 2>/dev/null || true
	snap remove --purge ollama 2>/dev/null || true
	rm -f /usr/local/bin/ollama /etc/systemd/system/ollama.service
	systemctl daemon-reload
	systemctl stop packagekit 2>/dev/null || true
	systemctl mask packagekit
	mkdir -p /etc/PackageKit
	dpkg-divert --divert /etc/PackageKit/20packagekit.distrib --rename /etc/apt/apt.conf.d/20packagekit
	echo "deb http://archive.ubuntu.com/ubuntu jammy-backports main universe" > /etc/apt/sources.list.d/jammy-backports.list
	$(APT) update
	$(APT) install -y apt-file git syncthing avahi-daemon arp-scan nmap nodejs npm mc libheif1 libheif-examples gwenview appmenu-gtk3-module appmenu-registrar ddclient cockpit/jammy-backports cockpit-files/jammy-backports
	apt-file update
	@echo ">>> Bootstrap done. Run: sudo make"


.PHONY: level-1 ## Installs INSTALL targets not yet present on this machine

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
  /etc/systemd/system/suspend.target \
  /etc/modprobe.d/blacklist-nouveau.conf \
  /etc/modprobe.d/nvidia-power.conf \
  /etc/systemd/system/openipmi.service \
  .sentinel/pam-sss-fixed \
  .sentinel/grub-timeout-set \
  .sentinel/initramfs-updated

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
  /usr/share/cockpit/files \
  /etc/ssh/sshd_config.d/lan-password.conf \
  $(PRINTER_PPD) \
  .sentinel/syncthing-gui-remote

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
CUDA_PKG              := $(if $(shell [ -n "$(SYS_SM)" ] && [ "$(SYS_SM)" -lt 75 ] && echo 1),cuda-toolkit-12-6,cuda-toolkit)
CUDA_VER              := $(shell echo $(CUDA_PKG) | grep -oE '[0-9]+-[0-9]+$$' | tr '-' '.')
NVCC                  := $(if $(CUDA_VER),/usr/local/cuda-$(CUDA_VER)/bin/nvcc,/usr/local/cuda/bin/nvcc)
CUDA_LIST             := /etc/apt/sources.list.d/cuda-ubuntu$(UBUNTU_VER)-x86_64.list
CUDA_SYMLINK_SENTINEL := $(if $(CUDA_VER),/usr/local/cuda,)
CUDA_REPO              = https://developer.download.nvidia.com/compute/cuda/repos/ubuntu$(UBUNTU_VER)/x86_64
CUDA_KEYRING_DEB      := $(DOWNLOADS_DIR)/cuda-keyring_1.1-1_all.deb
CUDA_MATH_H           := /usr/local/cuda/targets/x86_64-linux/include/crt/math_functions.h
CUDA_MATH_HPP         := /usr/local/cuda/targets/x86_64-linux/include/crt/math_functions.hpp
CURRENT_UID           := $(shell id -u)
UV                    := $(USER_HOME)/.local/bin/uv
WHISPER_VENV          := $(USER_HOME)/.local/share/whisper-venv
WHISPER_PIP            = VIRTUAL_ENV=$(WHISPER_VENV) $(UV) pip install
WHISPER_TARGET        := $(USER_HOME)/.local/share/whisper-venv/lib/python3.12/site-packages/faster_whisper

COMPUTE := \
  /usr/bin/nvidia-smi \
  $(CUDA_LIST) \
  $(NVCC) \
  $(CUDA_SYMLINK_SENTINEL) \
  /usr/bin/cmake \
  /usr/bin/g++-14 \
  .sentinel/cuda-rsqrt-patched \
  $(WHISPER_TARGET)

# ----------------------------------------------------------

INSTALL := $(HARDENING) $(MANAGEMENT) $(PKG_APPS) $(COMPUTE)
PENDING := $(filter-out $(wildcard $(INSTALL)),$(INSTALL))

level-1: $(PENDING)
	$(APT) autoremove

# ----------------------------------------------------------
# Infrastructure — pattern rules, downloads, sentinels
# ----------------------------------------------------------

## Resolve packages by Custom Repository URL
/usr/bin/%: /etc/apt/sources.list.d/%.list
	$(APT) update
	$(APT) install -y $*

## Resolve packages using apt-file global search
/usr/bin/%:
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

.sentinel/initramfs-updated: /etc/modprobe.d/blacklist-nouveau.conf /etc/modprobe.d/nvidia-power.conf | .sentinel
	update-initramfs -u
	touch $@
	@echo ">>> initramfs updated"

# ----------------------------------------------------------
# MANAGEMENT recipes
# ----------------------------------------------------------

/etc/ddclient.conf: $(PROJECTS)/secrets/ddclient.conf /usr/bin/ddclient
	ln -sf $< $@
	systemctl enable --now ddclient
	@echo ">>> ddclient configured and enabled"

$(PROJECTS)/secrets/ddclient.conf: | $(PROJECTS)
	cd $(PROJECTS) && git clone https://github.com/crdtk/secrets

$(PROJECTS):
	mkdir -p $@

/etc/systemd/system/sockets.target.wants/cockpit.socket: /usr/bin/cockpit
	systemctl enable --now cockpit.socket
	@echo ">>> Cockpit: https://$(MACHINE_IP):9090"

# cockpit-files requires cockpit >= 318; jammy ships 264 — upgrade via backports
/usr/share/cockpit/files: /etc/apt/sources.list.d/jammy-backports.list
	$(APT) install -y -t jammy-backports cockpit cockpit-files

/etc/apt/sources.list.d/jammy-backports.list:
	echo "deb http://archive.ubuntu.com/ubuntu jammy-backports main universe" > $@
	$(APT) update

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

# kimg_heif.so requires KFrameworks >= 5.100 — not in jammy; needs Kubuntu Backports PPA
/etc/apt/sources.list.d/kubuntu-ppa-ubuntu-backports-jammy.list:
	add-apt-repository -y ppa:kubuntu-ppa/backports
	$(APT) update

$(KIMG_HEIF_SO): /etc/apt/sources.list.d/kubuntu-ppa-ubuntu-backports-jammy.list
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
	ln -sfn /usr/local/cuda-$(CUDA_VER) $@

define CUDA_HPP_PATCH_PY
import sys
path = sys.argv[1]
targets = [
    '__MATH_FUNCTIONS_DECL__ float rsqrt(const float a)',
    '__func__(double rsqrt(const double a))',
    '__func__(float rsqrtf(const float a))',
]
with open(path) as f:
    lines = f.readlines()
for i, line in enumerate(lines):
    if line.rstrip('\n') in targets:
        lines[i] = line.rstrip('\n') + ' noexcept\n'
with open(path, 'w') as f:
    f.writelines(lines)
endef

# CUDA 13.1 rsqrt/rsqrtf host declarations lack noexcept, conflicting with glibc 2.41
.sentinel/cuda-rsqrt-patched: | .sentinel
	@test -f $(CUDA_MATH_H) || { echo ">>> CUDA not installed. Run: sudo make"; exit 1; }
	sed -i -E '/\brsqrtf?\b/{ /__device__/! { /noexcept/! s/\);$$/) noexcept;/ } }' $(CUDA_MATH_H)
	$(file >/tmp/cuda_hpp_patch.py,$(CUDA_HPP_PATCH_PY))
	python3 /tmp/cuda_hpp_patch.py $(CUDA_MATH_HPP)
	touch $@
	@echo ">>> CUDA math_functions patched for glibc 2.41"

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

.PHONY: setup

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
KBUILDSYCOCA           := $(or $(wildcard /usr/bin/kbuildsycoca6),$(wildcard /usr/bin/kbuildsycoca5))

setup: $(APPS) $(CLAUDE_BIN) $(USER_HOME)/.ssh/authorized_keys $(DOLPHIN_PREVIEW_TARGET) make-completion
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

.PHONY: backup-mount
backup-mount:
	sed -i '\|/mnt/backup|d' /etc/fstab 2>/dev/null || true
	$(file >/etc/systemd/system/mnt-backup.mount,$(BACKUP_MOUNT_UNIT))
	$(file >/etc/systemd/system/mnt-backup.automount,$(BACKUP_AUTOMOUNT_UNIT))
	systemctl daemon-reload
	systemctl enable --now mnt-backup.automount
	systemctl start mnt-backup.mount
	chmod 1777 /mnt/backup
	@echo ">>> SN8100 automount enabled at /mnt/backup"

.PHONY: eject
eject:
	@DEV=$$(lsblk -dno NAME,MODEL | awk '/SN8100/{print $$1; exit}'); \
	[ -n "$$DEV" ] || { echo "SN8100 not found"; exit 1; }; \
	echo 1 > /sys/block/$$DEV/device/remove; \
	echo ">>> Ejected $$DEV"

# ----------------------------------------------------------
# Inference — llama.cpp. make infer-server builds everything on first run.
# ----------------------------------------------------------

MODEL_DIR  ?= $(USER_HOME)/models
MODEL_FILE := Qwen3-Coder-30B-A3B-Instruct-480B-Distill-V2-Fp32.i1-Q4_K_M.gguf
MODEL_PATH := $(MODEL_DIR)/$(MODEL_FILE)
MODEL_META := $(MODEL_DIR)/.cache/huggingface/download/$(MODEL_FILE).metadata
.PRECIOUS: $(MODEL_PATH) $(MODEL_META)

SYS_THREADS   := $(shell nproc)
SYS_VRAM      := $(shell nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | awk '{sum+=$$1}END{print sum+0}')
SYS_MODEL_MIB := $(shell test -f $(MODEL_META) && du -m $(MODEL_PATH) | cut -f1 || echo 0)
SYS_AVAIL     := $(shell echo $$(( $(SYS_VRAM) > $(SYS_MODEL_MIB) ? $(SYS_VRAM) - $(SYS_MODEL_MIB) : 0 )))
SYS_CTX       := $(shell echo $$(( $(SYS_AVAIL) * 16 > 131072 ? 131072 : $(SYS_AVAIL) * 16 )))

N_GPU_LAYERS ?= 99
N_CPU_MOE    := $(if $(filter-out 0,$(SYS_AVAIL)),0,48)
THREADS      ?= $(SYS_THREADS)
CTX_SIZE     ?= $(or $(filter-out 0,$(SYS_CTX)),16384)
MOE_FLAG      = $(if $(filter-out 0,$(N_CPU_MOE)),--n-cpu-moe $(N_CPU_MOE),)
INFER_FLAGS   = -ngl $(N_GPU_LAYERS) $(MOE_FLAG) --no-mmap --mlock --cache-type-k q4_0 --cache-type-v q4_0 --ctx-size $(CTX_SIZE) --threads $(THREADS) --flash-attn on
LLAMA_BINS    = $(USER_HOME)/.local/bin
LLAMA_BIN     = $(LLAMA_BINS)/llama-bench

.PHONY: infer-server
infer-server: $(LLAMA_BIN) $(MODEL_META)
	@echo ">>> Serving on http://0.0.0.0:8080 — GPU_LAYERS=$(N_GPU_LAYERS) CTX=$(CTX_SIZE)"
	llama-server -m $(MODEL_PATH) $(INFER_FLAGS) --host 0.0.0.0 --port 8080

LLAMA_TAG      = b9222
LLAMA_SRC      = $(DOWNLOADS_DIR)/llama.cpp-$(LLAMA_TAG)
CUDA_ROOT     := $(patsubst %/bin/nvcc,%,$(NVCC))
# CUDA 13.x does not support GCC 15 (Ubuntu 26.04 default); use g++-14 as host compiler
CUDA_HOST_CC   := $(firstword $(wildcard /usr/bin/g++-14 /usr/bin/g++-13 /usr/bin/g++-12))
CUDA_HOST_FLAG  = $(if $(CUDA_HOST_CC),-DCMAKE_CUDA_HOST_COMPILER=$(CUDA_HOST_CC),)

$(LLAMA_BIN): $(LLAMA_SRC) /usr/bin/cmake /usr/bin/g++-14 .sentinel/cuda-rsqrt-patched | $(LLAMA_BINS)
	@test -x $(NVCC) || { echo ">>> CUDA not installed. Run: sudo make"; exit 1; }
	cmake -B $(LLAMA_SRC)/build -S $(LLAMA_SRC) \
		-DGGML_CUDA=ON \
		-DCMAKE_CUDA_COMPILER=$(NVCC) \
		-DCUDA_TOOLKIT_ROOT_DIR=$(CUDA_ROOT) \
		-DCUDAToolkit_ROOT=$(CUDA_ROOT) \
		-DCMAKE_EXE_LINKER_FLAGS="-L$(CUDA_ROOT)/lib64 -Wl,-rpath,$(CUDA_ROOT)/lib64" \
		-DCMAKE_CUDA_ARCHITECTURES=$(SYS_SM) \
		-DCMAKE_BUILD_TYPE=Release \
		-DBUILD_SHARED_LIBS=OFF \
		$(CUDA_HOST_FLAG)
	cmake --build $(LLAMA_SRC)/build -j$(SYS_THREADS)
	cp $(LLAMA_SRC)/build/bin/llama-bench $(LLAMA_SRC)/build/bin/llama-server $(LLAMA_SRC)/build/bin/llama-cli $(LLAMA_BINS)/
	@echo ">>> llama.cpp $(LLAMA_TAG) built with CUDA"

$(LLAMA_SRC): $(LLAMA_SRC).tar.gz
	tar -xzf $< -C $(DOWNLOADS_DIR)

$(LLAMA_SRC).tar.gz: | $(DOWNLOADS_DIR)
	curl -fsSL https://github.com/ggml-org/llama.cpp/archive/refs/tags/$(LLAMA_TAG).tar.gz -o $@

$(LLAMA_BINS):
	mkdir -p $@

MODEL_HF = mradermacher/Qwen3-Coder-30B-A3B-Instruct-480B-Distill-V2-Fp32-i1-GGUF
HF_CLI   = $(LLAMA_BINS)/hf

$(MODEL_META): | $(MODEL_DIR) $(HF_CLI)
	$(HF_CLI) download $(MODEL_HF) $(MODEL_FILE) --local-dir $(MODEL_DIR)
	@echo ">>> Model ready: $(MODEL_PATH)"

$(MODEL_DIR):
	mkdir -p $@

$(HF_CLI):
	pip install --user huggingface_hub
	@echo ">>> huggingface-cli installed"

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

## Wipe llama.cpp build — hardware is re-assessed at parse time on next run
.PHONY: clean-infer
clean-infer:
	rm -f $(LLAMA_BINS)/llama-bench $(LLAMA_BINS)/llama-server $(LLAMA_BINS)/llama-cli
	rm -rf $(LLAMA_SRC)
	rm -f .sentinel/cuda-rsqrt-patched 2>/dev/null || true

## Wipe CUDA repo setup — forces keyring re-download and toolkit reinstall on next run
.PHONY: clean-cuda
clean-cuda:
	rm -f $(CUDA_KEYRING_DEB) /etc/apt/sources.list.d/cuda-ubuntu*-x86_64.list

.PHONY: clean
clean: clean-infer clean-cuda clean-demo
	rm -f /usr/share/applications/google-chrome.desktop /usr/share/applications/code.desktop

# ----------------------------------------------------------
# TurboQuant Fit Demo — bench-bert  bench-tq  demo-fit
# Source: turboquant-demo/  (proper Python package, not generated)
# ----------------------------------------------------------

DEMO_DIR      := $(CURDIR)/turboquant-demo
DEMO_SENTINEL := $(DEMO_DIR)/.sentinel
$(shell mkdir -p $(DEMO_SENTINEL))
TURBO_DIR     ?=
VENV          := $(DEMO_DIR)/.venv
VENV_PY       := $(VENV)/bin/python3
VENV_PIP       = VIRTUAL_ENV=$(VENV) $(UV) pip install

DEMO_MODEL_HF  ?= casperhansen/deepseek-r1-distill-qwen-7b-awq
DEMO_MODEL_DIR := $(MODEL_DIR)/$(notdir $(DEMO_MODEL_HF))

# Locust defaults — override on the command line, e.g. LOCUST_USERS=8 make bench-locust
LOCUST_USERS   ?= 4
LOCUST_RATE    ?= 1
LOCUST_TIME    ?= 60s
LOCUST_CSV     ?= $(DEMO_DIR)/locust_results

.PHONY: bench-bert bench-tq bench-pipeline bench-spark demo-servers demo-fit demo-model bench-locust locust-ui clean-demo

# ---- Stage 1: uv ----
$(DEMO_SENTINEL)/uv-installed:
	curl -LsSf https://astral.sh/uv/install.sh | sh
	touch $@
	@echo ">>> uv ready at $(UV)"

# ---- Stage 2: venv (Python 3.12 — llvmlite 0.44 doesn't support 3.14) ----
$(DEMO_SENTINEL)/demo-venv: $(DEMO_SENTINEL)/uv-installed
	$(UV) venv $(VENV) --python 3.12
	touch $@
	@echo ">>> venv at $(VENV) (python 3.12)"

# ---- Stage 3: Python deps + install package in editable mode ----
$(DEMO_SENTINEL)/demo-deps: $(DEMO_SENTINEL)/demo-venv
	$(VENV_PIP) \
	    "vllm==0.18.0" \
	    transformers \
	    accelerate \
	    streamlit \
	    pynvml \
	    "huggingface_hub[cli]" \
	    openai \
	    triton \
	    locust \
	    pyspark
	$(VENV_PIP) -e "$(DEMO_DIR)"
	@[ -n "$(TURBO_DIR)" ] && $(VENV_PIP) -e "$(TURBO_DIR)" || true
	touch $@
	@echo ">>> demo deps installed (vllm==0.18.0)"

# ---- Stage 4: model download ----
# Model is public — no HF login needed.
demo-model: $(DEMO_SENTINEL)/demo-deps | $(MODEL_DIR)
	$(VENV_PY) -c "from huggingface_hub import snapshot_download; \
snapshot_download('$(DEMO_MODEL_HF)', local_dir='$(DEMO_MODEL_DIR)')"
	@echo ">>> model ready: $(DEMO_MODEL_DIR)"

# ---- Phony targets ----

bench-bert: $(DEMO_SENTINEL)/demo-deps
	cd $(DEMO_DIR) && $(VENV_PY) -m turboquant_demo.bert

bench-tq: $(DEMO_SENTINEL)/demo-deps
	@curl -sf http://localhost:8000/health >/dev/null 2>&1 || \
	    { echo ">>> TQ server not running — run: make demo-servers"; exit 1; }
	@curl -sf http://localhost:8001/health >/dev/null 2>&1 || \
	    { echo ">>> Baseline server not running — run: make demo-servers"; exit 1; }
	cd $(DEMO_DIR) && $(VENV_PY) -m turboquant_demo.sweep
	@echo ">>> results: $(DEMO_DIR)/bench_results.json"

bench-spark: $(DEMO_SENTINEL)/demo-deps
	cd $(DEMO_DIR) && $(VENV_PY) -m turboquant_demo.pipeline \
	    --generate \
	    --input  data/returns.parquet \
	    --output data/profiles.parquet
	@echo ">>> profiles: $(DEMO_DIR)/data/profiles.parquet"

bench-pipeline: $(DEMO_SENTINEL)/demo-deps
	@curl -sf http://localhost:8000/health >/dev/null 2>&1 || \
	    { echo ">>> TQ server not running — run: make demo-servers"; exit 1; }
	cd $(DEMO_DIR) && $(VENV_PY) -m turboquant_demo.latency

demo-servers: $(DEMO_SENTINEL)/demo-deps
	@echo ">>> Splitting A4000 16GB: 0.42 each, eager mode (baseline :8001, TQ :8000)"
	$(DEMO_DIR)/scripts/start_servers.sh "$(DEMO_MODEL_DIR)"

demo-fit: $(DEMO_SENTINEL)/demo-deps
	cd $(DEMO_DIR) && $(VENV)/bin/streamlit run turboquant_demo/app.py \
	    --browser.gatherUsageStats false \
	    --server.headless true

bench-locust: $(DEMO_SENTINEL)/demo-deps
	@curl -sf http://localhost:8000/health >/dev/null 2>&1 || \
	    { echo ">>> TQ server not running — run: make demo-servers"; exit 1; }
	@curl -sf http://localhost:8001/health >/dev/null 2>&1 || \
	    { echo ">>> Baseline server not running — run: make demo-servers"; exit 1; }
	cd $(DEMO_DIR) && $(VENV)/bin/locust \
	    -f turboquant_demo/locustfile.py \
	    --headless \
	    -u $(LOCUST_USERS) -r $(LOCUST_RATE) -t $(LOCUST_TIME) \
	    --csv $(LOCUST_CSV) \
	    --host http://localhost:8000
	@echo ">>> results: $(LOCUST_CSV)_stats.csv"

locust-ui: $(DEMO_SENTINEL)/demo-deps
	@curl -sf http://localhost:8000/health >/dev/null 2>&1 || \
	    { echo ">>> TQ server not running — run: make demo-servers"; exit 1; }
	@echo ">>> Locust UI at http://localhost:8089"
	cd $(DEMO_DIR) && $(VENV)/bin/locust \
	    -f turboquant_demo/locustfile.py \
	    --host http://localhost:8000

clean-demo:
	-kill $$(cat /tmp/vllm-base.pid 2>/dev/null) 2>/dev/null; rm -f /tmp/vllm-base.pid
	-kill $$(cat /tmp/vllm-tq.pid  2>/dev/null) 2>/dev/null; rm -f /tmp/vllm-tq.pid
	rm -rf $(DEMO_DIR)/.venv $(DEMO_DIR)/.sentinel
	@echo ">>> demo venv cleaned (source preserved in turboquant-demo/)"

# ---- end of demo section — Python source lives in turboquant-demo/ ----
