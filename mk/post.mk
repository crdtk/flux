# POST system — Power-On Self Test: diagnostic and fix pipeline.
#
# stderr: colored boot-sequence output as data is collected.
# stdout: ordered shell commands satisfying every failure.
#
# Pipe is acceptance:
#   make              — plan visible, nothing applied
#   make | sudo bash  — plan applied

export USER_HOME RUN_AS_USER DOWNLOADS_DIR UBUNTU_CODENAME

SWIPL   := /usr/bin/swipl
POST_PL := $(CURDIR)/post/post.pl

.PHONY: all
all:
	$(SWIPL) -g main -g halt $(POST_PL)
