# POST system — Power-On Self Test: diagnostic and fix pipeline.
# Governed by constitution XXI–XXIV (Makefile header).
#
# stderr: colored boot-sequence output as data is collected.
# stdout: ordered shell commands satisfying every failure.
#
# Pipe is acceptance (XXII):
#   make              — plan visible, nothing applied
#   make | sudo bash  — plan applied

export USER_HOME RUN_AS_USER DOWNLOADS_DIR UBUNTU_CODENAME

SWIPL   := /usr/bin/swipl
POST_PL := $(CURDIR)/post/post.pl

.PHONY: all
all:
	$(SWIPL) -g main -g halt $(POST_PL)

## One-time interactive login for the ai-agent sandbox (own OAuth token,
## stored in /home/ai-agent — revocable independently of the user's).
## Sanctioned by the 50-claude-safe sudoers rule (NOPASSWD).
.PHONY: agent-login
agent-login:
	sudo -u ai-agent /usr/local/bin/claude
