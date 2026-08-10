"""USD scene -> GLB for the web/AR tier (<model-viewer>, three.js).

usage: blender -b --python export_glb.py -- scene.usda out.glb
"""
import sys

import bpy

argv = sys.argv[sys.argv.index("--") + 1:]
USD, OUT = argv[0], argv[1]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.usd_import(filepath=USD)
# curves don't survive glTF; convert threads to thin meshes first
for o in list(bpy.data.objects):
    if o.type == "CURVE":
        o.data.bevel_depth = 0.00035
        bpy.context.view_layer.objects.active = o
        o.select_set(True)
        bpy.ops.object.convert(target="MESH")
        o.select_set(False)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB")
print(f">>> exported {OUT}")
