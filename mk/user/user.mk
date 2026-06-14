#include mk/user/albert.mk
include mk/user/shell.mk
include mk/user/demos.mk
include mk/user/panels/panels.mk
include mk/user/plasmoids.mk
include mk/user/references.mk
include mk/user/vscode.mk

USER_PENDING := $(filter-out $(wildcard $(USER_FILES)),$(USER_FILES))

.PHONY: user
user: $(USER_PENDING) \
    $(if $(filter 0,$(GLOBALMENU_OK)),configure-top-panel) \
    $(if $(or $(filter 0,$(DOCK_OK)),$(filter 0,$(DOCK_CONFIGURED_OK))),configure-bottom-panel) \
    configure-panels \
    configure-shell \
    configure-vscode
	/usr/bin/kbuildsycoca6
