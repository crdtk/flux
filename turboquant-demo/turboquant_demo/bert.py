"""
Zero-shot fit signal extraction from customer return text.

Uses a small cross-encoder NLI model to classify:
  - which body region is mentioned (thighs, waist, shoulders, ...)
  - which fit direction (too tight, too large, perfect, ...)

Run standalone:  python -m turboquant_demo.bert
"""
import time

from transformers import pipeline as hf_pipeline

REGIONS = [
    "thighs", "waist", "shoulders", "chest",
    "hips", "length", "sleeves",
]

# Full-sentence hypotheses work better with cross-encoder NLI models
_DIRECTION_LABELS = [
    "too tight", "too small", "too loose", "too large",
    "runs small", "runs large", "perfect fit", "true to size",
]
_DIRECTION_HYPS = [
    "The clothing item was too tight or constricting",
    "The clothing item was too small and did not fit",
    "The clothing item was too loose or baggy",
    "The clothing item was too large or oversized",
    "The clothing item runs small, smaller than labelled",
    "The clothing item runs large, larger than labelled",
    "The clothing item fit perfectly and the customer is happy",
    "The clothing item fits exactly true to size as expected",
]
_REGION_HYPS = {
    "thighs":    "The fit problem is in the thigh area",
    "waist":     "The fit problem is at the waist",
    "shoulders": "The fit problem is at the shoulders",
    "chest":     "The fit problem is across the chest",
    "hips":      "The fit problem is at the hips",
    "length":    "The length of the item is mentioned",
    "sleeves":   "The fit problem is in the sleeves",
}

_clf = None


def _get_clf():
    global _clf
    if _clf is None:
        _clf = hf_pipeline(
            "zero-shot-classification",
            model="cross-encoder/nli-deberta-v3-small",
        )
    return _clf


def extract_fit_signal(text: str) -> dict:
    """Return structured fit signal from a customer return description."""
    clf = _get_clf()
    t0  = time.perf_counter()

    direction_result = clf(text, candidate_labels=_DIRECTION_HYPS)
    region_result    = clf(text, candidate_labels=list(_REGION_HYPS.values()),
                           multi_label=True)

    ms = (time.perf_counter() - t0) * 1000

    # Map winning hypothesis back to short label
    hyp_to_label     = dict(zip(_DIRECTION_HYPS, _DIRECTION_LABELS))
    region_hyp_to_name = {v: k for k, v in _REGION_HYPS.items()}
    direction  = hyp_to_label[direction_result["labels"][0]]
    confidence = direction_result["scores"][0]

    regions = [
        region_hyp_to_name[hyp]
        for hyp, score in zip(region_result["labels"], region_result["scores"])
        if score > 0.5
    ] or [region_hyp_to_name[region_result["labels"][0]]]

    return {
        "direction":  direction,
        "confidence": confidence,
        "regions":    regions,
        "latency_ms": ms,
    }


_SAMPLES = [
    "The jeans were too tight in the thighs but the waist fit perfectly",
    "Runs very large overall, should have ordered a size down",
    "Tight across the shoulders, everything else was fine",
    "Perfect fit everywhere, definitely keeping these",
    "The chest was a bit snug but the length was great",
]

if __name__ == "__main__":
    print(f"\n{'text':<50} | {'direction':<16} | {'regions':<20} | ms")
    print("-" * 98)
    for sample in _SAMPLES:
        r = extract_fit_signal(sample)
        print(
            f"{sample[:48]:<50} | {r['direction']:<16} | "
            f"{str(r['regions']):<20} | {r['latency_ms']:.0f}"
        )
