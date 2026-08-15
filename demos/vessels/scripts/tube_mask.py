"""The extraction DECISION — ONE output: the binary tube mask.

Hysteresis threshold on the vesselness field, then (dark mode) the
anatomical gate: keep tubes that are deep below the brain surface
(carotid siphons, basilar, MCA) or in the thin dural band at the skull
base (transverse/sigmoid sinuses); superficial sulci are culled. The
learned brain mask is preferred over the eroded-head approximation when
present — file presence IS the tier signal, no re-sensing (III).

usage: tube_mask.py <vesselness.nii.gz> <mask.nii.gz>
       (reads head.nii.gz / seg/brain.nii.gz beside the output in dark mode)
"""
import os
import sys
from pathlib import Path

import nibabel as nib
import numpy as np
from scipy import ndimage
from skimage.filters import apply_hysteresis_threshold

BLACK_RIDGES = os.environ.get("VESSEL_POLARITY", "bright") == "dark"
MIN_COMPONENT_VOX = 1200
DEEP_MM = 5.0
BAND_MM = 3.0
BASE_FRACTION = 0.40

SRC, DST = sys.argv[1], sys.argv[2]
work = Path(DST).parent
img = nib.load(SRC)
spacing = np.asarray(img.header.get_zooms()[:3], dtype=np.float64)
ves = np.asarray(img.dataobj, dtype=np.float32)

hi = float(np.percentile(ves, 99.7))
mask = apply_hysteresis_threshold(ves, 0.2 * hi, hi)

if BLACK_RIDGES:
    head = np.asarray(nib.load(work / "head.nii.gz").dataobj) > 0
    seg = work / "seg" / "brain.nii.gz"
    if seg.exists():
        brain = np.asarray(nib.load(seg).dataobj) > 0
        print("brain mask: learned (TotalSegmentator)")
    else:
        erode_vox = np.maximum((8.0 / spacing).astype(int), 1)
        brain = ndimage.binary_erosion(head, np.ones(2 * erode_vox + 1))
        brain = ndimage.binary_fill_holes(
            ndimage.binary_dilation(brain, np.ones(erode_vox)))
    depth = ndimage.distance_transform_edt(brain, sampling=spacing)
    # inferior direction from the NIfTI affine — never assume voxel layout
    axcodes = nib.orientations.aff2axcodes(img.affine)
    s_axis = [i for i, c in enumerate(axcodes) if c in "SI"][0]
    sup = np.indices(brain.shape)[s_axis].astype(np.float32)
    if axcodes[s_axis] == "I":
        sup = sup.max() - sup
    base_cut = np.percentile(sup[brain], 100 * BASE_FRACTION)
    inferior = sup <= base_cut
    gate = (depth >= DEEP_MM) | (brain & (depth <= BAND_MM) & inferior)
    before = int(mask.sum())
    mask &= gate
    print(f"anatomical gate: {before} -> {int(mask.sum())} voxels "
          f"(deep>={DEEP_MM}mm or basal band<={BAND_MM}mm)")

labels, n = ndimage.label(mask, structure=np.ones((3, 3, 3)))
sizes = ndimage.sum_labels(np.ones_like(labels), labels, range(1, n + 1))
keep = {i + 1 for i, s in enumerate(sizes) if s >= MIN_COMPONENT_VOX}
mask = np.isin(labels, list(keep))
mask = ndimage.binary_closing(mask, structure=np.ones((3, 3, 3)))
print(f"vesselness hi={hi:.4g}; {n} components -> {len(keep)} kept; "
      f"{int(mask.sum())} voxels")

nib.save(nib.Nifti1Image(mask.astype(np.uint8), img.affine), DST)
print(f">>> wrote {DST}")
