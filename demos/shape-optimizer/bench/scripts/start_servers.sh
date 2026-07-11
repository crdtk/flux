#!/usr/bin/env bash
# Start baseline (port 8001) then FP8-KV (port 8000) vLLM servers sequentially.
# Restored from 8cb3df4:demos/turboquant/scripts/start_servers.sh; the second
# server now uses stock --kv-cache-dtype fp8 instead of the TURBOQUANT=1 patch.
#
# Sequential start is required on a single GPU: simultaneous profiling runs cause OOM.
# --enforce-eager: skips CUDA graph pre-allocation (saves ~560 MiB per server),
#   freeing enough KV cache budget for 8192-token sequences on a 16 GB A4000.
#   Without eager mode, KV pool = 389 MiB < 448 MiB needed for max_seq_len=8192.
#
# Usage: ./start_servers.sh <model_dir>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV="${SCRIPT_DIR}/../.venv"
MODEL="${1:?Usage: start_servers.sh <model_dir>}"

# vllm is invoked by absolute path (venv never activated), but the fp8 engine
# JIT-compiles kernels at init and spawns `ninja` via PATH lookup — without
# .venv/bin on PATH it dies with FileNotFoundError('ninja') even though ninja
# is installed. The bf16 baseline compiles nothing, which masks this.
export PATH="${VENV}/bin:${PATH}"

_wait_healthy() {
    local port=$1 name=$2 timeout=${3:-240}
    echo ">>> waiting for ${name} on :${port} (up to ${timeout}s)..."
    for i in $(seq "${timeout}"); do
        curl -sf "http://localhost:${port}/health" > /dev/null 2>&1 && \
            echo ">>> ${name} ready" && return 0
        sleep 1
    done
    echo ">>> ${name} timeout — check /tmp/vllm-${name}.log"
    return 1
}

# --- baseline, bf16 KV (port 8001) ---
echo ">>> starting baseline :8001  log=/tmp/vllm-base.log"
"${VENV}/bin/vllm" serve "${MODEL}" \
    --port 8001 \
    --served-model-name default \
    --gpu-memory-utilization 0.42 \
    --max-model-len 8192 \
    --dtype bfloat16 \
    --enforce-eager \
    > /tmp/vllm-base.log 2>&1 &
echo $! > /tmp/vllm-base.pid
_wait_healthy 8001 base 240

# --- FP8 KV cache (port 8000) — starts AFTER baseline is healthy ---
echo ">>> starting fp8-kv :8000  log=/tmp/vllm-fp8.log"
"${VENV}/bin/vllm" serve "${MODEL}" \
    --port 8000 \
    --served-model-name default \
    --gpu-memory-utilization 0.42 \
    --max-model-len 8192 \
    --dtype bfloat16 \
    --kv-cache-dtype fp8 \
    --enforce-eager \
    > /tmp/vllm-fp8.log 2>&1 &
echo $! > /tmp/vllm-fp8.pid
_wait_healthy 8000 fp8 240

echo ">>> both servers ready (baseline :8001, fp8 :8000)"
