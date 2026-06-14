SYS_SM           := $(shell nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 | tr -d '.' | grep -oE '^[0-9]+')
GPU_BDF          := $(shell lspci -D 2>/dev/null | awk '/VGA.*NVIDIA/{print $$1; exit}')
NVCC             := /usr/local/cuda/bin/nvcc
CUDA_LIST        := /etc/apt/sources.list.d/cuda-ubuntu$(UBUNTU_VER)-x86_64.list
CUDA_REPO        := https://developer.download.nvidia.com/compute/cuda/repos/ubuntu$(UBUNTU_VER)/x86_64
CUDA_KEYRING_DEB := $(DOWNLOADS_DIR)/cuda-keyring_1.1-1_all.deb

COMPUTE += \
  /usr/bin/nvidia-smi \
  $(NVCC) \
  /usr/bin/cmake \
  /usr/bin/g++-14

/usr/bin/nvidia-smi:
	ubuntu-drivers install

CUDA_PKG ?= cuda-toolkit
$(NVCC): | $(CUDA_LIST)
	@[ -n "$(IS_ROOT)" ] || { echo ">>> CUDA install requires root. Run: sudo make"; exit 1; }
	$(APT) update
	$(APT) install -y $(CUDA_PKG)

$(CUDA_LIST): $(CUDA_KEYRING_DEB)
	@[ -n "$(IS_ROOT)" ] || { echo ">>> CUDA repo setup requires root. Run: sudo make"; exit 1; }
	$(APT) install -y $<

$(CUDA_KEYRING_DEB): | $(DOWNLOADS_DIR)
	curl -fsSL $(CUDA_REPO)/cuda-keyring_1.1-1_all.deb -o $@
