include mk/user/albert.mk
include mk/user/shell.mk
include mk/user/demos.mk
include mk/user/panels.mk
include mk/user/plasmoids.mk
include mk/user/references.mk

USER_PENDING := $(filter-out $(wildcard $(USER_FILES)),$(USER_FILES))

.PHONY: user
user: $(USER_PENDING) configure-panels configure-shell
	/usr/bin/kbuildsycoca6
