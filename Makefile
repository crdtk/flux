# ==========================================================
# Ubuntu Setup
# ==========================================================

MAKEFLAGS += --no-builtin-rules
.SUFFIXES:

.PHONY: all
ROOT_TARGET  := $(if $(wildcard /usr/bin/apt-file),level-1,level-0)
all: $(if $(filter 0,$(shell id -u)),$(ROOT_TARGET),setup)

.PHONY: level-0 ## Foundational packages required for the rest of the packages install
level-0:
	systemctl stop packagekit 2>/dev/null || true
	systemctl mask packagekit
	mkdir -p /etc/PackageKit
	dpkg-divert --divert /etc/PackageKit/20packagekit.distrib --rename /etc/apt/apt.conf.d/20packagekit
	apt install -y apt-file git syncthing cockpit avahi-daemon
	apt-file update
	@echo ">>> Bootstrap done. Run: sudo make"

# ----------------------------------------------------------
# Package install (sudo make)
# ----------------------------------------------------------

.PHONY: level-1 ## Installs INSTALL targets not yet present on this machine

USER_HOME     := $(shell getent passwd $${SUDO_USER:-$$(whoami)} | cut -d: -f6)
DOWNLOADS_DIR := $(USER_HOME)/Downloads
DEB_URLS  := https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
DEBS      := $(foreach u,$(DEB_URLS),$(DOWNLOADS_DIR)/$(notdir $(u)))

UBUNTU_VER    := $(shell lsb_release -rs 2>/dev/null | tr -d '.')
SYS_SM        := $(shell nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 | tr -d '.')
CUDA_PKG      := $(if $(shell [ -n "$(SYS_SM)" ] && [ "$(SYS_SM)" -lt 75 ] && echo 1),cuda-toolkit-12-6,cuda-toolkit)
CUDA_VER      := $(shell echo $(CUDA_PKG) | grep -oE '[0-9]+-[0-9]+$$' | tr '-' '.')
NVCC          := $(if $(CUDA_VER),/usr/local/cuda-$(CUDA_VER)/bin/nvcc,/usr/local/cuda/bin/nvcc)
CUDA_REPO      = https://developer.download.nvidia.com/compute/cuda/repos/ubuntu$(UBUNTU_VER)/x86_64
CUDA_LIST     := /etc/apt/sources.list.d/cuda-ubuntu$(UBUNTU_VER)-x86_64.list

CUDA_SYMLINK_SENTINEL := $(if $(CUDA_VER),.sentinel/cuda-symlink,)

INSTALL  := /usr/bin/appimagelauncher /usr/bin/code /usr/bin/google-chrome $(CUDA_LIST) $(NVCC) $(CUDA_SYMLINK_SENTINEL) /etc/systemd/system/suspend.target .sentinel/syncthing-gui-remote .sentinel/cockpit-enabled .sentinel/grub-timeout-set
PENDING  := $(filter-out $(wildcard $(INSTALL)),$(INSTALL))

level-1: $(PENDING)
	apt autoremove

## Resolve packages by URL: explicit rule per binary
/usr/bin/google-chrome: $(DOWNLOADS_DIR)/google-chrome-stable_current_amd64.deb
	apt install -y $<

$(NVCC): | $(CUDA_LIST)
	@test $$(id -u) -eq 0 || { echo ">>> CUDA install requires root. Run: sudo make"; exit 1; }
	apt update
	apt install -y $(CUDA_PKG)

.sentinel/cuda-symlink: | .sentinel
	@test $$(id -u) -eq 0 || { echo ">>> CUDA symlink requires root. Run: sudo make"; exit 1; }
	ln -sfn /usr/local/cuda-$(CUDA_VER) /usr/local/cuda
	touch $@
	@echo ">>> /usr/local/cuda -> /usr/local/cuda-$(CUDA_VER)"

$(CUDA_LIST): /usr/share/keyrings/cuda-keyring.gpg
	@test $$(id -u) -eq 0 || { echo ">>> CUDA install requires root. Run: sudo make"; exit 1; }
	echo 'deb [signed-by=$<] $(CUDA_REPO)/ /' > $@

/usr/share/keyrings/cuda-keyring.gpg:
	@test $$(id -u) -eq 0 || { echo ">>> CUDA install requires root. Run: sudo make"; exit 1; }
	mkdir -p $(dir $@)
	curl -fsSL $(CUDA_REPO)/cuda-archive-keyring.gpg -o $@



## Resolve packages by Custom Repository URL: Define explicit rule per Repository
/usr/bin/%: /etc/apt/sources.list.d/%.list
	apt update
	apt install -y $*

## Resolve packages using apt global search
/usr/bin/%: ## pattern 1: standard apt — apt-file resolves package from binary path; add /usr/bin/<pkg> to INSTALL
	apt install -y $$(apt-file search $@ 2>/dev/null | awk -F': ' '{print $$1}' | head -1)

