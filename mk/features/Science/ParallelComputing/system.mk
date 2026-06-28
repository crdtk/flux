GPU_BDF := $(shell lspci -D 2>/dev/null | awk '/VGA.*NVIDIA/{print $$1; exit}')

NVCC    := /usr/local/cuda/bin/nvcc
COMPUTE += /usr/bin/nvidia-smi $(NVCC)

/usr/bin/nvidia-smi:
	ubuntu-drivers install

CUDA_LIST := /etc/apt/sources.list.d/cuda-ubuntu$(UBUNTU_VER)-x86_64.list
CUDA_PKG  ?= cuda-toolkit
$(NVCC): | $(CUDA_LIST)
	@$(APT) update && $(APT) install -y $(CUDA_PKG)

CUDA_KEYRING_DEB := $(DOWNLOADS_DIR)/cuda-keyring_1.1-1_all.deb
$(CUDA_LIST): $(CUDA_KEYRING_DEB)
	$(APT) install -y $<

CUDA_REPO := https://developer.download.nvidia.com/compute/cuda/repos/ubuntu$(UBUNTU_VER)/x86_64
$(CUDA_KEYRING_DEB): | $(DOWNLOADS_DIR)
	curl -fsSL $(CUDA_REPO)/cuda-keyring_1.1-1_all.deb -o $@
