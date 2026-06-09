MAKEFLAGS += --no-builtin-rules
.SUFFIXES:

USER_HOME     ?= $(shell getent passwd $${SUDO_USER:-$$(whoami)} | cut -d: -f6)
DOWNLOADS_DIR ?= $(USER_HOME)/Downloads
MODEL_DIR     ?= $(USER_HOME)/models
NVCC          ?= /usr/local/cuda/bin/nvcc
SYS_SM        ?= $(shell nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 | tr -d '.' | grep -oE '^[0-9]+')

SENTINEL := $(CURDIR)/.sentinel
$(shell mkdir -p $(SENTINEL))

# ----------------------------------------------------------
# CUDA rsqrt patch — fixes glibc 2.41 conflict in CUDA 13.1 headers
# ----------------------------------------------------------

CUDA_MATH_H   := /usr/local/cuda/targets/x86_64-linux/include/crt/math_functions.h
CUDA_MATH_HPP := /usr/local/cuda/targets/x86_64-linux/include/crt/math_functions.hpp

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

$(SENTINEL)/cuda-rsqrt-patched:
	@test -f $(CUDA_MATH_H) || { echo ">>> CUDA not installed — run: sudo make from project root"; exit 1; }
	sed -i -E '/\brsqrtf?\b/{ /__device__/! { /noexcept/! s/\);$$/) noexcept;/ } }' $(CUDA_MATH_H)
	$(file >/tmp/cuda_hpp_patch.py,$(CUDA_HPP_PATCH_PY))
	python3 /tmp/cuda_hpp_patch.py $(CUDA_MATH_HPP)
	touch $@
	@echo ">>> CUDA math_functions patched for glibc 2.41"

# ----------------------------------------------------------
# llama.cpp build
# ----------------------------------------------------------

SYS_THREADS  := $(shell nproc)
LLAMA_BINS    = $(USER_HOME)/.local/bin
LLAMA_BIN     = $(LLAMA_BINS)/llama-bench
LLAMA_TAG     = b9222
LLAMA_SRC     = $(DOWNLOADS_DIR)/llama.cpp-$(LLAMA_TAG)
CUDA_ROOT    := $(patsubst %/bin/nvcc,%,$(NVCC))
# CUDA 13.x does not support GCC 15 (Ubuntu 26.04 default); use g++-14 as host compiler
CUDA_HOST_CC  := $(firstword $(wildcard /usr/bin/g++-14 /usr/bin/g++-13 /usr/bin/g++-12))
CUDA_HOST_FLAG = $(if $(CUDA_HOST_CC),-DCMAKE_CUDA_HOST_COMPILER=$(CUDA_HOST_CC),)

$(LLAMA_BIN): $(LLAMA_SRC) $(SENTINEL)/cuda-rsqrt-patched | $(LLAMA_BINS)
	@test -x $(NVCC) || { echo ">>> CUDA not installed — run: sudo make from project root"; exit 1; }
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

$(DOWNLOADS_DIR):
	mkdir -p $@

$(LLAMA_BINS):
	mkdir -p $@

# ----------------------------------------------------------
# Model download
# ----------------------------------------------------------

MODEL_FILE := Qwen3-Coder-30B-A3B-Instruct-480B-Distill-V2-Fp32.i1-Q4_K_M.gguf
MODEL_PATH := $(MODEL_DIR)/$(MODEL_FILE)
MODEL_META := $(MODEL_DIR)/.cache/huggingface/download/$(MODEL_FILE).metadata
MODEL_HF    = mradermacher/Qwen3-Coder-30B-A3B-Instruct-480B-Distill-V2-Fp32-i1-GGUF
HF_CLI      = $(LLAMA_BINS)/hf
.PRECIOUS: $(MODEL_PATH) $(MODEL_META)

$(MODEL_META): | $(MODEL_DIR) $(HF_CLI)
	$(HF_CLI) download $(MODEL_HF) $(MODEL_FILE) --local-dir $(MODEL_DIR)
	@echo ">>> Model ready: $(MODEL_PATH)"

$(MODEL_DIR):
	mkdir -p $@

$(HF_CLI):
	pip install --user huggingface_hub
	@echo ">>> huggingface-cli installed"

# ----------------------------------------------------------
# Inference server
# ----------------------------------------------------------

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

.PHONY: infer-server
infer-server: $(LLAMA_BIN) $(MODEL_META)
	@echo ">>> Serving on http://0.0.0.0:8080 — GPU_LAYERS=$(N_GPU_LAYERS) CTX=$(CTX_SIZE)"
	llama-server -m $(MODEL_PATH) $(INFER_FLAGS) --host 0.0.0.0 --port 8080

# ----------------------------------------------------------
# Clean
# ----------------------------------------------------------

.PHONY: clean
clean:
	rm -f $(LLAMA_BINS)/llama-bench $(LLAMA_BINS)/llama-server $(LLAMA_BINS)/llama-cli
	rm -rf $(LLAMA_SRC)
	rm -f $(SENTINEL)/cuda-rsqrt-patched
	@echo ">>> llama.cpp build cleaned"
