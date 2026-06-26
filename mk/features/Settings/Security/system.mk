MANAGEMENT += /etc/profile.d/universal-ai-security.sh

# The shield is installed for everyone, but applies per login user: sudoers (admins) are
# exempt and keep SSH_AUTH_SOCK / tokens / env / cat; non-sudoers get locked down. The
# decision is made at login by `id -nG`, not at install time.
define SECURITY_SCRIPT_CONTENTS
#!/bin/sh
# AI-security shield. Admins (members of the sudo group) pass through untouched; everyone
# else has agent-exploitable env and tools stripped at login.
if ! id -nG 2>/dev/null | grep -qw sudo; then
    # Break GNOME Keyring and active SSH socket inheritances
    unset SSH_AUTH_SOCK
    unset GITHUB_TOKEN
    unset GITHUB_PAT

    # Block environmental scraping/debugging tricks
    alias env="echo 'Command blocked by system security policy.'"
    alias printenv="echo 'Command blocked by system security policy.'"
    alias set="echo 'Command blocked by system security policy.'"

    # Prevent raw text tools from dumping potential key signatures
    alias cat='function _guard() { if echo "$$*" | grep -Eiq "env|key|secret|credential|token"; then echo "Access Denied"; else command cat "$$@"; fi }; _guard'
fi

# Drop AI agents to the unprivileged box (available to everyone)
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
