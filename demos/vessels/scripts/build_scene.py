"""Materialize the void look as a Cycles .blend — ONE output.

Geometry straight from the work/ files (PLY meshes + flow.json threads),
looks from looks.json, lights and camera computed from the scene bounds:
hidden warm back panel behind the subject, cool rims, near-black world.
Scene is built in metres (mm inputs / 1000). The .blend is the cached
realization: the Blender CLI renders it without re-running this script.

usage: blender -b --python build_scene.py -- workdir looks.json out.blend [light_scale]
"""
import json
import sys
from pathlib import Path

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
WORK, LOOKS, OUT = Path(argv[0]), argv[1], argv[2]
LIGHT_SCALE = float(argv[3]) if len(argv) > 3 else 1.0
MM = 0.001

looks = json.loads(open(LOOKS).read())
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene


def _sin(node, name, val):
    try:
        node.inputs[name].default_value = val
    except (KeyError, TypeError):
        pass


def glass_material(name, gv):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    b = nt.nodes.get("Principled BSDF")
    _sin(b, "Base Color", (1, 1, 1, 1))
    _sin(b, "Transmission Weight", 1.0)
    _sin(b, "Roughness", gv["roughness"])
    _sin(b, "IOR", gv["ior"])
    vol = nt.nodes.new("ShaderNodeVolumeAbsorption")
    vol.inputs["Color"].default_value = (*gv["tint"], 1)
    vol.inputs["Density"].default_value = gv["absorption_per_mm"] / MM
    nt.links.new(vol.outputs["Volume"],
                 nt.nodes["Material Output"].inputs["Volume"])
    return mat


def import_ply(path, name, mat):
    bpy.ops.wm.ply_import(filepath=str(path))
    o = bpy.context.active_object
    o.name = name
    o.scale = (MM, MM, MM)
    o.data.materials.clear()
    o.data.materials.append(mat)
    return o


vessels = import_ply(WORK / "vessels.ply", "Vessels",
                     glass_material("VesselGlass", looks["Vessels"]))
shell_path = WORK / "brain.ply"
if shell_path.exists():
    import_ply(shell_path, "Brain", glass_material("BrainGlass", looks["Brain"]))

# threads: one CURVE object, polyline splines, emissive bevel tubes
gf = looks["Flow"]
cd = bpy.data.curves.new("Threads", "CURVE")
cd.dimensions = "3D"
cd.bevel_depth = gf["width_mm"] * MM / 2.0
for t in json.loads((WORK / "flow.json").read_text())["threads"]:
    sp = cd.splines.new("POLY")
    sp.points.add(len(t) - 1)
    for p, (x, y, z) in zip(sp.points, t):
        p.co = (x * MM, y * MM, z * MM, 1)
fmat = bpy.data.materials.new("FlowEmission")
fmat.use_nodes = True
fnt = fmat.node_tree
for n in list(fnt.nodes):
    if n.type != "OUTPUT_MATERIAL":
        fnt.nodes.remove(n)
em = fnt.nodes.new("ShaderNodeEmission")
em.inputs["Color"].default_value = (*gf["emission_color"], 1)
em.inputs["Strength"].default_value = gf["emission_strength"]
fnt.links.new(em.outputs["Emission"], fnt.nodes["Material Output"].inputs["Surface"])
cd.materials.append(fmat)
threads = bpy.data.objects.new("Flow", cd)
sc.collection.objects.link(threads)

# bounds of the outermost form (metres). The scale assigned above is not
# in matrix_world until the depsgraph evaluates — update first, or the
# bounds come back in millimetres and the camera flies 600 "metres" out.
bpy.context.view_layer.update()
ref = bpy.data.objects.get("Brain") or vessels
bb = [ref.matrix_world @ Vector(c) for c in ref.bound_box]
lo = Vector((min(v.x for v in bb), min(v.y for v in bb), min(v.z for v in bb)))
hi = Vector((max(v.x for v in bb), max(v.y for v in bb), max(v.z for v in bb)))
ctr, s = (lo + hi) / 2, max(hi - lo)


