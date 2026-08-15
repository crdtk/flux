MAKEFLAGS += --no-builtin-rules
.SUFFIXES:
# a failed recipe must not leave a half-written target that satisfies the
# next run (I: a stale report is worse than none)
.DELETE_ON_ERROR:

# vessels — heuristic vessel extraction into two audience databases.
# Data: OpenNeuro ds003949 (Di Noto et al.), healthy control sub-000,
# N4-corrected skull-stripped angio — direct S3, no auth. A personal scan
# slots in via MRA=path (VESSEL_POLARITY=dark for T1 flow voids,
# MASKS=learned for the TotalSegmentator brain).
#
# SRP chain — every script has ONE output; files are the seams, Make is
# the orchestrator (stages cache and parallelize under -j):
#   NIfTI -> frangi field -> decision mask -> {lumen, shell, threads}
#   customer/  = the web+AR model — the single artifact that leaves the
#                shop, built Blender-free (trimesh + gltf-transform)
#   operator/  = hero still, QC overlay, interactive .blend — team-only
# looks.json is the one look source, read by build_scene and export alike.

.PHONY: all customer internal
all: customer internal
customer: customer/vessels.opt.glb
internal: operator/void.png operator/heuristics-vessels-garbage.png

USER_HOME ?= $(shell getent passwd $${SUDO_USER:-$$(whoami)} | cut -d: -f6)
UV        ?= $(USER_HOME)/.local/bin/uv
VENV      := $(CURDIR)/.venv
PY        := $(VENV)/bin/python3
VENV_PIP   = VIRTUAL_ENV=$(VENV) $(UV) pip install
BLENDER   ?= /usr/local/bin/blender

MRA_URL := https://s3.amazonaws.com/openneuro.org/ds003949/derivatives/N4_bias_field_corrected/sub-000/ses-20110101/anat/sub-000_ses-20110101_desc-angio_N4bfc_brain_mask.nii.gz
MRA     ?= data/mra.nii.gz

$(UV):
	curl -LsSf https://astral.sh/uv/install.sh | sh

$(PY): | $(UV)
	$(UV) venv $(VENV) --python 3.12 --clear

# GPU gate (III): RAPIDS needs Pascal+ (compute >= 6.0) — rig A4000 = 8.6,
# laptop 980M = 5.2. Sensed once at parse; consumers: the venv rule (cuCIM)
# and the TotalSegmentator device flag.
COMPUTE_CAP := $(shell nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1)
GPU_RAPIDS  := $(shell awk 'BEGIN{print (("$(COMPUTE_CAP)"+0) >= 6.0) ? 1 : 0}')

# deps marker: a real file the install creates (skan ships no binary, its
# package __init__ is the honest witness). Depends on this Makefile so
# dep-list edits reinstall.
$(VENV)/lib/python3.12/site-packages/skan/__init__.py: Makefile | $(PY)
	$(VENV_PIP) nibabel scikit-image scipy trimesh skan nilearn matplotlib $(if $(filter 1,$(GPU_RAPIDS)),cucim-cu12 cupy-cuda12x)

data/mra.nii.gz:
	mkdir -p data
	curl -fsSL $(MRA_URL) -o $@

# ---- extraction: one script, one output ----------------------------------
work/vesselness.nii.gz: $(MRA) scripts/frangi_field.py | $(VENV)/lib/python3.12/site-packages/skan/__init__.py
	mkdir -p work
	$(PY) scripts/frangi_field.py $(MRA) $@

# the DECISION: threshold + anatomy gate. Dark mode demands the head mask
# (XVIII); MASKS=learned adds the TotalSegmentator brain, which the script
# prefers by file presence.
work/mask.nii.gz: work/vesselness.nii.gz scripts/tube_mask.py $(if $(filter dark,$(VESSEL_POLARITY)),work/head.nii.gz $(if $(filter learned,$(MASKS)),work/seg/brain.nii.gz))
	$(PY) scripts/tube_mask.py work/vesselness.nii.gz $@

# head mask as one c3d pipeline (the specialist)
work/head.nii.gz: $(MRA)
	mkdir -p work
	c3d $(MRA) -smooth 2mm -pim r -thresh 20% inf 1 0 -comp -thresh 1 1 1 0 -holefill 1 0 -o $@

# learned brain (opt-in MASKS=learned): PyTorch ~3GB rides this recipe,
# not the base venv. CPU ~15min; rig GPU ~1min.
work/seg/brain.nii.gz: $(MRA)
	$(VENV_PIP) totalsegmentator
	$(VENV)/bin/TotalSegmentator -i $(MRA) -o work/seg -ta total_mr -d $(if $(filter 1,$(GPU_RAPIDS)),gpu,cpu)

work/vessels.ply: work/mask.nii.gz scripts/lumen_mesh.py
	$(PY) scripts/lumen_mesh.py work/mask.nii.gz $@

work/brain.ply: work/head.nii.gz scripts/shell_mesh.py $(if $(filter learned,$(MASKS)),work/seg/brain.nii.gz)
	$(PY) scripts/shell_mesh.py work/head.nii.gz $@

work/flow.json: work/mask.nii.gz scripts/flow_threads.py
	$(PY) scripts/flow_threads.py work/mask.nii.gz $@

# ---- operator database ---------------------------------------------------
# the cached Cycles realization; geometry + looks in, .blend out. The
# shell rides only in dark mode.
operator/scene.blend: work/vessels.ply work/flow.json $(if $(filter dark,$(VESSEL_POLARITY)),work/brain.ply) looks.json scripts/build_scene.py
	mkdir -p operator
	$(BLENDER) --background --python scripts/build_scene.py -- work looks.json $@ $(or $(LIGHT_SCALE),1.0)

# rendering the cached .blend is a stock Blender invocation — no script
operator/void.png: operator/scene.blend
	$(BLENDER) --background operator/scene.blend --render-output //void_#### --render-frame 1
	mv operator/void_0001.png $@

# extraction QC plots the decision itself — QC cannot disagree with truth
operator/heuristics-vessels-garbage.png: work/mask.nii.gz scripts/overlay_qc.py
	mkdir -p operator
	$(PY) scripts/overlay_qc.py $(MRA) work/mask.nii.gz $@

# ---- customer database (Blender-free by design) --------------------------
work/vessels.glb: work/vessels.ply work/flow.json $(if $(filter dark,$(VESSEL_POLARITY)),work/brain.ply) looks.json scripts/export_glb.py
	$(PY) scripts/export_glb.py work looks.json $@

customer/vessels.opt.glb: work/vessels.glb
	mkdir -p customer
	command -v npx >/dev/null && npx --yes @gltf-transform/cli optimize work/vessels.glb $@ || echo ">>> SKIP: npm absent (POST provisions it: make | sudo bash)"

# ---- dormant: NIfTI->VDB (organs-as-nebulae) — no consumer yet, so it is
# not in any aggregate; activates with the nebula shader in build_scene.py
work/context.vdb: work/vesselness.nii.gz scripts/nifti_to_vdb.py
	$(BLENDER) --background --python scripts/nifti_to_vdb.py -- work/vesselness.nii.gz $@

# Stack diagram: plantuml is POST-provisioned; warn-continue (IV)
docs/stack.png: docs/stack.puml
	command -v plantuml >/dev/null && plantuml -tpng $< || echo ">>> SKIP: plantuml absent (POST provisions it: make | sudo bash)"

.PHONY: render
render: operator/void.png

.PHONY: clean
clean:
	rm -rf $(VENV) work operator customer frames web usd
	@echo ">>> data/ preserved (re-download); looks.json is authored truth"
