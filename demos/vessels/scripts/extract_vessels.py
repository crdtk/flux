"""Heuristic vessel chain: TOF-MRA NIfTI -> lumen mesh + centerline threads.

No learned models: Frangi vesselness (Hessian tubularity) -> hysteresis
threshold -> component filtering -> marching cubes; skeleton walk ->
spline-smoothed polylines ("flow threads"). Deterministic, explainable,
tunable — the prototype tier. All geometry in millimetres, voxel-spacing
frame (affine rotation ignored consistently for mesh and threads alike).

usage: extract_vessels.py <mra.nii.gz> <workdir>
"""
import json
import sys
from pathlib import Path

import nibabel as nib
import numpy as np
import trimesh
from scipy import ndimage
from scipy.interpolate import splev, splprep
from skimage.filters import apply_hysteresis_threshold, frangi
from skimage.measure import marching_cubes
from skimage.morphology import skeletonize

import os
# VESSEL_POLARITY=dark finds flow VOIDS (dark tubes on T1/T2 — the only
# vessel signal in a scan without TOF-MRA; illustrative tier, not CFD-grade)
BLACK_RIDGES = os.environ.get("VESSEL_POLARITY", "bright") == "dark"
MIN_COMPONENT_VOX = 1200     # drop specks below this many voxels
MIN_THREAD_MM = 12.0        # drop skeleton paths shorter than this
MAX_THREADS = 60            # keep the longest N threads
SIGMAS_MM = (0.6, 0.9, 1.3, 1.9, 2.7)  # vessel radii of interest


def main(mra_path: str, workdir: str) -> None:
    out = Path(workdir)
    out.mkdir(parents=True, exist_ok=True)

    img = nib.load(mra_path)
    spacing = np.asarray(img.header.get_zooms()[:3], dtype=np.float64)
    data = np.asarray(img.dataobj, dtype=np.float32)
    if data.ndim == 4:
        data = data[..., 0]
    p99 = np.percentile(data, 99.5)
    data = np.clip(data / max(p99, 1e-6), 0, 1)
    print(f"volume {data.shape}, spacing {spacing} mm")

    # Frangi wants sigmas in voxels; convert from mm using in-plane spacing.
    sigmas_vox = [s / float(np.min(spacing)) for s in SIGMAS_MM]
    ves = frangi(data, sigmas=sigmas_vox, black_ridges=BLACK_RIDGES).astype(np.float32)
    hi = float(np.percentile(ves, 99.7))
    mask = apply_hysteresis_threshold(ves, 0.2 * hi, hi)

    labels, n = ndimage.label(mask, structure=np.ones((3, 3, 3)))
    sizes = ndimage.sum_labels(np.ones_like(labels), labels, range(1, n + 1))
    keep = {i + 1 for i, s in enumerate(sizes) if s >= MIN_COMPONENT_VOX}
    mask = np.isin(labels, list(keep))
    mask = ndimage.binary_closing(mask, structure=np.ones((3, 3, 3)))
    print(f"vesselness hi={hi:.4g}; {n} components -> {len(keep)} kept; "
          f"{int(mask.sum())} voxels")

    nib.save(nib.Nifti1Image(ves, img.affine), out / "vesselness.nii.gz")

    verts, faces, _, _ = marching_cubes(mask.astype(np.float32), 0.5,
                                        spacing=tuple(spacing))
    mesh = trimesh.Trimesh(vertices=verts, faces=faces, process=True)
    parts = sorted(mesh.split(only_watertight=False),
                   key=lambda m: len(m.faces), reverse=True)[:8]
    mesh = trimesh.util.concatenate(parts)
    trimesh.smoothing.filter_taubin(mesh, lamb=0.5, nu=-0.53, iterations=10)
    mesh.export(out / "vessels.ply")
    print(f"mesh: {len(mesh.vertices)} verts, {len(mesh.faces)} faces, "
          f"extent {mesh.extents.round(1)} mm")

    # Skeleton -> threads: walk from each leaf along degree-2 voxels.
    skel = skeletonize(mask)
    vox = {tuple(v) for v in np.argwhere(skel)}
    offs = [(i, j, k) for i in (-1, 0, 1) for j in (-1, 0, 1)
            for k in (-1, 0, 1) if (i, j, k) != (0, 0, 0)]
    nbrs = {v: [w for w in ((v[0] + o[0], v[1] + o[1], v[2] + o[2])
                            for o in offs) if w in vox] for v in vox}
    leaves = [v for v, ns in nbrs.items() if len(ns) == 1]

    threads, visited = [], set()
    for leaf in leaves:
        if leaf in visited:
            continue
        path, prev, cur = [leaf], None, leaf
        while True:
            visited.add(cur)
            nxt = [w for w in nbrs[cur] if w != prev]
            if len(nxt) != 1:
                break
            prev, cur = cur, nxt[0]
            path.append(cur)
            if cur in visited:
                break
        pts = np.asarray(path, dtype=np.float64) * spacing
        seg = np.linalg.norm(np.diff(pts, axis=0), axis=1).sum()
        if seg >= MIN_THREAD_MM and len(pts) >= 8:
            try:
                tck, _ = splprep(pts.T, s=len(pts) * 0.8)
                u = np.linspace(0, 1, max(2 * len(pts), 24))
                pts = np.asarray(splev(u, tck)).T
            except Exception:
                pass
            threads.append((seg, pts))
    threads.sort(key=lambda t: t[0], reverse=True)
    threads = threads[:MAX_THREADS]
    total = sum(t[0] for t in threads)
    print(f"threads: {len(threads)} kept of {len(leaves)} leaves, "
          f"{total:.0f} mm total")

    with open(out / "flow.json", "w") as f:
        json.dump({"units": "mm",
                   "threads": [t[1].round(3).tolist() for t in threads]}, f)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
