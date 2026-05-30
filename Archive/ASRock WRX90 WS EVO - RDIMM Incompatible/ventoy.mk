# Ventoy bootable USB setup
#
# Bootstrap (once per machine):
#   sudo make deps                 # install required system packages
#
# Workflow (run all three in order):
#   make && sudo make && make
#     make         # 1. fetch Ventoy tarball
#     sudo make    # 2. flash Ventoy bootloader + reformat as ext4 (needs root)
#     make         # 3. download ISOs + load them + persistence onto flashed USB
#
# Other targets:
#   make test                      # boot USB in QEMU VM (verify without reboot)
#   make clean                     # remove Ventoy archive + extracted dir
#   sudo make wipe                 # zap partition table + filesystem signatures
#
# WiFi credentials are auto-detected from the currently-connected network via
# `nmcli device wifi show-password`. Override on command line if needed:
#   make WIFI_SSID=HomeNet WIFI_KEY='s3cret!'
# https://cdimage.ubuntu.com/kubuntu/releases/25.10/release/kubuntu-25.10-desktop-amd64.iso
# http://cdimage.ubuntu.com/kubuntu/releases/26.04/beta/kubuntu-26.04-beta-desktop-amd64.iso

define URLS
https://download.manjaro.org/kde/26.0.4/manjaro-kde-26.0.4-260327-linux618.iso
https://mirror.cachyos.org/ISO/desktop/260308/cachyos-desktop-linux-260308.iso
endef

ifeq ($(strip $(DEV)),)
DEV := $(shell lsblk -dno NAME,TRAN | awk '$$2=="usb" {print "/dev/"$$1; exit}')
endif

DOWNLOADS_DIR := $(REAL_HOME)/Downloads

.PHONY: ventoy-default
ifeq ($(shell lsblk -no LABEL $(DEV)1 2>/dev/null),Ventoy)
$(shell findmnt $(DEV)1 >/dev/null 2>&1 || udisksctl mount -b $(DEV)1 >/dev/null 2>&1)
ventoy-default: local-setup $(FFS_CONFIG) load
else
ventoy-default: local-setup $(FFS_CONFIG) fetch
endif

.PHONY: fetch
VENTOY_VERSION   := 1.1.11
VENTOY_DIR       := ventoy-$(VENTOY_VERSION)
fetch: $(VENTOY_DIR)/Ventoy2Disk.sh
	@echo ">>> Fetched. Now run: sudo make    (to flash Ventoy)"

VENTOY_TARBALL   := ventoy-$(VENTOY_VERSION)-linux.tar.gz
$(VENTOY_DIR)/Ventoy2Disk.sh: $(DOWNLOADS_DIR)/$(VENTOY_TARBALL)
	@tar -xzf $<
	@touch $@

VENTOY_URL       := https://github.com/ventoy/Ventoy/releases/download/v$(VENTOY_VERSION)/$(VENTOY_TARBALL)
$(DOWNLOADS_DIR)/$(VENTOY_TARBALL): | $(DOWNLOADS_DIR)
	@echo ">>> Downloading $(VENTOY_TARBALL)..."
	@curl -#L -o $@ $(VENTOY_URL)

.PHONY: flash
FLASH_FLAG := $(if $(filter Ventoy,$(shell lsblk -no LABEL $(DEV)1 2>/dev/null)),-u,-i)
flash: $(VENTOY_DIR)/Ventoy2Disk.sh
	@[ -n "$(DEV)" ] || { echo "ERROR: No USB device detected. Plug in the USB and retry."; exit 1; }
	@cd $(<D) && ./$(<F) $(FLASH_FLAG) $(DEV)
	@if [ "$(FLASH_FLAG)" = "-i" ]; then \
		echo ">>> Reformatting $(DEV)1 as ext4 (journal + checksums)..."; \
		mkfs.ext4 -L Ventoy -m 0 -O metadata_csum -q $(DEV)1; \
		mount $(DEV)1 /mnt; \
		chown $${SUDO_USER:-$$USER}:$${SUDO_USER:-$$USER} /mnt; \
		umount /mnt; \
	fi
	@echo ">>> Flashed. Now run: make    (to load ISOs)"

.PHONY: load
MOUNT := $(shell findmnt -no TARGET $(DEV)1)
ISO_URL      := $(shell jq -n '[$$ARGS.positional[] | {key: split("/")[-1], value: .}] | from_entries' --args $(strip $(URLS)))
MOUNTED_ISOS := $(shell echo '$(ISO_URL)' | jq -r --arg m '$(MOUNT)' 'keys[] | "\($$m)/\(.)"')
DAT_FILES    := $(shell echo '$(ISO_URL)' | jq -r --arg m '$(MOUNT)' 'keys[] | "\($$m)/persistence/\(.).dat"')
WIFI_ARCHIVE := $(MOUNT)/injection/wifi-seed.tar.xz
define VENTOY_JSON
{
  "persistence": $(shell echo '$(ISO_URL)' | jq '[keys[] | { "image": ("/" + .), "backend": ("/persistence/" + . + ".dat") }]'),
  "injection": $(shell echo '$(ISO_URL)' | jq '[keys[] | { "image": ("/" + .), "archive": "/injection/wifi-seed.tar.xz" }]')
}
endef
load: $(MOUNTED_ISOS) $(DAT_FILES) $(WIFI_ARCHIVE) | $(MOUNT) $(MOUNT)/ventoy
	@[ -n "$(DEV)" ] || { echo "ERROR: No USB device detected. Plug in the USB and retry."; exit 1; }
	@echo ">>> Loading $(words $(MOUNTED_ISOS)) ISOs + persistence files ($(PERSISTENCE_SIZE_MB)MB each) + WiFi profile to $(DEV)..."
	$(file >$(MOUNT)/ventoy/ventoy.json,$(VENTOY_JSON))
	@echo ">>> Wrote $(MOUNT)/ventoy/ventoy.json"
	@echo ">>> Flushing writes to $(DEV)..."
	@sync
	@echo ">>> Unmounting $(DEV)1..."
	@udisksctl unmount -b $(DEV)1 2>/dev/null || echo "    (already unmounted)"
	@echo ">>> Powering off $(DEV)..."
	@udisksctl power-off -b $(DEV) 2>/dev/null || echo "    (power-off unsupported — safe to remove manually)"
	@echo ">>> Done. USB ready to remove."

