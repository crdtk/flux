"""Cycles realization of the void look: luminous threads in glass on black.

Imports the USD scene (geometry, lights, camera), then materializes the
glaskoerper look from materials.json — Cycles' volume-absorption glass
cannot be expressed in UsdPreviewSurface, so the USD carries the params
and this script builds the node graphs.

usage: blender -b --python render_void.py -- scene.usda materials.json out.png [samples] [light_scale]
"""
import json
import sys

import bpy

argv = sys.argv[sys.argv.index("--") + 1:]
USD, MATS, OUT = argv[0], argv[1], argv[2]
SAMPLES = int(argv[3]) if len(argv) > 3 else 128
LIGHT_SCALE = float(argv[4]) if len(argv) > 4 else 1.0

looks = json.loads(open(MATS).read())

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
bpy.ops.wm.usd_import(filepath=USD)

# ---- world: near-black deep-space blue --------------------------------
w = bpy.data.worlds.new("Void")
w.use_nodes = True
bg = w.node_tree.nodes["Background"]
bg.inputs["Color"].default_value = (0.004, 0.006, 0.014, 1)
bg.inputs["Strength"].default_value = 1.0
sc.world = w

# ---- camera -----------------------------------------------------------
for o in bpy.data.objects:
    if o.type == "CAMERA":
        sc.camera = o
        break

# ---- lights: imported from USD; allow a global trim -------------------
for o in bpy.data.objects:
    if o.type == "LIGHT":
        o.data.energy *= LIGHT_SCALE


def _sin(node, name, val):
    try:
        node.inputs[name].default_value = val
    except (KeyError, TypeError):
        pass


# ---- glass vessels ----------------------------------------------------
gv = looks["Vessels"]
mat = bpy.data.materials.new("VesselGlass")
mat.use_nodes = True
nt = mat.node_tree
b = nt.nodes.get("Principled BSDF")
_sin(b, "Base Color", (1, 1, 1, 1))
_sin(b, "Transmission Weight", 1.0)
_sin(b, "Roughness", gv["roughness"])
_sin(b, "IOR", gv["ior"])
vol = nt.nodes.new("ShaderNodeVolumeAbsorption")
vol.inputs["Color"].default_value = (*gv["tint"], 1)
# imported scene is metric: USD mm arrive as 0.001 m units, so per-mm -> per-m
vol.inputs["Density"].default_value = gv["absorption_per_mm"] * 1000.0
nt.links.new(vol.outputs["Volume"], nt.nodes["Material Output"].inputs["Volume"])

# ---- luminous threads -------------------------------------------------
gf = looks["Flow"]
fmat = bpy.data.materials.new("FlowEmission")
fmat.use_nodes = True
fnt = fmat.node_tree
for n in list(fnt.nodes):
    if n.type not in ("OUTPUT_MATERIAL",):
        fnt.nodes.remove(n)
em = fnt.nodes.new("ShaderNodeEmission")
em.inputs["Color"].default_value = (*gf["emission_color"], 1)
em.inputs["Strength"].default_value = gf["emission_strength"]
fnt.links.new(em.outputs["Emission"], fnt.nodes["Material Output"].inputs["Surface"])

for o in bpy.data.objects:
    if o.type == "MESH" and "Vessels" in o.name:
        o.data.materials.clear()
        o.data.materials.append(mat)
    elif o.type in ("CURVE", "CURVES") and ("Threads" in o.name or "Flow" in o.name):
        o.data.materials.clear() if o.data.materials else None
        o.data.materials.append(fmat)
        if o.type == "CURVE":
            o.data.bevel_depth = gf["width_mm"] / 1000.0
        elif o.type == "CURVES":
            # hair-curves need a point radius attribute or they render as nothing
            r = gf["width_mm"] / 2000.0
            attr = o.data.attributes.get("radius") or o.data.attributes.new(
                "radius", "FLOAT", "POINT")
            attr.data.foreach_set("value", [r] * len(attr.data))

# ---- Cycles on GPU ----------------------------------------------------
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
sc.cycles.samples = SAMPLES
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
sc.render.filepath = OUT

# ---- compositor: fog-glow glare makes the threads luminous ------------
# Blender 5: the scene compositor is a node-group datablock, not Scene.node_tree
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

bpy.ops.wm.save_as_mainfile(filepath=OUT.rsplit("/", 1)[0] + "/scene.blend")
bpy.ops.render.render(write_still=True)
print(f">>> rendered {OUT} at {SAMPLES} samples, light_scale {LIGHT_SCALE}")