#
# Custom apt repositories — one .list target per package (see Resolve packages by Custom Repository URL above)
#

/etc/apt/sources.list.d/appimagelauncher.list:
	add-apt-repository -y ppa:appimagelauncher-team/stable
	mv /etc/apt/sources.list.d/appimagelauncher-team-ubuntu-stable-$$(lsb_release -cs).list $@

/etc/apt/sources.list.d/code.list: /usr/share/keyrings/microsoft.gpg
	echo 'deb [arch=amd64 signed-by=$<] https://packages.microsoft.com/repos/code stable main' > $@

/usr/share/keyrings/microsoft.gpg:
	mkdir -p $(dir $@)
	curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > $@

#
# END of Package setup
#

# Prevent machine to become unreachable
/etc/systemd/system/suspend.target:
	systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
	@echo ">>> Suspend disabled"

$(DOWNLOADS_DIR)/%: | $(DOWNLOADS_DIR)
	curl -fsSL $(filter %/$*,$(DEB_URLS)) -o $@

$(DOWNLOADS_DIR):
	mkdir -p $@

ST_USER ?= m
ST_PASS ?= change-me

.sentinel: ## pattern 4: side-effect — add .sentinel/<name> target + touch $@; add to INSTALL
	mkdir -p $@

.sentinel/syncthing-gui-remote: .sentinel/syncthing-enabled | .sentinel
	@USERX=$${SUDO_USER:-$$USER}; \
	HOME_DIR=$$(getent passwd $$USERX | cut -d: -f6); \
	KEY=$$(grep -rh '<apikey>' \
	$$HOME_DIR/.config/syncthing/config.xml \
	$$HOME_DIR/.local/state/syncthing/config.xml 2>/dev/null | \
	sed -n 's:.*<apikey>\(.*\)</apikey>.*:\1:p' | head -1); \
	curl -sS -X PATCH http://localhost:8384/rest/config/gui \
	-H "X-API-Key: $$KEY" \
	-H "Content-Type: application/json" \
	-d "{\"address\":\"0.0.0.0:8384\",\"user\":\"$(ST_USER)\",\"password\":\"$(ST_PASS)\"}"
	@touch $@
	@echo ">>> Syncthing GUI remote enabled"

.sentinel/syncthing-enabled: /usr/bin/syncthing | .sentinel
	@USERX=$${SUDO_USER:-$$USER}; \
	loginctl enable-linger $$USERX; \
	sudo -u $$USERX env XDG_RUNTIME_DIR=/run/user/$$(id -u $$USERX) \
		systemctl --user enable --now syncthing
	touch $@
	@echo ">>> Syncthing enabled"

.sentinel/cockpit-enabled: /usr/bin/cockpit | .sentinel
	systemctl enable --now cockpit.socket
	@IP=$$(hostname -I | awk '{print $$1}'); \
	echo ">>> Cockpit: https://$$IP:9090"
	touch $@

.sentinel/grub-timeout-set: | .sentinel
	@test -f /etc/default/grub && sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=3/' /etc/default/grub && update-grub && echo ">>> GRUB timeout = 3" || echo ">>> /etc/default/grub not found, skipping"
	touch $@


# ----------------------------------------------------------
# User setup (make, no sudo)
# ----------------------------------------------------------

.PHONY: setup

DIGIKAM_VERSION  := 9.0.0
DIGIKAM_URL      := https://download.kde.org/stable/digikam/$(DIGIKAM_VERSION)/digiKam-$(DIGIKAM_VERSION)-Qt6-x86-64.appimage

APPS_URLS = $(DIGIKAM_URL)
APPS_DIR = $(HOME)/.local/share/AppImages
APPS = $(foreach u,$(APPS_URLS),$(APPS_DIR)/$(notdir $(u)))
setup: $(APPS) make-completion

$(APPS_DIR)/%: | $(APPS_DIR)
	curl -fsSL  --progress-bar $(filter %/$*,$(APPS_URLS)) -o $@
	chmod +x $@
	command -v ail-cli >/dev/null 2>&1 && ail-cli integrate $@ || echo ">>> appimagelauncher not installed — run: sudo make, then: make integrate-apps"

$(APPS_DIR):
	mkdir -p $@

.PHONY: integrate-apps
integrate-apps: /usr/bin/appimagelauncher
	for app in $(APPS); do ail-cli integrate $$app; done
	kbuildsycoca6

.PHONY: make-completion
BASHRC          = $(HOME)/.bashrc
MAKE_COMPLETION = /usr/share/bash-completion/completions/make
make-completion:
	@grep -q 'bash-completion/completions/make' $(BASHRC) 2>/dev/null || \
	echo 'source $(MAKE_COMPLETION)' >> $(BASHRC)
	@echo ">>> Make autocomplete enabled"

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
# SN8100
# ----------------------------------------------------------

