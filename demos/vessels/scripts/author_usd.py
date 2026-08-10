"""Author the layered OpenUSD scene — the diffable scene truth.

Layers (composition order strong->weak in scene.usda):
  look_void.usda  lights (hidden back panel + cool rims + faint dome) + camera
  flow.usda       skeleton threads as BasisCurves (the luminous flow)
  anatomy.usda    vessel lumen mesh, GLASS params as glaskoerper:* attributes

The same LOOKS dict is emitted twice from this one source: as USD custom
attributes (scene truth, renderer-agnostic) and as materials.json (the
Cycles realization sidecar render_void.py consumes). Units: millimetres.

usage: author_usd.py <workdir> <usddir>
"""
import json
import sys
from pathlib import Path

import numpy as np
import trimesh
from pxr import Gf, Sdf, Usd, UsdGeom, UsdLux, Vt

LOOKS = {
    "Vessels": {  # near-clear sapphire glass; the volume does the colour
        "tint": (0.60, 0.78, 1.00), "ior": 1.50,
        "absorption_per_mm": 0.28, "roughness": 0.015,
    },
    "Flow": {     # warm luminous threads against the cool glass
        "emission_color": (1.00, 0.52, 0.18), "emission_strength": 80.0,
        "width_mm": 1.1,
    },
}


def _set_glaskoerper(prim, table):
    for key, val in table.items():
        name = f"glaskoerper:{key}"
        if isinstance(val, tuple):
            a = prim.CreateAttribute(name, Sdf.ValueTypeNames.Color3f)
            a.Set(Gf.Vec3f(*val))
        else:
            prim.CreateAttribute(name, Sdf.ValueTypeNames.Float).Set(float(val))


def main(workdir: str, usddir: str) -> None:
    work, usd = Path(workdir), Path(usddir)
    usd.mkdir(parents=True, exist_ok=True)

    mesh = trimesh.load(work / "vessels.ply", process=False)
    lo, hi = mesh.bounds
    ctr = 0.5 * (lo + hi)
    size = float(np.max(hi - lo))

    # ---- anatomy.usda -------------------------------------------------
    st = Usd.Stage.CreateNew(str(usd / "anatomy.usda"))
    UsdGeom.SetStageUpAxis(st, UsdGeom.Tokens.z)
    UsdGeom.SetStageMetersPerUnit(st, 0.001)
    m = UsdGeom.Mesh.Define(st, "/Anatomy/Vessels")
    m.CreatePointsAttr(Vt.Vec3fArray.FromNumpy(mesh.vertices.astype(np.float32)))
    m.CreateFaceVertexCountsAttr(Vt.IntArray([3] * len(mesh.faces)))
    m.CreateFaceVertexIndicesAttr(Vt.IntArray.FromNumpy(mesh.faces.ravel().astype(np.int32)))
    m.CreateExtentAttr(Vt.Vec3fArray([Gf.Vec3f(*[float(v) for v in lo]),
                                      Gf.Vec3f(*[float(v) for v in hi])]))
    m.CreateSubdivisionSchemeAttr(UsdGeom.Tokens.none)
    _set_glaskoerper(m.GetPrim(), LOOKS["Vessels"])
    st.SetDefaultPrim(st.GetPrimAtPath("/Anatomy"))
    st.GetRootLayer().Save()

    # ---- flow.usda ----------------------------------------------------
    st = Usd.Stage.CreateNew(str(usd / "flow.usda"))
    UsdGeom.SetStageUpAxis(st, UsdGeom.Tokens.z)
    UsdGeom.SetStageMetersPerUnit(st, 0.001)
    threads = json.loads((work / "flow.json").read_text())["threads"]
    counts, pts = [], []
    for t in threads:
        counts.append(len(t))
        pts.extend(t)
    c = UsdGeom.BasisCurves.Define(st, "/Flow/Threads")
    c.CreateTypeAttr(UsdGeom.Tokens.linear)
    c.CreateCurveVertexCountsAttr(Vt.IntArray(counts))
    c.CreatePointsAttr(Vt.Vec3fArray.FromNumpy(np.asarray(pts, dtype=np.float32)))
    c.CreateWidthsAttr(Vt.FloatArray([LOOKS["Flow"]["width_mm"]]))
    c.SetWidthsInterpolation(UsdGeom.Tokens.constant)
    _set_glaskoerper(c.GetPrim(), LOOKS["Flow"])
    st.SetDefaultPrim(st.GetPrimAtPath("/Flow"))
    st.GetRootLayer().Save()

    # ---- look_void.usda: void recipe — light THROUGH, background black
    st = Usd.Stage.CreateNew(str(usd / "look_void.usda"))
    UsdGeom.SetStageUpAxis(st, UsdGeom.Tokens.z)
    UsdGeom.SetStageMetersPerUnit(st, 0.001)

    def rect(path, pos, rot_xyz, w, h, intensity, color):
        light = UsdLux.RectLight.Define(st, path)
        light.CreateWidthAttr(w)
        light.CreateHeightAttr(h)
        light.CreateIntensityAttr(intensity)
        light.CreateColorAttr(Gf.Vec3f(*color))
        x = UsdGeom.Xformable(light)
        x.AddTranslateOp().Set(Gf.Vec3d(*pos))
        x.AddRotateXYZOp().Set(Gf.Vec3f(*rot_xyz))

    s = size
    # hidden bright panel BEHIND the vessels (+Y); camera sits at -Y, so the
    # panel back-lights the glass without appearing in frame
    rect("/Lights/BackPanel", (ctr[0], ctr[1] + 1.1 * s, ctr[2]),
         (90, 0, 180), 1.6 * s, 1.6 * s, 7.5, (1.0, 0.82, 0.58))
    rect("/Lights/RimL", (ctr[0] - 1.3 * s, ctr[1] + 0.4 * s, ctr[2] + 0.3 * s),
         (90, 0, 240), 0.25 * s, 1.4 * s, 1.6, (0.70, 0.82, 1.0))
    rect("/Lights/RimR", (ctr[0] + 1.3 * s, ctr[1] + 0.4 * s, ctr[2] + 0.3 * s),
         (90, 0, 120), 0.25 * s, 1.4 * s, 1.6, (0.70, 0.82, 1.0))
    dome = UsdLux.DomeLight.Define(st, "/Lights/Dome")
    dome.CreateIntensityAttr(0.02)
    dome.CreateColorAttr(Gf.Vec3f(0.05, 0.07, 0.12))

    cam = UsdGeom.Camera.Define(st, "/Camera/main")
    cam.CreateFocalLengthAttr(65.0)
    cam.CreateClippingRangeAttr(Gf.Vec2f(1.0, 20000.0))
    eye = Gf.Vec3d(float(ctr[0] - 0.25 * s), float(ctr[1] - 4.3 * s),
                   float(ctr[2] + 0.45 * s))
    view = Gf.Matrix4d().SetLookAt(eye, Gf.Vec3d(*[float(v) for v in ctr]),
                                   Gf.Vec3d(0, 0, 1))
    UsdGeom.Xformable(cam).AddTransformOp().Set(view.GetInverse())
    st.GetRootLayer().Save()

    # ---- scene.usda: the composition ---------------------------------
    root = Sdf.Layer.CreateNew(str(usd / "scene.usda"))
    root.subLayerPaths = ["./look_void.usda", "./flow.usda", "./anatomy.usda"]
    root.Save()

    (usd / "materials.json").write_text(json.dumps(LOOKS, indent=2))
    print(f"authored {usd}/scene.usda (+3 layers, materials.json); "
          f"{len(threads)} threads, extent {size:.0f} mm")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
