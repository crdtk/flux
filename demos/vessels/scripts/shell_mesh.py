"""Brain shell — ONE output: the translucent outer form (dark mode).

Prefers the learned brain label; falls back to eroding the c3d head mask.
Downsampled marching cubes + hard Taubin smoothing — a glass form, not a
surface reconstruction.

usage: shell_mesh.py <head.nii.gz> <brain.ply>
       (prefers seg/brain.nii.gz beside the head mask when present)
"""
import sys
from pathlib import Path

import nibabel as nib
import numpy as np
import trimesh
from scipy import ndimage
from skimage.measure import marching_cubes

SRC, DST = sys.argv[1], sys.argv[2]
img = nib.load(SRC)
spacing = np.asarray(img.header.get_zooms()[:3], dtype=np.float64)

seg = Path(SRC).parent / "seg" / "brain.nii.gz"
if seg.exists():
    brain = np.asarray(nib.load(seg).dataobj) > 0
    print("shell source: learned brain (TotalSegmentator)")
else:
    head = np.asarray(img.dataobj) > 0
    erode_vox = np.maximum((8.0 / spacing).astype(int), 1)
    brain = ndimage.binary_erosion(head, np.ones(2 * erode_vox + 1))
    brain = ndimage.binary_fill_holes(
        ndimage.binary_dilation(brain, np.ones(erode_vox)))
    print("shell source: eroded head (heuristic)")

ds = ndimage.zoom(brain.astype(np.float32), 0.5, order=1)
verts, faces, _, _ = marching_cubes(ds, 0.5, spacing=tuple(spacing * 2))
shell = trimesh.Trimesh(vertices=verts, faces=faces, process=True)
shell = sorted(shell.split(only_watertight=False),
               key=lambda m: len(m.faces), reverse=True)[0]
trimesh.smoothing.filter_taubin(shell, lamb=0.5, nu=-0.53, iterations=30)
shell.export(DST)
print(f">>> {DST}: {len(shell.faces)} faces, extent {shell.extents.round(1)} mm")
