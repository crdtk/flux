"""Customer GLB — ONE output, and Blender-free by design: nothing the
customer receives depends on Blender. trimesh assembles the lumen mesh,
shell, and thread tubes with PBR materials from looks.json and writes
binary glTF directly.

usage: export_glb.py <workdir> <looks.json> <vessels.glb>
"""
import json
import sys
from pathlib import Path

import numpy as np
import trimesh
from trimesh.visual.material import PBRMaterial

WORK, LOOKS, DST = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
looks = json.loads(open(LOOKS).read())


def pbr(name, base, rough, emissive=None):
    m = PBRMaterial(name=name, baseColorFactor=[*base, 1.0],
                    roughnessFactor=rough, metallicFactor=0.0)
    if emissive:
        m.emissiveFactor = emissive
    return m


scene = trimesh.Scene()

gv = looks["Vessels"]
vessels = trimesh.load(WORK / "vessels.ply", process=False)
vessels.visual = trimesh.visual.TextureVisuals(
    material=pbr("VesselGlass", gv["tint"], gv["roughness"]))
scene.add_geometry(vessels, node_name="Vessels")

shell_path = WORK / "brain.ply"
if shell_path.exists():
    gb = looks["Brain"]
    shell = trimesh.load(shell_path, process=False)
    shell.visual = trimesh.visual.TextureVisuals(
        material=pbr("BrainGlass", gb["tint"], gb["roughness"]))
    scene.add_geometry(shell, node_name="Brain")

# threads as thin tube meshes (glTF has no renderable curves)
gf = looks["Flow"]
fmat = pbr("FlowEmission", gf["emission_color"], 0.5,
           emissive=list(gf["emission_color"]))
r = gf["width_mm"] / 2.0
segs = []
for t in json.loads((WORK / "flow.json").read_text())["threads"]:
    pts = np.asarray(t)[::3]
    for a, b in zip(pts, pts[1:]):
        h = float(np.linalg.norm(b - a))
        if h < 1e-3:
            continue
        cyl = trimesh.creation.cylinder(radius=r, height=h, sections=6)
        cyl.apply_transform(trimesh.geometry.align_vectors([0, 0, 1],
                                                           (b - a) / h))
        cyl.apply_translation((a + b) / 2.0)
        segs.append(cyl)
threads = trimesh.util.concatenate(segs)
threads.visual = trimesh.visual.TextureVisuals(material=fmat)
scene.add_geometry(threads, node_name="Flow")

scene.export(DST)
print(f">>> wrote {DST} ({len(segs)} thread segments, Blender-free)")
