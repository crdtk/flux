MAKEFLAGS += --no-builtin-rules
.SUFFIXES:

# vessels — heuristic vessel extraction from public TOF-MRA into the USD stack.
# Data: OpenNeuro ds003949 (Di Noto et al., Lausanne aneurysm study), healthy
# control sub-000, N4-corrected skull-stripped angio derivative — direct S3,
# no auth. (IXI would also serve, but its host 403s non-browser fetches.)
#   NIfTI -> Frangi vesselness -> mesh + skeleton threads (extract)
#         -> layered OpenUSD scene: anatomy / flow / void look (author)
#         -> Cycles "luminous threads in glass on black void" render
#         -> glTF for web/AR; best-effort NIfTI->VDB for volume context.
# Proves the chain on open data; a personal TOF-MRA slots in via MRA=path.

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

# usdcat is a real binary usd-core installs — the deps marker (no sentinels).
$(VENV)/bin/usdcat: | $(PY)
	$(VENV_PIP) nibabel scikit-image scipy trimesh usd-core

data/mra.nii.gz:
	mkdir -p data
	curl -fsSL $(MRA_URL) -o $@

work/vessels.ply: $(MRA) | $(VENV)/bin/usdcat
	$(PY) scripts/extract_vessels.py $(MRA) work

usd/scene.usda: work/vessels.ply
	$(PY) scripts/author_usd.py work usd

frames/void.png: usd/scene.usda
	mkdir -p frames work
	$(BLENDER) --background --python scripts/render_void.py -- usd/scene.usda usd/materials.json $@ $(or $(SAMPLES),128) $(or $(LIGHT_SCALE),1.0)

web/vessels.glb: usd/scene.usda
	mkdir -p web
	$(BLENDER) --background --python scripts/export_glb.py -- usd/scene.usda $@

# Volume context as VDB (organs-as-nebulae tier). pyopenvdb wheels are
# spotty; degrade to a SKIP message rather than failing the chain.
work/context.vdb: work/vessels.ply
	$(VENV_PIP) pyopenvdb 2>/dev/null || true
	$(PY) scripts/nifti_to_vdb.py work/vesselness.nii.gz $@

.PHONY: render
render: frames/void.png

.PHONY: clean
clean:
	rm -rf $(VENV) work frames web
	@echo ">>> data/ and usd/ preserved (data is a 15MB re-download; usd is authored truth)"
