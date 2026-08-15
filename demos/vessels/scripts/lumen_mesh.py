"""Lumen surface — ONE output: the vessel mesh in millimetres.

Marching cubes on the decision mask, keep the 8 largest parts, Taubin
smooth (volume-preserving).

usage: lumen_mesh.py <mask.nii.gz> <vessels.ply>
"""
import sys

import nibabel as nib
import numpy as np
import trimesh
from skimage.measure import marching_cubes

SRC, DST = sys.argv[1], sys.argv[2]
img = nib.load(SRC)
spacing = np.asarray(img.header.get_zooms()[:3], dtype=np.float64)
mask = np.asarray(img.dataobj).astype(np.float32)

verts, faces, _, _ = marching_cubes(mask, 0.5, spacing=tuple(spacing))
mesh = trimesh.Trimesh(vertices=verts, faces=faces, process=True)
parts = sorted(mesh.split(only_watertight=False),
               key=lambda m: len(m.faces), reverse=True)[:8]
mesh = trimesh.util.concatenate(parts)
trimesh.smoothing.filter_taubin(mesh, lamb=0.5, nu=-0.53, iterations=10)
mesh.export(DST)
print(f">>> {DST}: {len(mesh.vertices)} verts, {len(mesh.faces)} faces, "
      f"extent {mesh.extents.round(1)} mm")
