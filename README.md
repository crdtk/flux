# 🏺 Crucible: The High-Performance AI Lab

Crucible is a research-grade LLM inference lab designed to sidestep the 2026 global RAM crisis. It is a "furnace" where we forge high-speed, open-source alternatives to frontier models like Claude 4.5 and GPT-5, running on local, cost-optimized hardware.

## 🚀 The Spotlight: [Prefix Caching Demo](demos/prefix-caching/prefix_caching_demo.ipynb)

The crown jewel of our current experiments is the **Prefix Caching Optimization**. 

In 2026, the bottleneck for local coding assistants isn't just raw FLOPs—it's the cost of re-processing massive codebases on every request. This demo showcases how we achieve near-instantaneous "prefill" times for long contexts using **vLLM's RadixAttention**.

### Why it matters for "Claude Code" alternatives:
*   **Zero-latency Context:** Re-querying the same 100k-token project context costs **0ms** of prefill computation after the first hit.
*   **INT4 KV Quantization:** Fits 4× more concurrent context windows into VRAM, enabling massive "thought buffers" for reasoning models.
*   **Strategic Memory Placement:** Demonstrates how to structure prompts so that session IDs and dynamic data don't "bust" the cache.

**Run the experiment:**
```bash
make -C demos/prefix-caching colab-upload  # Launch in the cloud
# OR
make -C demos/prefix-caching demo-notebook # Launch locally
```

---

## 🛠️ The Automation Engine (`mk/`)

Crucible isn't just a collection of scripts; it is **provisioning-as-code**. The laboratory infrastructure is managed through a modular Makefile system located in `mk/`. This ensures that our high-performance environment is reproducible, hardened, and optimized for maximum `tok/s`.

| Layer | Responsibility |
| :--- | :--- |
| **`mk/system/`** | Core infrastructure: compute, storage, 10GbE networking, and hardening. |
| **`mk/user/`** | Developer experience: AI CLI tools, VS Code optimization, and environment settings. |
| **`mk/display.mk`** | Real-time telemetry and lab status dashboard. |
| **`mk/clean.mk`** | Atomic "reset" of the lab state for clean experimentation. |

Every experiment in the `demos/` directory relies on this foundational automation to ensure hardware-accelerated drivers (NVIDIA/CUDA) and optimized runtimes are correctly configured.

---

## 🏗️ The Build: Sidestepping the 2026 Crisis

We operate on the **"VRAM-First" principle**. While the industry panics over DDR5 RDIMM prices, Crucible leverages:

*   **Legacy Reuse:** High-density DDR4 SODIMMs (recycled from mobile workstations) for system RAM.
*   **PCIe Switching:** A Broadcom PEX88048 switch card to drive **4× NVIDIA RTX PRO 6000 Blackwell GPUs** from a single Mini-ITX slot.
*   **Expert Parallelism:** Optimized expert-routing for MoE models like **Qwen3.5-397B**, achieving >120 tok/s by reading only active weights.

Detailed hardware specs and build logs can be found in the [Lab/](Lab/) and [References/](References/) directories.

---

## 📂 Project Structure

*   `demos/`: High-signal AI experiments (Prefix Caching, LLMs from scratch, etc.).
*   `Lab/`: Research articles, risk assessments, and hardware validation logs.
*   `mk/`: The modular automation system (The "OS" of the lab).
*   `References/`: Datasheets and manuals for the lab's hardware components.

---

*“The RAM crisis is only a crisis if you think system RAM matters for inference. It doesn’t. VRAM is king.”* — [ARTICLE.md](Lab/ARTICLE.md)
