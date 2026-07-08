%% dev/ide — VS Code (Microsoft repo, GPU workaround, workspace settings,
%% extensions, OpenCode Zen commit-message key) and PyCharm Community
%% (JetBrains tarball, menu entry).

binary_pkg('/usr/bin/code', code).

apt_repo(microsoft_vscode,
    "test -f /etc/apt/sources.list.d/code.list",
    "curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/microsoft.gpg && echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/code stable main' > /etc/apt/sources.list.d/code.list").

pkg_repo(code, microsoft_vscode).

config_patch(code_disable_gpu,
    '/usr/bin/code',
    "grep -q 'disable-gpu' /usr/share/applications/code.desktop 2>/dev/null",
    "sed -i 's|Exec=/usr/share/code/code|Exec=/usr/share/code/code --disable-gpu|g' /usr/share/applications/code.desktop").

opt_install(pycharm, '/opt/pycharm-community/bin/pycharm.sh', Cmd) :-
    downloads_dir(DDir),
    format(atom(Cmd),
        "URL=$(curl -fsSL 'https://data.services.jetbrains.com/products/releases?code=PCC&latest=true&type=release' | jq -r '.PCC[0].downloads.linux.link') && curl -fL --retry 5 --retry-delay 3 -A 'Mozilla/5.0' \"$URL\" -o \"~w/$(basename \"$URL\")\" && tar -xz -C /opt --transform 's|^pycharm-[^/]*|pycharm-community|' -f \"~w/$(basename \"$URL\")\"",
        [DDir, DDir]).

opt_install_deps(pycharm, [internet_ok, packages_installed]).  % needs jq

config_patch(pycharm_menu_entry,
    '/opt/pycharm-community/bin/pycharm.sh',
    "test -f /usr/share/applications/pycharm-community.desktop",
    "printf '%s\\n' '[Desktop Entry]' 'Name=PyCharm Community Edition' 'Type=Application' 'Exec=/opt/pycharm-community/bin/pycharm.sh %f' 'Icon=/opt/pycharm-community/bin/pycharm.svg' 'Terminal=false' 'Categories=Development;IDE;' 'MimeType=text/x-python;' > /usr/share/applications/pycharm-community.desktop").

%% VS Code: workspace interpreter path (merge, don't clobber) + extensions.
user_config(vscode_workspace_settings, Check, Fix) :-
    project_dir(Proj),
    format(atom(Check),
        "jq -e '.\"python.defaultInterpreterPath\"' '~w/.vscode/settings.json' >/dev/null 2>&1",
        [Proj]),
    format(atom(Fix),
        "mkdir -p '~w/.vscode' && { test -f '~w/.vscode/settings.json' || printf '{}' > '~w/.vscode/settings.json'; } && jq '. + {\"python.defaultInterpreterPath\": \"${workspaceFolder}/.venv/bin/python\"}' '~w/.vscode/settings.json' > '~w/.vscode/settings.json.tmp' && mv '~w/.vscode/settings.json.tmp' '~w/.vscode/settings.json'",
        [Proj, Proj, Proj, Proj, Proj, Proj, Proj]).
vscode_extension('ms-python.python').
vscode_extension('ms-toolsai.jupyter').
vscode_extension('ms-vscode-remote.remote-ssh').
vscode_extension('Google.colab').
vscode_extension('BusinessAddonscom.gitmessagegenerator').
user_config(vscode_ext(Ext), Check, Fix) :-
    vscode_extension(Ext),
    user_home(Home),
    downcase_atom(Ext, ExtLc),
    format(atom(Check),
        "ls ~w/.vscode/extensions 2>/dev/null | grep -q '^~w-'", [Home, ExtLc]),
    format(atom(Fix), "code --install-extension ~w", [Ext]).
%% OpenCode Zen key for commit messages — only when the key is in the env.
user_config(vscode_opencode_zen, Check, Fix) :-
    getenv('OPENCODE_ZEN_KEY', Key),
    user_home(Home),
    format(atom(Check),
        "grep -q opencodeZenKey ~w/.config/Code/User/settings.json 2>/dev/null", [Home]),
    format(atom(Fix),
        "mkdir -p ~w/.config/Code/User && { test -f ~w/.config/Code/User/settings.json || printf '{}' > ~w/.config/Code/User/settings.json; } && jq --arg key '~w' '. + {\"gitMessageGenerator.opencodeZenKey\": $key, \"gitMessageGenerator.provider\": \"opencode-zen\"}' ~w/.config/Code/User/settings.json > ~w/.config/Code/User/settings.json.tmp && mv ~w/.config/Code/User/settings.json.tmp ~w/.config/Code/User/settings.json",
        [Home, Home, Home, Key, Home, Home, Home, Home]).

user_config_deps(vscode_workspace_settings, [packages_installed]).
user_config_deps(vscode_ext(_),             [packages_installed]).
user_config_deps(vscode_opencode_zen,       [packages_installed]).
