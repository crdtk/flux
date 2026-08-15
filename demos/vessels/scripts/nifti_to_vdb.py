"""NIfTI -> OpenVDB via Blender's bundled Python (volume-context tier).

Blender >=3.5 ships pyopenvdb inside its own interpreter — the PyPI wheel
situation never matters. Runs headless under the same binary that later
renders the volume, so writer and reader can never disagree on VDB version.
No nibabel in Blender's Python: the fixed 348-byte NIfTI-1 header is parsed
directly (dims, datatype, pixdim, vox_offset, scaling — all this needs).
Degrades to a SKIP if pyopenvdb is somehow absent (IV: warn, continue).

usage: blender -b --python nifti_to_vdb.py -- <field.nii.gz> <out.vdb>
"""
import gzip
import struct
import sys

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, DST = argv[0], argv[1]

# OpenVDB v11+ (Blender 5) names the binding "openvdb"; older ships "pyopenvdb"
try:
    import openvdb as vdb
except ImportError:
    try:
        import pyopenvdb as vdb
    except ImportError:
        print(">>> SKIP: this Blender lacks OpenVDB Python bindings; VDB "
              "context layer deferred — mesh+threads chain unaffected")
        sys.exit(0)

import numpy as np

NII_DTYPES = {2: np.uint8, 4: np.int16, 8: np.int32, 16: np.float32,
              64: np.float64, 256: np.int8, 512: np.uint16, 768: np.uint32}

opener = gzip.open if SRC.endswith(".gz") else open
with opener(SRC, "rb") as f:
    raw = f.read()
ndim = struct.unpack_from("<h", raw, 40)[0]
dims = struct.unpack_from("<3h", raw, 42)  # spatial dims only
dtype_code = struct.unpack_from("<h", raw, 70)[0]
pixdim = struct.unpack_from("<3f", raw, 80)  # pixdim[1:4] = mm spacing
vox_offset = int(struct.unpack_from("<f", raw, 108)[0])
scl_slope, scl_inter = struct.unpack_from("<2f", raw, 112)
if struct.unpack_from("<2s", raw, 344)[0] not in (b"n+", b"ni"):
    sys.exit(f"not a NIfTI-1 file: {SRC}")

n = dims[0] * dims[1] * dims[2]
data = np.frombuffer(raw, NII_DTYPES[dtype_code], n, vox_offset)
data = data.reshape(dims, order="F").astype(np.float32)
if scl_slope not in (0.0, 1.0):
    data = data * scl_slope + scl_inter
data = np.ascontiguousarray(data / max(float(data.max()), 1e-6))
print(f"volume {dims}, spacing {tuple(round(p, 2) for p in pixdim)} mm, "
      f"dtype code {dtype_code}")

grid = vdb.FloatGrid()
grid.copyFromArray(data, tolerance=0.001)
# scene truth is mm (metersPerUnit=0.001): voxel size in mm matches the meshes
grid.transform = vdb.createLinearTransform(voxelSize=float(min(pixdim)))
grid.name = "density"
grid.gridClass = vdb.GridClass.FOG_VOLUME
vdb.write(DST, grids=[grid])
print(f">>> wrote {DST}")
