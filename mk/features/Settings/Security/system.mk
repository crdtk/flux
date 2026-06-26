MANAGEMENT += /etc/profile.d/universal-ai-security.sh

define SECURITY_SCRIPT_CONTENTS
#!/bin/sh
	# Aggressively break GNOME Keyring and active SSH socket inheritances
	unset SSH_AUTH_SOCK
	unset GITHUB_TOKEN
	unset GITHUB_PAT

	# Intercept and block internal environmental scraping/debugging tricks
	alias env="echo 'Command blocked by system security policy.'"
	alias printenv="echo 'Command blocked by system security policy.'"
	alias set="echo 'Command blocked by system security policy.'"

	# Prevent the AI from executing raw text tools against potential key signatures
	alias cat='function _guard() { if echo "$$*" | grep -Eiq "env|key|secret|credential|token"; then echo "Access Denied"; else command cat "$$@"; fi }; _guard'


	# Clear active socket markers and drop down to the unprivileged box
	alias run-claude='sudo -u ai-agent PATH="$$PATH" SSH_AUTH_SOCK="" /usr/local/bin/claude --continue'
	alias run-aider='sudo -u ai-agent PATH="$$PATH" SSH_AUTH_SOCK="" aider'
	alias run-agent='sudo -u ai-agent PATH="$$PATH" SSH_AUTH_SOCK=""'
endef

/etc/profile.d/universal-ai-security.sh:
	$(file >$@,$(SECURITY_SCRIPT_CONTENTS))
	@echo "Enforcing system-level permissions on $@..."
	@chmod 644 $@
	@chown root:root $@
	@echo "Success! Shield generated cleanly without spawning streaming shell pipes."
