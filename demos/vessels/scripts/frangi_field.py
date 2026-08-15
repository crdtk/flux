"""Frangi tube-likelihood field — ONE output: the vesselness volume.

VESSEL_POLARITY=dark finds flow VOIDS (dark tubes on T1/T2 — the only
vessel signal in a scan without TOF-MRA); bright is the TOF default.
cuCIM GPU when the venv has it (Makefile installs it on Pascal+ only),
else scikit-image CPU — import presence IS the capability gate.

usage: frangi_field.py <mra.nii.gz> <vesselness.nii.gz>
"""
import os
import sys

import nibabel as nib
import numpy as np
from skimage.filters import frangi

try:
    import cupy as cp
    from cucim.skimage.filters import frangi as frangi_gpu
except ImportError:
    frangi_gpu = None

BLACK_RIDGES = os.environ.get("VESSEL_POLARITY", "bright") == "dark"
# dark mode biases to the large named vessels (>=~3mm lumen); bright/TOF
# keeps the fine-radius bank
SIGMAS_MM = ((1.2, 1.8, 2.7, 4.0) if BLACK_RIDGES
             else (0.6, 0.9, 1.3, 1.9, 2.7))

SRC, DST = sys.argv[1], sys.argv[2]
img = nib.load(SRC)
spacing = np.asarray(img.header.get_zooms()[:3], dtype=np.float64)
data = np.asarray(img.dataobj, dtype=np.float32)
if data.ndim == 4:
    data = data[..., 0]
p99 = np.percentile(data, 99.5)
data = np.clip(data / max(p99, 1e-6), 0, 1)
print(f"volume {data.shape}, spacing {spacing} mm, "
      f"polarity {'dark' if BLACK_RIDGES else 'bright'}")

sigmas_vox = [s / float(np.min(spacing)) for s in SIGMAS_MM]
if frangi_gpu is not None:
    ves = cp.asnumpy(frangi_gpu(cp.asarray(data), sigmas=sigmas_vox,
                                black_ridges=BLACK_RIDGES)).astype(np.float32)
    print("frangi: GPU (cuCIM)")
else:
    ves = frangi(data, sigmas=sigmas_vox,
                 black_ridges=BLACK_RIDGES).astype(np.float32)
nib.save(nib.Nifti1Image(ves, img.affine), DST)
print(f">>> wrote {DST}")
