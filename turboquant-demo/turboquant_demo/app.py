"""
Streamlit demo: baseline (bf16 KV) vs TurboQuant (3b key / 2b val KV).

Shows side-by-side streaming responses with live VRAM gauge and tok/s metrics
for two corporate scenarios: fashion fit recommendation and legal document review.

Requires: make demo-servers   (baseline on :8001, TQ on :8000)
Run:      streamlit run turboquant_demo/app.py
"""
import threading
import time

import streamlit as st
from openai import OpenAI

from turboquant_demo.bert import extract_fit_signal

try:
    import pynvml
    pynvml.nvmlInit()
    _HAS_NVML = True
except Exception:
    _HAS_NVML = False

_BASE = OpenAI(base_url="http://localhost:8001/v1", api_key="x")
_TQ   = OpenAI(base_url="http://localhost:8000/v1", api_key="x")

_VRAM_TOTAL_MB = 16_384  # RTX A4000


def _vram_used_mb() -> int:
    if not _HAS_NVML:
        return 0
    info = pynvml.nvmlDeviceGetMemoryInfo(pynvml.nvmlDeviceGetHandleByIndex(0))
    return info.used // 1024 ** 2


# --- Scenario documents ---

_CUSTOMER_HISTORY = """\
Customer purchase history — 47 items, 3 years:

  Item 36 (Mar 2022): Levi's 501 32W 32L  → RETURNED: thighs too tight, waist perfect
  Item 37 (Jun 2022): Hugo Boss chino 32   → kept
  Item 38 (Nov 2023): Uniqlo slim fit 32   → RETURNED: thighs too tight again
  Item 39 (Jan 2024): Gap relaxed 33W 30L  → kept — "finally found my fit"
  Item 40 (Mar 2024): Levi's 502 33W 30L   → kept
  Item 41 (Nov 2024): Levi's 541 33W 30L   → kept — "athletic fit works for me"
  Item 42 (Apr 2025): [TARGET] Levi's 501 32W 32L — advise correct size?
"""

_LEGAL_DOC = (
    "A " * 6_000
    + " INDEMNIFICATION CLAUSE: The Seller's aggregate liability under this Agreement"
    + " shall not exceed USD 50,000,000. The Buyer's indemnification obligation is"
    + " limited to 30% of the total deal consideration. All representations and"
    + " warranties shall survive for a period of 18 months following the Closing Date."
)

_SCENARIOS = {
    "Fashion: size recommendation (full 3-year history)": _CUSTOMER_HISTORY,
    "Legal: liability caps in merger agreement":          _LEGAL_DOC,
}


# --- Streamlit UI ---

st.set_page_config(page_title="TurboQuant Demo", layout="wide")
st.title("TurboQuant — KV Cache Compression")
st.caption(
    "RTX A4000 16 GB  ·  DeepSeek-R1-Distill-Qwen-7B (AWQ)  ·  3-bit key / 2-bit value"
)

scenario = st.selectbox("Scenario", list(_SCENARIOS))
ret_text = st.text_area(
    "Customer return text",
    "The jeans were too tight in the thighs but the waist fit perfectly",
)

if st.button("Run comparison", type="primary"):
    sig = extract_fit_signal(ret_text)
    st.info(
        f"BERT signal: **{sig['direction']}** in **{', '.join(sig['regions'])}**  "
        f"({sig['confidence']:.0%} confidence · {sig['latency_ms']:.0f} ms)"
    )

    doc    = _SCENARIOS[scenario]
    prompt = (
        f"{doc}\n\n"
        f"Customer return: {ret_text}\n\n"
        f"What size should this customer order? Cite specific evidence from their history."
    )

    col_base, col_tq = st.columns(2)

    with col_base:
        st.subheader("Baseline — bf16 KV")
        vram_bar_base  = st.empty()
        metrics_base   = st.empty()
        response_base  = st.empty()

    with col_tq:
        st.subheader("TurboQuant — 3b key / 2b val")
        vram_bar_tq  = st.empty()
        metrics_tq   = st.empty()
        response_tq  = st.empty()

    _active = {"running": True}

    def _poll_vram() -> None:
        while _active["running"]:
            mb  = _vram_used_mb()
            pct = mb / _VRAM_TOTAL_MB
            vram_bar_base.progress(pct, f"VRAM {mb / 1024:.1f} GB / 16 GB")
            vram_bar_tq.progress(pct,   f"VRAM {mb / 1024:.1f} GB / 16 GB")
            time.sleep(0.4)

    def _stream(client: OpenAI, metrics, response_box) -> None:
        t0   = time.time()
        n    = 0
        text = ""
        try:
            with client.chat.completions.create(
                model="default",
                messages=[{"role": "user", "content": prompt}],
                max_tokens=256,
                stream=True,
            ) as stream:
                for chunk in stream:
                    delta = chunk.choices[0].delta.content or ""
                    text += delta
                    n    += 1
                    metrics.metric("tok/s", f"{n / max(time.time() - t0, 0.01):.1f}")
                    response_box.markdown(text)
        except Exception as exc:
            response_box.error(f"{exc}\n\nStart servers: `make demo-servers`")

    threading.Thread(target=_poll_vram, daemon=True).start()

    t_base = threading.Thread(target=_stream, args=(_BASE, metrics_base, response_base))
    t_tq   = threading.Thread(target=_stream, args=(_TQ,  metrics_tq,   response_tq))
    t_base.start()
    t_tq.start()
    t_base.join()
    t_tq.join()
    _active["running"] = False