$(MOUNT)/%: $(DOWNLOADS_DIR)/%
	@echo ">>> Copying $* to USB..."
	@rsync -h --progress $^ $(@D)

PERSISTENCE_SIZE_MB := 4096
$(MOUNT)/persistence/%.dat: | $(MOUNT)/persistence
	@echo ">>> Creating $(PERSISTENCE_SIZE_MB)MB persistence file for $*..."
	@dd if=/dev/zero of=$@ bs=1M count=$(PERSISTENCE_SIZE_MB) status=progress
	@mkfs.ext4 -F -L persistence -q $@

$(MOUNT)/persistence:
	@mkdir -p $@

.PRECIOUS: $(DOWNLOADS_DIR)/%
$(DOWNLOADS_DIR)/%: | $(DOWNLOADS_DIR)
	@echo ">>> Downloading $*..."
	@curl -#L -o $@ $$(echo '$(ISO_URL)' | jq -r --arg k '$(notdir $@)' '.[$$k]')

$(DOWNLOADS_DIR):
	@mkdir -p $@

# WiFi injection — SSID/key auto-detected from the currently-connected network via
# nmcli. The keyfile is scaffolded into .data/ then packed into $(WIFI_ARCHIVE).
# NetworkManager on the live system picks it up at boot, auto-connecting to the same
# network the build host is on. Override credentials with: make WIFI_SSID=... WIFI_KEY=...
DATA_DIR     := .data
WIFI_ID      := MyWiFi
WIFI_SSID    := $(shell nmcli device wifi show-password 2>/dev/null | sed -n 's/^SSID: //p')
WIFI_KEY     := $(shell nmcli device wifi show-password 2>/dev/null | sed -n 's/^Password: //p')
WIFI_PROFILE := $(DATA_DIR)/etc/NetworkManager/system-connections/$(WIFI_ID).nmconnection
$(WIFI_ARCHIVE): $(WIFI_PROFILE) | $(MOUNT)/injection
	@echo ">>> Packing $(DATA_DIR)/ → $@"
	@tar -cJf $@ -C $(DATA_DIR) .

$(MOUNT)/injection $(MOUNT)/ventoy:
	@mkdir -p $@

define WIFI_CONNECTION
[connection]
id=$(WIFI_ID)
type=wifi

[wifi]
mode=infrastructure
ssid=$(WIFI_SSID)

[wifi-security]
key-mgmt=wpa-psk
psk=$(WIFI_KEY)

[ipv4]
method=auto

[ipv6]
method=auto
endef

$(WIFI_PROFILE): | $(DATA_DIR)/etc/NetworkManager/system-connections
	$(file >$@,$(WIFI_CONNECTION))
	@chmod 600 $@

$(DATA_DIR)/etc/NetworkManager/system-connections:
	@mkdir -p $@

BASHRC          := $(HOME)/.bashrc
MAKE_COMPLETION := /usr/share/bash-completion/completions/make

.PHONY: local-setup
local-setup: $(MAKE_COMPLETION)
	@grep -q 'bash-completion/completions/make' $(BASHRC) || \
		echo 'source $(MAKE_COMPLETION)' >> $(BASHRC)
	@echo ">>> Make autocomplete enabled. Run: source $(BASHRC)"


.PHONY: deps
deps:
ifeq ($(shell which pacman 2>/dev/null),)
	apt install -y curl rsync tar exfatprogs e2fsprogs gdisk udisks2 qemu-system-x86 ovmf jq
else
	pacman -S --needed --noconfirm curl rsync tar e2fsprogs gptfdisk udisks2 jq qemu-desktop edk2-ovmf
endif

.PHONY: test
test:
	@[ -n "$(DEV)" ] || { echo "ERROR: No USB device detected. Plug in the USB and retry."; exit 1; }
	@udisksctl unmount -b $(DEV)1 2>/dev/null || true
	sudo qemu-system-x86_64 -enable-kvm -m 4G -bios /usr/share/ovmf/OVMF.fd -drive file=$(DEV),format=raw

.PHONY: clean
clean:
	@rm -rf $(VENTOY_DIR) $(DOWNLOADS_DIR)/$(VENTOY_TARBALL) $(DATA_DIR)

.PHONY: wipe
wipe:
	@[ "$$(id -u)" = "0" ] || { echo "ERROR: wipe requires root. Run: sudo make wipe"; exit 1; }
	@[ -n "$(DEV)" ] || { echo "ERROR: No USB device detected. Plug in the USB and retry."; exit 1; }
	@echo ">>> Unmounting any mounted partitions on $(DEV)..."
	@umount $(DEV)?* 2>/dev/null || true
	@echo ">>> Wiping $(DEV)..."
	wipefs -a $(DEV)
	sgdisk --zap-all $(DEV)
	partprobe $(DEV)
	@echo ">>> $(DEV) wiped clean."
