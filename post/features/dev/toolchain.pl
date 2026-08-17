%% dev/toolchain — compilers, interpreters, package managers and local
%% inference runtime: cmake, g++, SWI-Prolog (POST's own interpreter),
%% gh, npm, uv, gemini CLI.

binary_pkg('/usr/bin/cmake',         cmake).
binary_pkg('/usr/bin/g++-14',        'g++-14').
binary_pkg('/usr/bin/swipl',         'swi-prolog-core').
binary_pkg('/usr/bin/gh',            gh).
binary_pkg('/usr/bin/npm',           npm).
%% LM Studio: retired 2026-08-17 (user decision 2026-08-15 "unused" —
%% inference lives on the rig via vLLM, its state dir was already swept
%% by lmstudio-clean). Install facts deleted; the purge below unwinds
%% the deb. Gate: never while the app is running.
hardening_check(no_lmstudio,
    "! dpkg -l lm-studio 2>/dev/null | grep -q '^ii'",
    "apt-get purge -y lm-studio") :-
    \+ shell_ok("pgrep -f /opt/LM-Studio >/dev/null 2>&1").

user_tool(uv,     '.local/bin/uv',     'curl -LsSf https://astral.sh/uv/install.sh | sh').
user_tool(gemini, '.local/bin/gemini', 'npm install --prefix ~/.local -g @google/gemini-cli').

user_tool_deps(uv,     [internet_ok]).
user_tool_deps(gemini, [internet_ok, packages_installed]).

%% Tab completion for the project's only interface (XIX).
user_config(bashrc_make_completion, Check, Fix) :-
    user_home(Home),
    format(atom(Check),
        "grep -q 'bash-completion/completions/make' ~w/.bashrc 2>/dev/null", [Home]),
    format(atom(Fix),
        "printf 'source %s\\n' '/usr/share/bash-completion/completions/make' >> ~w/.bashrc",
        [Home]).
