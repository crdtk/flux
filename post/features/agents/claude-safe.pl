%% agents/claude-safe — sandboxed Claude Code as a system user (see memory:
%% project-claude-safe). Three checks chained by single-level deps:
%% binary → user → sudoers. No credentials sharing: an ACL on the human's
%% .credentials.json silently dies on the next token refresh (Claude Code
%% rewrites the file atomically, dropping ACLs — observed 2026-07-08), and
%% the sandbox should hold its own revocable OAuth token anyway (one-time
%% `make agent-login`). The human gets a read-only supervision ACL into the
%% sandbox home (default ACL inherits onto new files) so POST can verify
%% login state; ai-agent gets traversal into the human's home to read
%% project files.

service_check(claude_bin,
    "test -x /usr/local/bin/claude",
    "npm install -g @anthropic-ai/claude-code").
service_check(ai_agent_user, Check, Fix) :-
    run_as_user(User), user_home(Home),
    format(atom(Check),
        "id ai-agent >/dev/null 2>&1 && getfacl -p /home/ai-agent 2>/dev/null | grep -q '^user:~w:r-x'",
        [User]),
    format(atom(Fix),
        "{ id ai-agent >/dev/null 2>&1 || adduser --system --group --shell /bin/false --disabled-login --home /home/ai-agent ai-agent; } && chmod 700 /home/ai-agent && setfacl -R -m u:~w:rX /home/ai-agent && setfacl -d -m u:~w:rX /home/ai-agent && setfacl -m u:ai-agent:x ~w",
        [User, User, Home]).
service_check(claude_safe_sudoers,
    "test -f /etc/sudoers.d/50-claude-safe",
    "printf '%s\\n' '# Allow any user to run claude as ai-agent without password, forwarding CLAUDE_CONFIG_DIR' 'ALL ALL=(ai-agent) NOPASSWD: SETENV: /usr/local/bin/claude' > /etc/sudoers.d/50-claude-safe && chmod 440 /etc/sudoers.d/50-claude-safe").

service_deps(claude_bin,          [packages_installed]).
service_deps(ai_agent_user,       [service_ready(claude_bin)]).
service_deps(claude_safe_sudoers, [service_ready(ai_agent_user)]).

%% ai-agent login is OAuth — needs a human once, never auto-fixable.
%% Readable only via the supervision ACL (ai_agent_user fix).
advisory(services, ai_agent_login,
         'no credentials — run make agent-login once (after applying POST)') :-
    shell_ok("id ai-agent"),
    \+ shell_ok("test -s /home/ai-agent/.claude/.credentials.json").
