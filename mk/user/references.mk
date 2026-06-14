USER_FILES += \
    References/Motherboard/E3C256D4I-2T.pdf \
    References/Motherboard/ASUS-Prime-X299-A-II.pdf \
    References/Case/ENTHOO-PRO-II/Enthoo_Pro2_Manual_v1.1.pdf \
    References/Storage/SN8100/WD_Black_SN8100_Datasheet.pdf \
    References/Storage/MB111VP-B/MB111VP_B_Manual.pdf \
    References/Storage/MB705M2P-B/MB705M2P-B_Manual.pdf

References/Motherboard/E3C256D4I-2T.pdf:
	mkdir -p $(dir $@)
	curl -fL --progress-bar -o $@ https://download.asrock.com/Manual/E3C256D4I-2T.pdf
	@echo ">>> $@"

References/Motherboard/ASUS-Prime-X299-A-II.pdf:
	mkdir -p $(dir $@)
	curl -fL --progress-bar -o $@ https://dlcdnets.asus.com/pub/ASUS/mb/LGA2066/PRIME_X299-A_II/E15936_PRIME_X299-A_II_UM_V2_WEB.pdf
	@echo ">>> $@"

References/Case/ENTHOO-PRO-II/Enthoo_Pro2_Manual_v1.1.pdf:
	mkdir -p $(dir $@)
	curl -fL --progress-bar -o $@ https://phanteks.com/manuals/Enthoo_Pro2_Manual_v1.1.pdf
	@echo ">>> $@"

References/Storage/SN8100/WD_Black_SN8100_Datasheet.pdf:
	mkdir -p $(dir $@)
	#curl -fL --progress-bar -o $@ https://documents.sandisk.com/content/dam/asset-library/en_us/assets/public/sandisk/product/internal-drives/wd-black-ssd/data-sheet-wd-black-ssd-sn8100-nvme-ssd.pdf
	@echo ">>> $@"

References/Storage/MB111VP-B/MB111VP_B_Manual.pdf:
	mkdir -p $(dir $@)
	curl -fL --progress-bar -o $@ https://global.icydock.com/vancheerfile/files/installation_guide/MB111VP_B_Manual.pdf
	@echo ">>> $@"

References/Storage/MB705M2P-B/MB705M2P-B_Manual.pdf:
	mkdir -p $(dir $@)
	curl -fL --progress-bar -o $@ "https://www.icydock.com/Installation%20Guide/MB705M2P-B-webpage_manual.pdf"
	@echo ">>> $@"
