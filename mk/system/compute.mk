SYS_SM           := $(shell nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 | tr -d '.' | grep -oE '^[0-9]+')
NVCC             := /usr/local/cuda/bin/nvcc
CUDA_LIST        := /etc/apt/sources.list.d/cuda-ubuntu$(UBUNTU_VER)-x86_64.list
CUDA_REPO        := https://developer.download.nvidia.com/compute/cuda/repos/ubuntu$(UBUNTU_VER)/x86_64
CUDA_KEYRING_DEB := $(DOWNLOADS_DIR)/cuda-keyring_1.1-1_all.deb
UV               := $(USER_HOME)/.local/bin/uv
WHISPER_VENV     := $(USER_HOME)/.local/share/whisper-venv
WHISPER_TARGET   := $(WHISPER_VENV)/lib/python3.12/site-packages/faster_whisper

COMPUTE += \
  /usr/bin/nvidia-smi \
  $(NVCC) \
  /usr/bin/cmake \
  /usr/bin/g++-14 \
  $(WHISPER_TARGET)

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
