# Graphics/3DGraphics — interactive exploration of the vessels scene.
# One surface per audience (the stack diagram's boundary):
#
#  - vessels-blend   Blender GUI on the cached realization — the ONLY
#                    surface showing the true volumetric glass; Shift+Z
#                    switches the viewport to interactive GPU path tracing
#                    (Cycles). The operator's demo rig; the customer's own
#                    surface is the web+AR model in any browser, which
#                    needs no target, no install, and no Blender.

.PHONY: vessels-blend
vessels-blend:
	$(MAKE) -C demos/vessels operator/scene.blend
	blender demos/vessels/operator/scene.blend &

# Which Cycles render devices the installed Blender actually sees —
# OPTIX rows prove the official build's GPU kernels are live (the
# distro build never shows them; that gap is why blender.org owns the
# install, see post/features/base/tools.pl).
.PHONY: blender-devices
blender-devices:
	blender -b --python-expr "import bpy; p = bpy.context.preferences.addons['cycles'].preferences; p.refresh_devices(); [print(d.type.ljust(8), d.name) for d in p.devices]"