def aim(obj, target):
    d = target - obj.location
    obj.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()


def area_light(name, loc, size_xy, energy, color):
    ld = bpy.data.lights.new(name, "AREA")
    ld.shape = "RECTANGLE"
    ld.size, ld.size_y = size_xy
    ld.energy = energy * LIGHT_SCALE
    ld.color = color
    o = bpy.data.objects.new(name, ld)
    o.location = loc
    sc.collection.objects.link(o)
    aim(o, ctr)
    return o


# hidden warm panel BEHIND the subject (+Y); camera sits at -Y.
# Energies/colors live in looks.json — lighting IS look, and a look edit
# must invalidate the blend (file-tracked), which a CLI knob cannot.
gl = looks["Lights"]
area_light("BackPanel", ctr + Vector((0, 1.1 * s, 0)),
           (1.6 * s, 1.6 * s), gl["back_panel_w"], gl["back_panel_color"])
area_light("RimL", ctr + Vector((-1.3 * s, 0.4 * s, 0.3 * s)),
           (0.25 * s, 1.4 * s), gl["rim_w"], gl["rim_color"])
area_light("RimR", ctr + Vector((1.3 * s, 0.4 * s, 0.3 * s)),
           (0.25 * s, 1.4 * s), gl["rim_w"], gl["rim_color"])

cam = bpy.data.cameras.new("main")
cam.lens = 65.0
cam.clip_start = 0.001
cam.clip_end = 100.0
co = bpy.data.objects.new("main", cam)
co.location = ctr + Vector((-0.25 * s, -4.3 * s, 0.45 * s))
sc.collection.objects.link(co)
aim(co, ctr)
sc.camera = co

w = bpy.data.worlds.new("Void")
w.use_nodes = True
bg = w.node_tree.nodes["Background"]
bg.inputs["Color"].default_value = (0.004, 0.006, 0.014, 1)
sc.world = w

sc.render.engine = "CYCLES"
prefs = bpy.context.preferences.addons["cycles"].preferences
for dev_type in ("OPTIX", "CUDA"):
    try:
        prefs.compute_device_type = dev_type
        prefs.get_devices()
        for d in prefs.devices:
            d.use = d.type != "CPU"
        sc.cycles.device = "GPU"
        break
    except Exception:
        continue
sc.cycles.samples = 160
sc.cycles.use_denoising = True
sc.cycles.volume_bounces = 2
sc.cycles.transmission_bounces = 12
sc.cycles.transparent_max_bounces = 16
sc.view_settings.view_transform = "AgX"
try:
    sc.view_settings.look = "AgX - Medium High Contrast"
except Exception:
    pass
sc.render.resolution_x = sc.render.resolution_y = 1024
sc.render.image_settings.file_format = "PNG"

# Blender 5: the scene compositor is a node-group datablock
ct = bpy.data.node_groups.new("VoidGlare", "CompositorNodeTree")
sc.compositing_node_group = ct
sc.use_nodes = True
rl = ct.nodes.new("CompositorNodeRLayers")
glare = ct.nodes.new("CompositorNodeGlare")
for val in ("Fog Glow", "FOG_GLOW"):
    try:
        glare.inputs["Type"].default_value = val
        break
    except TypeError:
        continue
_sin(glare, "Threshold", 1.0)
_sin(glare, "Size", 8)
_sin(glare, "Strength", 1.0)
out = ct.nodes.new("NodeGroupOutput")
ct.interface.new_socket("Image", in_out="OUTPUT", socket_type="NodeSocketColor")
ct.links.new(rl.outputs["Image"], glare.inputs["Image"])
ct.links.new(glare.outputs["Image"], out.inputs["Image"])

bpy.ops.wm.save_as_mainfile(filepath=str(Path(OUT).resolve()))
print(f">>> built {OUT} (light_scale {LIGHT_SCALE})")
