# Claude Code — SYSTEM-WIDE install, usable by every account on the box. The official
# installer is per-user ($HOME-based, → ~/.local/bin/claude as a symlink into
# ~/.local/share/claude/versions/<v>). /home/m is 0750 so that's invisible to other
# accounts — instead we point HOME at a system prefix under /usr/local (world-traversable)
# and symlink the launcher into /usr/local/bin. Each user still gets their own ~/.claude
# config at runtime; only the binary is shared. Updates are a root action (re-run this
# target); non-root self-update simply can't write /usr/local, so the version is pinned
# system-wide until root refreshes it.
CLAUDE_PREFIX := /usr/local/lib/claude-code

MANAGEMENT += /usr/local/bin/claude

# XVIII: policy is an invariant of the binary — binary not considered installed without it.
/usr/local/bin/claude: /etc/claude-code/managed-settings.d/99-block-secrets.json
	mkdir -p $(CLAUDE_PREFIX)
	curl -fsSL https://claude.ai/install.sh | env HOME=$(CLAUDE_PREFIX) bash
	ln -sf $(CLAUDE_PREFIX)/.local/bin/claude $@

define CLAUDE_SECRETS_POLICY
{
  "permissions": {
    "deny": [
      "Read(./.env*)",
      "Read(./**/*.key)",
      "Read(./**/secrets/**)",
      "Bash(*cat *.env*)",
      "Bash(*printenv*)",
      "Bash(*env*)"
    ]
  }
}
endef

# VII: order-only prerequisite — directory must exist before $(file ...) expands.
/etc/claude-code/managed-settings.d/99-block-secrets.json: | /etc/claude-code/managed-settings.d
	$(file >$@,$(CLAUDE_SECRETS_POLICY))
	@echo ">>> Claude Code managed policy: secrets access denied"

/etc/claude-code/managed-settings.d:
	mkdir -p $@