.PHONY: detect-sn8100
detect-sn8100:
	@echo 1 > /sys/bus/pci/rescan
	@sleep 1
	@lsblk -d -o NAME,SIZE,MODEL | grep -E 'nvme|SN8100' || true

.PHONY: backup-mount
backup-mount:
	@sed -i '\|/mnt/backup|d' /etc/fstab 2>/dev/null || true
	@printf '%s\n' \
		'[Unit]' 'Description=NVMe backup drive (SN8100)' '' \
		'[Mount]' 'What=/dev/disk/by-label/backup' 'Where=/mnt/backup' 'Type=ext4' 'Options=defaults,noatime' '' \
		'[Install]' 'WantedBy=multi-user.target' \
		> /etc/systemd/system/mnt-backup.mount
	@printf '%s\n' \
		'[Unit]' 'Description=Automount NVMe backup drive (SN8100)' '' \
		'[Automount]' 'Where=/mnt/backup' 'TimeoutIdleSec=0' '' \
		'[Install]' 'WantedBy=multi-user.target' \
		> /etc/systemd/system/mnt-backup.automount
	@systemctl daemon-reload
	@systemctl enable --now mnt-backup.automount
	@systemctl start mnt-backup.mount
	@chmod 1777 /mnt/backup
	@echo ">>> SN8100 automount enabled at /mnt/backup"

.PHONY: eject
eject:
	@DEV=$$(lsblk -dno NAME,MODEL | awk '/SN8100/{print $$1; exit}'); \
	[ -n "$$DEV" ] || { echo "SN8100 not found"; exit 1; }; \
	echo 1 > /sys/block/$$DEV/device/remove
	@echo ">>> Ejected $$DEV"

# ----------------------------------------------------------
# Inference — llama.cpp. make infer-server builds everything on first run.
# ----------------------------------------------------------

MODEL_DIR  ?= $(HOME)/models
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
LLAMA_BINS = $(HOME)/.local/bin
LLAMA_BIN  = $(LLAMA_BINS)/llama-bench

.PHONY: infer-server
infer-server: $(LLAMA_BIN) $(MODEL_META)
	@echo ">>> Serving on http://0.0.0.0:8080 — GPU_LAYERS=$(N_GPU_LAYERS) CTX=$(CTX_SIZE)"
	llama-server -m $(MODEL_PATH) $(INFER_FLAGS) --host 0.0.0.0 --port 8080

LLAMA_TAG = b9075
LLAMA_SRC = $(DOWNLOADS_DIR)/llama.cpp-$(LLAMA_TAG)

$(LLAMA_BIN): $(NVCC) $(LLAMA_SRC) | $(LLAMA_BINS)
	cmake -B $(LLAMA_SRC)/build -S $(LLAMA_SRC) \
		-DGGML_CUDA=ON \
		-DCMAKE_CUDA_COMPILER=$(NVCC) \
		-DCUDA_TOOLKIT_ROOT_DIR=$(patsubst %/bin/nvcc,%,$(NVCC)) \
		-DCUDAToolkit_ROOT=$(patsubst %/bin/nvcc,%,$(NVCC)) \
		-DCMAKE_EXE_LINKER_FLAGS="-L$(patsubst %/bin/nvcc,%,$(NVCC))/lib64 -Wl,-rpath,$(patsubst %/bin/nvcc,%,$(NVCC))/lib64" \
		-DCMAKE_CUDA_ARCHITECTURES=$(SYS_SM) \
		-DCMAKE_BUILD_TYPE=Release \
		-DBUILD_SHARED_LIBS=OFF
	cmake --build $(LLAMA_SRC)/build -j$$(nproc)
	cp $(LLAMA_SRC)/build/bin/llama-bench $(LLAMA_SRC)/build/bin/llama-server $(LLAMA_SRC)/build/bin/llama-cli $(LLAMA_BINS)/
	@echo ">>> llama.cpp $(LLAMA_TAG) built with CUDA"

$(LLAMA_SRC): $(LLAMA_SRC).tar.gz
	tar -xzf $< -C $(DOWNLOADS_DIR)

$(LLAMA_SRC).tar.gz: | $(DOWNLOADS_DIR)
	curl -fsSL https://github.com/ggerganov/llama.cpp/archive/refs/tags/$(LLAMA_TAG).tar.gz -o $@

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

## Wipe llama.cpp build — hardware is re-assessed at parse time on next run
.PHONY: clean-infer
clean-infer:
	rm -f $(LLAMA_BINS)/llama-bench $(LLAMA_BINS)/llama-server $(LLAMA_BINS)/llama-cli
	rm -rf $(LLAMA_SRC)

.PHONY: clean
clean:
	rm -rf $(LLAMA_SRC)
	rm -f $(LLAMA_BINS)/llama-bench $(LLAMA_BINS)/llama-server $(LLAMA_BINS)/llama-cli
