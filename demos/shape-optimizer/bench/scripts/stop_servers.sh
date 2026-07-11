#!/usr/bin/env bash
# Stop baseline and fp8 vLLM servers started by start_servers.sh
set -euo pipefail

for pid_file in /tmp/vllm-base.pid /tmp/vllm-fp8.pid; do
    if [ -f "${pid_file}" ]; then
        pid=$(cat "${pid_file}")
        if kill "${pid}" 2>/dev/null; then
            echo ">>> stopped PID ${pid} (${pid_file})"
        fi
        rm -f "${pid_file}"
    fi
done

# Pattern fallback: pid files are consumed on first stop, so a re-run must still
# find strays — an unkilled old baseline answers the health poll while a doomed
# duplicate loads ~4 GiB of weights, and the pair OOMs the fp8 server.
if pkill -f 'vllm serve .*--port 800[01]' 2>/dev/null; then
    echo ">>> stopped stray vllm serve processes (pattern fallback)"
fi

# Wait until the strays actually exit — the next start budgets 0.42 of the card
# and a lingering EngineCore makes that arithmetic false.
for i in $(seq 30); do
    pgrep -f 'vllm serve .*--port 800[01]' >/dev/null 2>&1 || break
    sleep 1
done
echo ">>> done"
