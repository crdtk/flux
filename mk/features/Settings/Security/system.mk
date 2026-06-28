
HARDENING  += /etc/sudoers.d/50-claude-safe

define CLAUDE_SAFE_SUDOERS
# Allow any user to run claude as ai-agent without password, forwarding CLAUDE_CONFIG_DIR
ALL ALL=(ai-agent) NOPASSWD: SETENV: /usr/local/bin/claude
endef

/etc/sudoers.d/50-claude-safe:
	$(file >$@,$(CLAUDE_SAFE_SUDOERS))
	chmod 440 $@
	@echo ">>> ai-agent: NOPASSWD SETENV sudo grant written"

/home/ai-agent:
	adduser --system --group --shell /bin/false --disabled-login --home /home/ai-agent ai-agent
	chmod 700 $@
	@echo ">>> ai-agent: system user created"

.PHONY: claude-safe
claude-safe: /etc/sudoers.d/50-claude-safe /home/ai-agent
	sudo -u ai-agent CLAUDE_CONFIG_DIR="$(HOME)/.claude" claude
