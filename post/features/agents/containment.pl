%% agents/containment — agents must never escalate. An agent running as
%% the sudoer user cannot answer a password prompt, but it CAN ride the
%% ticket sudo caches for 15 minutes after the human authenticates (e.g.
%% right after `| sudo bash`). timestamp_timeout=0 kills the cache:
%% sudo -n always fails, every escalation needs a live human at the
%% prompt. visudo -cf guards the install — a syntactically broken drop-in
%% would lock sudo out entirely. The existence check mirrors
%% 50-claude-safe (content is 0440 root). The Claude Code deny rule is the
%% agent-side layer; the ai-agent sandbox (agents/claude-safe) is the hard
%% guarantee.

hardening_check(sudo_no_cached_ticket,
    "test -f /etc/sudoers.d/60-no-cached-ticket",
    "printf 'Defaults timestamp_timeout=0\\n' > /tmp/60-no-cached-ticket && visudo -cf /tmp/60-no-cached-ticket && install -m 440 -o root -g root /tmp/60-no-cached-ticket /etc/sudoers.d/60-no-cached-ticket; rm -f /tmp/60-no-cached-ticket").

% Claude Code must never invoke sudo (pipe is acceptance — the human runs
% `| sudo bash`). A user-level deny rule enforces this in every session and
% permission mode, complementing the sudoers timestamp_timeout=0 layer.
user_config(claude_deny_sudo, Check, Fix) :-
    user_home(Home),
    format(atom(Check),
        "jq -e '.permissions.deny // [] | index(\"Bash(sudo *)\")' ~w/.claude/settings.json >/dev/null 2>&1",
        [Home]),
    format(atom(Fix),
        "mkdir -p ~w/.claude && { test -f ~w/.claude/settings.json || printf '{}' > ~w/.claude/settings.json; } && jq '.permissions.deny = ((.permissions.deny // []) + [\"Bash(sudo *)\"] | unique)' ~w/.claude/settings.json > ~w/.claude/settings.json.tmp && mv ~w/.claude/settings.json.tmp ~w/.claude/settings.json",
        [Home, Home, Home, Home, Home, Home, Home]).

user_config_deps(claude_deny_sudo, [packages_installed]).
