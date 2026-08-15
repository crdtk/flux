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
