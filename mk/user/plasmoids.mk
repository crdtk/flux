## KDE Store widgets — repo URL and package subdir, keyed by plugin id
WIDGET_SRC_com.github.antroids.application-title-bar := https://github.com/antroids/application-title-bar package
WIDGET_SRC_Plasma.Flex.Hub                           := https://github.com/zayronxio/Plasma.Flex.Hub .
WIDGET_SRC_com.github.chrtall.kppleMenu              := https://github.com/ChrTall/kppleMenu package

USER_FILES += $(PLASMOIDS)/com.github.antroids.application-title-bar/metadata.json \
             $(PLASMOIDS)/Plasma.Flex.Hub/metadata.json \
             $(PLASMOIDS)/com.github.chrtall.kppleMenu/metadata.json

$(PLASMOIDS)/%/metadata.json:
	rm -rf /tmp/$*
	git clone --depth 1 $(word 1,$(WIDGET_SRC_$*)) /tmp/$*
	kpackagetool6 -t Plasma/Applet -i /tmp/$*/$(word 2,$(WIDGET_SRC_$*))
	rm -rf /tmp/$*
	@echo ">>> Widget $* installed"
