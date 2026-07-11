# POST system — Power-On Self Test: diagnostic and fix pipeline.
# Governed by constitution XXI–XXIV (Makefile header).
#
# stderr: colored boot-sequence output as data is collected.
# stdout: ordered shell commands satisfying every failure.
#
# Pipe is acceptance (XXII). The plan is privilege-agnostic — one stream,
# guarded per command, safe under either shell:
#   make              — plan visible, nothing applied
#   make | bash       — user-level fixes applied in the caller's own session;
#                       stops at the sentinel if root fixes remain
#   make | sudo bash  — root fixes applied; user-level fixes skipped (guarded),
#                       never run as root
# Each pipe re-senses, so alternating the two converges (II).

export USER_HOME RUN_AS_USER DOWNLOADS_DIR UBUNTU_CODENAME

SWIPL   := /usr/bin/swipl
POST_PL := $(CURDIR)/post/post.pl

# @-silenced: make echoes unsilenced recipe lines to STDOUT, and under
# `make | sudo bash` that echoed swipl line becomes the first command bash
# executes — POST runs a second time as root mid-stream and garbles the plan
# (heredoc bodies included). stdout must carry the plan and nothing else.
.PHONY: all
all:
	@$(SWIPL) -g main -g halt $(POST_PL)

## One-time interactive login for the ai-agent sandbox (own OAuth token,
## stored in /home/ai-agent — revocable independently of the user's).
## Sanctioned by the 50-claude-safe sudoers rule (NOPASSWD).
.PHONY: agent-login
agent-login:
	sudo -u ai-agent /usr/local/bin/claude
