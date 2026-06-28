
HARDENING  += /etc/sudoers.d/50-claude-safe /usr/local/bin/claude

define CLAUDE_SAFE_SUDOERS
# Allow any user to run claude as ai-agent without password, forwarding CLAUDE_CONFIG_DIR
ALL ALL=(ai-agent) NOPASSWD: SETENV: /usr/local/bin/claude
endef

.PHONY: claude-safe
claude-safe: /etc/sudoers.d/50-claude-safe  
	sudo -u ai-agent CLAUDE_CONFIG_DIR="$(HOME)/.claude" claude

/etc/sudoers.d/50-claude-safe: /home/ai-agent
	$(file >$@,$(CLAUDE_SAFE_SUDOERS))
	@chmod 440 $@ && echo ">>> ai-agent: NOPASSWD SETENV sudo grant written"

/home/ai-agent: /usr/local/bin/claude
	adduser --system --group --shell /bin/false --disabled-login --home /home/ai-agent ai-agent && chmod 700 $@ && setfacl -m u:ai-agent:x $(HOME) && setfacl -m u:ai-agent:r $(HOME)/.claude/.credentials.json && echo ">>> ai-agent: system user created"

/usr/local/bin/claude:
	npm install -g @anthropic-ai/claude-code && echo ">>> Claude Code installed globally"