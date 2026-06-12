.PHONY: references
define REF_LIST
  https://download.asrock.com/Manual/E3C256D4I-2T.pdf
    "References/Motherboard/E3C256D4I-2T.pdf"
  https://dlcdnets.asus.com/pub/ASUS/mb/LGA2066/PRIME_X299-A_II/E15936_PRIME_X299-A_II_UM_V2_WEB.pdf
    "References/Motherboard/ASUS Prime X299-A II.pdf"
  https://phanteks.com/manuals/Enthoo_Pro2_Manual_v1.1.pdf
    "References/Case/ENTHOO PRO II/Enthoo_Pro2_Manual_v1.1.pdf"
  https://documents.sandisk.com/content/dam/asset-library/en_us/assets/public/sandisk/product/internal-drives/wd-black-ssd/data-sheet-wd-black-sn8100-nvme-ssd.pdf
    "References/Storage/SN8100/WD_Black_SN8100_Datasheet.pdf"
  https://global.icydock.com/vancheerfile/files/installation_guide/MB111VP_B_Manual.pdf
    "References/Storage/MB111VP-B/MB111VP_B_Manual.pdf"
  "https://www.icydock.com/Installation%20Guide/MB705M2P-B-webpage_manual.pdf"
    "References/Storage/MB705M2P-B/MB705M2P-B_Manual.pdf"
endef
references:
	@set -- $(strip $(REF_LIST)); \
	while [ "$$#" -ge 2 ]; do \
	  url="$$1"; dest="$$2"; shift 2; \
	  [ -f "$$dest" ] || { mkdir -p "$$(dirname "$$dest")"; curl -fL --progress-bar -o "$$dest" "$$url"; echo ">>> $$dest"; }; \
	done
