"""Flow threads — ONE output: spline-smoothed centerline polylines (mm).

Skeletonize the decision mask; skan decomposes the skeleton into branch
paths (junctions and loops handled); keep the longest, spline-smooth.

usage: flow_threads.py <mask.nii.gz> <flow.json>
"""
import json
import sys

import nibabel as nib
import numpy as np
from scipy.interpolate import splev, splprep
from skan import Skeleton
from skimage.morphology import skeletonize

MIN_THREAD_MM = 12.0
MAX_THREADS = 60

SRC, DST = sys.argv[1], sys.argv[2]
img = nib.load(SRC)
spacing = np.asarray(img.header.get_zooms()[:3], dtype=np.float64)
mask = np.asarray(img.dataobj) > 0

skel = skeletonize(mask)
sk = Skeleton(skel)
threads = []
for i in range(sk.n_paths):
    pts = sk.path_coordinates(i) * spacing
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
print(f"threads: {len(threads)} kept of {sk.n_paths} paths, "
      f"{sum(t[0] for t in threads):.0f} mm total")

with open(DST, "w") as f:
    json.dump({"units": "mm",
               "threads": [t[1].round(3).tolist() for t in threads]}, f)
print(f">>> wrote {DST}")
