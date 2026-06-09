#!/usr/bin/env bash
# Stop baseline and TurboQuant vLLM servers started by start_servers.sh
set -euo pipefail

for pid_file in /tmp/vllm-base.pid /tmp/vllm-tq.pid; do
    if [ -f "${pid_file}" ]; then
        pid=$(cat "${pid_file}")
        if kill "${pid}" 2>/dev/null; then
            echo ">>> stopped PID ${pid} (${pid_file})"
        fi
        rm -f "${pid_file}"
    fi
done
echo ">>> done"
