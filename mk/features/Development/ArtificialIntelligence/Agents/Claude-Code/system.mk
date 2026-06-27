
# --- Agent user ---
# Restricted sandbox account for AI agent execution (Claude Code, vLLM, etc.)
# Locked password — switch via: sudo su -l agent
# GPU access via video/render groups; sudo denied unconditionally.

AGENT_UID := $(shell id -u agent 2>/dev/null)

MANAGEMENT += $(if $(AGENT_UID),,/home/agent)
HARDENING  += /etc/sudoers.d/99-deny-agent \
              /etc/security/limits.d/agent.conf

define AGENT_BASHRC
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
umask 027
endef

/home/agent:
	useradd --create-home --home-dir /home/agent \
	  --shell /bin/bash --comment "AI Agent sandbox" \
	  --groups video,render agent
	usermod -L agent
	$(file >/home/agent/.bashrc,$(AGENT_BASHRC))
	$(file >/home/agent/.profile,$(AGENT_BASHRC))
	chmod 750 /home/agent
	chown -R agent:agent /home/agent
	@echo ">>> agent: created (locked password, groups: video render)"

define AGENT_SUDOERS_DENY
# Deny sudo for agent regardless of any group membership
agent ALL=(ALL:ALL) !ALL
endef

/etc/sudoers.d/99-deny-agent:
	$(file >$@,$(AGENT_SUDOERS_DENY))
	chmod 440 $@
	@echo ">>> agent: sudo denied"

define AGENT_LIMITS
agent  hard  nproc   512
agent  hard  nofile  4096
agent  soft  nproc   256
agent  soft  nofile  2048
endef

/etc/security/limits.d/agent.conf:
	$(file >$@,$(AGENT_LIMITS))
	@echo ">>> agent: resource limits applied (nproc=512, nofile=4096)"
  
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

