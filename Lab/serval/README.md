# System76 Serval WS (serw9) — Daily Driver / Orchestration Node

**Model**: Serval WS · **Revision**: serw9  
**Role**: `serval` — always-on: API gateway, monitoring, model sync, build triggers, daily driver

---

## Hardware Inventory

| Component | Detail |
|-----------|--------|
| **Form** | 17.3" laptop, desktop-replacement chassis |
| **CPU** | Intel Core i7-6700K @ 4.00 GHz · 4C/8T · 8MB L3 · Skylake · 91W TDP · LGA1151 |
| **Chipset** | Intel Z170 |
| **GPU** | NVIDIA GeForce GTX 980M · 8GB GDDR5 · PCIe 3.0 x16 · GM204M |
| **RAM** | 2× Samsung M471A2K43BB1-CPB · 16GB DDR4-2133 SODIMM = 32GB · max 64GB (2× 32GB SODIMM) · both slots filled (other 2 of 4 owned SODIMMs are in crucible) |
| **Storage** | Samsung SSD 950 PRO 512GB · NVMe PCIe 3.0 x4 · M.2 2280 |
| **Display** | 17.3" 1920×1080 IPS (LVDS) |
| **Thunderbolt** | TB3 / USB-C · Intel Alpine Ridge DSL6340 · 2015 |
| **WiFi** | Intel Wireless 3165 · 802.11ac · 2×2 |
| **Ethernet** | 1× GbE (enp59s0) |
| **WWAN** | Huawei ME936 · LTE/HSDPA+ 4G |
| **Bluetooth** | 4.2 (Intel) |
| **Fingerprint** | LighTuning ES603 swipe sensor |
| **Camera** | BisonCam NB Pro |
| **Battery** | 56 Wh |
| **OS** | Pop!_OS 22.04 LTS |

---

## Role in the Lab

### Always-On Services
- **API gateway**: LiteLLM proxy → unified `http://serval:8080/v1` OpenAI-compatible endpoint, backends switchable between `forge` and `crucible`
- **Monitoring**: Prometheus + Grafana + node_exporter scraping all nodes; DCGM exporter for GPU metrics
- **Syncthing**: primary sync hub for model weight distribution and config replication
- **WoL orchestrator**: magic-packet boot of `crucible` and `forge` on demand; auto-shutdown hooks after idle timeout

### Daily Use
- Development, prompt engineering, browsing
- Makefile authoring and `make -n` validation before running on target nodes
- SSH jump host into `crucible` (IPMI) and `forge`

### Inference
- GTX 980M 8GB — draft model for speculative decoding paired with Crucible's 397B main model (7B draft → 2–4× effective throughput)
- Small-model development (7B, 13B) without touching the production cluster

---

## Upgrade Notes

- RAM: likely 4× SO-DIMM slots (DDR4); 32GB installed; check if slots free for expansion
- Storage: M.2 + 2.5" SATA bay likely available for a second drive (model weight cache)
- Thunderbolt 3: supports eGPU via TB3 enclosure if GPU bottleneck becomes limiting before EPYC arrives
