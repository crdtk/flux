"""Extraction QC — ONE output: the decision mask over the source volume,
three orthogonal views. Plots work/mask.nii.gz ITSELF (the actual
decision), never a re-derived threshold — QC cannot disagree with truth.

usage: overlay_qc.py <source.nii.gz> <mask.nii.gz> <out.png>
"""
import sys

from nilearn import plotting

SRC, MASK, OUT = sys.argv[1], sys.argv[2], sys.argv[3]

disp = plotting.plot_roi(MASK, bg_img=SRC, display_mode="ortho",
                         cmap="autumn", alpha=0.8, dim=-0.5,
                         title="extraction decision vs source")
disp.savefig(OUT, dpi=200)
print(f">>> wrote {OUT}")
