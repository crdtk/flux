"""Best-effort NIfTI -> OpenVDB (volume-context tier: organs as nebulae).

Degrades to a SKIP message when pyopenvdb is unavailable — the wheel
situation is spotty and the mesh/threads chain must not fail on it.

usage: nifti_to_vdb.py <field.nii.gz> <out.vdb>
"""
import sys

try:
    import pyopenvdb as vdb
except ImportError:
    print(">>> SKIP: pyopenvdb not installed (wheels are platform-spotty); "
          "VDB context layer deferred — mesh+threads chain unaffected")
    sys.exit(0)

import nibabel as nib
import numpy as np

src, dst = sys.argv[1], sys.argv[2]
img = nib.load(src)
data = np.asarray(img.dataobj, dtype=np.float32)
data = data / max(float(data.max()), 1e-6)
grid = vdb.FloatGrid()
grid.copyFromArray(data, tolerance=0.001)
sp = img.header.get_zooms()[:3]
grid.transform = vdb.createLinearTransform(voxelSize=float(min(sp)))
grid.name = "density"
vdb.write(dst, grids=[grid])
print(f">>> wrote {dst}")
