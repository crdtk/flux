%% dev/toolchain — compilers, interpreters, package managers and local
%% inference runtime: cmake, g++, SWI-Prolog (POST's own interpreter),
%% gh, npm, uv, LM-Studio, gemini CLI.

binary_pkg('/usr/bin/cmake',         cmake).
binary_pkg('/usr/bin/g++-14',        'g++-14').
binary_pkg('/usr/bin/swipl',         'swi-prolog-core').
binary_pkg('/usr/bin/gh',            gh).
binary_pkg('/usr/bin/npm',           npm).
binary_pkg('/opt/LM-Studio/lm-studio', 'lm-studio').

%% deb_install(+SentinelPath): installed from a local .deb, not a plain apt package.
deb_install('/opt/LM-Studio/lm-studio').
deb_source('/opt/LM-Studio/lm-studio',
    'https://installers.lmstudio.ai/linux/x64/0.4.7-4/LM-Studio-0.4.7-4-x64.deb',
    'LM-Studio-0.4.7-4-x64.deb').
%% Applied only after a fresh install (sentinel was missing before this run).
desktop_fix('/opt/LM-Studio/lm-studio',
    '/usr/share/applications/lm-studio.desktop',
    's|Exec=/opt/LM-Studio/lm-studio|Exec=/opt/LM-Studio/lm-studio --use-gl=desktop|').

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
