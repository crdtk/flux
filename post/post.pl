#!/usr/bin/env swipl
%% post/post.pl — Power-On Self Test: diagnostic and fix pipeline.
%%
%% stderr → colored boot-sequence output (human-readable).
%% stdout → shell commands that fix every failure (pipe to sudo bash).
%%
%% Pipe is acceptance:
%%   ./post.pl             — plan visible, nothing applied
%%   ./post.pl | sudo bash — plan applied

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(readutil)).

%% ── Dynamic state ─────────────────────────────────────────────────────────────

:- dynamic failed/3.      % failed(Level, Component, Reason)
:- dynamic satisfied/1.   % satisfied(Goal): already true, no action needed
:- dynamic build_rule/3.  % build_rule(Goal, Deps, Cmds)

%% KB predicates interleave plain facts with helper-gated rule clauses.
:- discontiguous binary_pkg/2, apt_repo/3, config_patch/4,
                 hardening_check/3, service_check/3, opt_install/3.

%% ── Environment ──────────────────────────────────────────────────────────────

downloads_dir(D) :-
    ( getenv('DOWNLOADS_DIR', D) -> true
    ; getenv('HOME', H), atom_concat(H, '/Downloads', D) ).

run_as_user(U) :-
    ( getenv('RUN_AS_USER', U) -> true
    ; getenv('SUDO_USER',   U) -> true
    ; getenv('USER',        U) ).

%% user_home(-H) — home of the real user, stable even when run under sudo
%% (where $HOME would be /root).
user_home(H) :-
    run_as_user(U),
    format(atom(H), '/home/~w', [U]).

%% os_release(+Key, -Value) — read /etc/os-release directly; environment
%% variables are not a reliable carrier for it (login shells don't export
%% UBUNTU_CODENAME).
os_release(Key, Value) :-
    read_file_to_string('/etc/os-release', S, []),
    split_string(S, "\n", "", Lines),
    format(atom(Prefix), '~w=', [Key]),
    member(L, Lines),
    string_concat(Prefix, V0, L),
    split_string(V0, "", "\"", [V1]),
    atom_string(Value, V1), !.

ubuntu_codename(C) :-
    ( os_release('UBUNTU_CODENAME', C) -> true
    ; getenv('UBUNTU_CODENAME', C)     -> true
    ; C = noble ).

%% ubuntu_ver(-V) — VERSION_ID without the dot (26.04 → 2604), the form
%% NVIDIA's CUDA repo paths use.
ubuntu_ver(V) :-
    os_release('VERSION_ID', VId),
    atomic_list_concat(Parts, '.', VId),
    atomic_list_concat(Parts, '', V).

has_nvidia :- shell_ok("lspci 2>/dev/null | grep -qi nvidia").

%% ── Display (→ stderr) ───────────────────────────────────────────────────────

section(Num, Title) :-
    format(user_error, '~n\033[1m-- ~w ~w ~`-t~55|\033[0m~n', [Num, Title]).

post_ok(Level, Comp, Detail) :-
    format(user_error, '\033[32m[ OK ]\033[0m  ~w/~w ~`.t~45|~w~n', [Level, Comp, Detail]).

post_warn(Level, Comp, Detail) :-
    format(user_error, '\033[33m[WARN]\033[0m  ~w/~w ~`.t~45|~w~n', [Level, Comp, Detail]).

post_fail(Level, Comp, Detail) :-
    format(user_error, '\033[31m[FAIL]\033[0m  ~w/~w ~`.t~45|~w~n', [Level, Comp, Detail]).

post_skip(Goal, Reason) :-
    format(user_error, '\033[33m[SKIP]\033[0m  ~w ~`.t~45|~w~n', [Goal, Reason]).

%% ── Knowledge base ───────────────────────────────────────────────────────────

%% binary_pkg(+SentinelPath, +PackageName)
%% PackageName is passed verbatim to apt install -y.
binary_pkg('/usr/bin/cmake',         cmake).
binary_pkg('/usr/bin/g++-14',        'g++-14').
binary_pkg('/usr/bin/swipl',         'swi-prolog-core').
binary_pkg('/usr/bin/gh',            gh).
binary_pkg('/usr/bin/npm',           npm).
binary_pkg('/usr/bin/flameshot',     flameshot).
binary_pkg('/usr/bin/gwenview',      gwenview).
binary_pkg('/usr/bin/heif-convert',  'libheif-examples').
binary_pkg('/usr/lib/x86_64-linux-gnu/qt5/plugins/imageformats/kimg_heif.so',
                                     'kimageformat-plugins').
binary_pkg('/usr/bin/terminator',    terminator).
binary_pkg('/usr/bin/mc',            mc).
binary_pkg('/usr/bin/plank',         plank).
binary_pkg('/usr/bin/rclone',        rclone).
binary_pkg('/usr/bin/syncthing',     syncthing).
binary_pkg('/usr/bin/xclip',         xclip).
binary_pkg('/usr/bin/jq',            jq).
binary_pkg('/usr/bin/cockpit-bridge', 'cockpit cockpit-files').
binary_pkg('/opt/LM-Studio/lm-studio', 'lm-studio').
binary_pkg('/usr/bin/code',          code).
binary_pkg('/usr/bin/tailscale',     tailscale).
binary_pkg('/usr/bin/kdenlive',      kdenlive).
binary_pkg('/usr/bin/digikam',       digikam).
binary_pkg('/usr/bin/obs',           'obs-studio').
binary_pkg('/usr/share/plasma/plasmoids/org.kde.plasma.kickerdash/metadata.json',
                                     'plasma-widgets-addons').
binary_pkg('/usr/bin/git',           git).
binary_pkg('/usr/sbin/avahi-daemon', 'avahi-daemon').
binary_pkg('/usr/sbin/arp-scan',     'arp-scan').
binary_pkg('/usr/bin/nmap',          nmap).
binary_pkg('/usr/bin/lspci',         pciutils).
binary_pkg('/usr/sbin/dmidecode',    dmidecode).
binary_pkg('/usr/bin/apt-file',      'apt-file').
binary_pkg('/usr/lib/x86_64-linux-gnu/gtk-3.0/modules/libappmenu-gtk-module.so',
                                     'appmenu-gtk3-module').
binary_pkg('/usr/libexec/vala-panel/appmenu-registrar',
                                     'appmenu-registrar').
%% The session file GDM/SDDM need to offer Plasma (X11) — POST's session fixes
%% assume it exists; this makes it restorable.
binary_pkg('/usr/share/xsessions/plasmax11.desktop',
                                     'plasma-session-x11').
%% CUDA toolkit — only a fact when an NVIDIA GPU is present.
binary_pkg('/usr/local/cuda/bin/nvcc', 'cuda-toolkit') :- has_nvidia.
%% Mir's atomic-kms display platform: the supported NVIDIA path on driver
%% 565+ (EGLStream is broken there, and gbm-kms block-lists nvidia).
%% Only needed where Lomiri is installed on an NVIDIA box.
binary_pkg('/usr/lib/x86_64-linux-gnu/mir/server-platform/graphics-atomic-kms.so.23',
           'mir-platform-graphics-atomic-kms') :-
    has_nvidia,
    shell_ok("test -x /usr/bin/lomiri").

%% deb_install(+SentinelPath): installed from a local .deb, not a plain apt package.
deb_install('/opt/LM-Studio/lm-studio').

%% deb_source(+SentinelPath, +URL, +Filename)
deb_source('/opt/LM-Studio/lm-studio',
    'https://installers.lmstudio.ai/linux/x64/0.4.7-4/LM-Studio-0.4.7-4-x64.deb',
    'LM-Studio-0.4.7-4-x64.deb').

%% apt_repo(+Name, +CheckShell, +AddCmd)
%% CheckShell exits 0 if the repo is already present.
%% AddCmd may be computed (see tailscale_repo below).
apt_repo(microsoft_vscode,
    "test -f /etc/apt/sources.list.d/code.list",
    "curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/microsoft.gpg && echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/code stable main' > /etc/apt/sources.list.d/code.list").
apt_repo(kubuntu_backports,
    "find /etc/apt/sources.list.d/ -name 'kubuntu-ppa-ubuntu-backports*' 2>/dev/null | grep -q .",
    "add-apt-repository -y ppa:kubuntu-ppa/backports").
apt_repo(obsproject,
    "find /etc/apt/sources.list.d/ -name 'obsproject*' 2>/dev/null | grep -q .",
    "add-apt-repository -y ppa:obsproject/obs-studio").
apt_repo(tailscale_repo,
    "test -f /etc/apt/sources.list.d/tailscale.list",
    AddCmd) :-
    ubuntu_codename(C),
    format(atom(AddCmd),
        "curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/~w.noarmor.gpg | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null && curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/~w.tailscale-keyring.list | tee /etc/apt/sources.list.d/tailscale.list",
        [C, C]).

%% NVIDIA's CUDA apt repo is added by installing the cuda-keyring deb, which
%% ships both the signing key and the sources.list entry.
apt_repo(cuda_repo, Check, AddCmd) :-
    ubuntu_ver(V),
    format(atom(Check),
        "test -f /etc/apt/sources.list.d/cuda-ubuntu~w-x86_64.list", [V]),
    downloads_dir(DDir),
    format(atom(AddCmd),
        "curl -fsSL https://developer.download.nvidia.com/compute/cuda/repos/ubuntu~w/x86_64/cuda-keyring_1.1-1_all.deb -o ~w/cuda-keyring_1.1-1_all.deb && apt install -y ~w/cuda-keyring_1.1-1_all.deb",
        [V, DDir, DDir]).

%% pkg_repo(+PackageName, +RepoName): package requires this repo before apt install.
pkg_repo(code,         microsoft_vscode).
pkg_repo(kdenlive,     kubuntu_backports).
pkg_repo(digikam,      kubuntu_backports).
pkg_repo('obs-studio', obsproject).
pkg_repo(tailscale,    tailscale_repo).
pkg_repo('cuda-toolkit', cuda_repo).

%% opt_install(+Name, +SentinelPath, +InstallCmd)
%% Software installed by a dedicated command (vendor tarball, ubuntu-drivers)
%% rather than a plain apt package. Diagnosed alongside packages; each gets its
%% own build rule (deps default to [internet_ok], override via opt_install_deps).
opt_install(nvidia_driver, '/usr/bin/nvidia-smi', 'ubuntu-drivers install') :-
    has_nvidia.
opt_install(pycharm, '/opt/pycharm-community/bin/pycharm.sh', Cmd) :-
    downloads_dir(DDir),
    format(atom(Cmd),
        "URL=$(curl -fsSL 'https://data.services.jetbrains.com/products/releases?code=PCC&latest=true&type=release' | jq -r '.PCC[0].downloads.linux.link') && curl -fL --retry 5 --retry-delay 3 -A 'Mozilla/5.0' \"$URL\" -o \"~w/$(basename \"$URL\")\" && tar -xz -C /opt --transform 's|^pycharm-[^/]*|pycharm-community|' -f \"~w/$(basename \"$URL\")\"",
        [DDir, DDir]).

%% opt_install_deps(+Name, +Deps): explicit dep override.
opt_install_deps(pycharm, [internet_ok, packages_installed]).  % needs jq

%% desktop_fix(+SentinelPath, +DesktopFile, +SedExpr)
%% Applied only after a fresh install (sentinel was missing before this run).
desktop_fix('/opt/LM-Studio/lm-studio',
    '/usr/share/applications/lm-studio.desktop',
    's|Exec=/opt/LM-Studio/lm-studio|Exec=/opt/LM-Studio/lm-studio --use-gl=desktop|').

%% config_patch(+Name, +Guard, +CheckShell, +FixCmd)
%% Guard: file that must exist for the check to be relevant.
%% CheckShell exits 0 if the patch is already applied.
%% Idempotent — applied regardless of whether the package was just installed.
config_patch(code_disable_gpu,
    '/usr/bin/code',
    "grep -q 'disable-gpu' /usr/share/applications/code.desktop 2>/dev/null",
    "sed -i 's|Exec=/usr/share/code/code|Exec=/usr/share/code/code --disable-gpu|g' /usr/share/applications/code.desktop").
config_patch(heif_mime_types,
    '/usr/lib/x86_64-linux-gnu/qt5/plugins/imageformats/kimg_heif.so',
    "! test -f /usr/share/kservices5/imagethumbnail.desktop || grep -q 'image/heif' /usr/share/kservices5/imagethumbnail.desktop 2>/dev/null",
    "sed -i 's|image/avif;|image/avif;image/heif;image/heic;|' /usr/share/kservices5/imagethumbnail.desktop 2>/dev/null || true").
%% The google-chrome-stable package ships two desktop entries:
%% google-chrome.desktop (the visible menu entry) and
%% com.google.Chrome.desktop (NoDisplay=true helper). If the visible one
%% goes missing, Chrome vanishes from the app menu; reinstalling the
%% package restores the file dpkg still claims to own.
config_patch(chrome_menu_entry,
    '/usr/bin/google-chrome',
    "test -f /usr/share/applications/google-chrome.desktop",
    "apt-get install --reinstall -y google-chrome-stable").
%% Chrome persists a "Preferred Ozone platform" choice in its profile; a
%% Wayland/Auto value saved during a Wayland session makes Chrome try the
%% nonexistent wayland-0 socket in an X11 session and exit. Resetting to
%% Default lets Chrome follow the actual session. Chrome must not be
%% running during the rewrite (it saves Local State on exit).
config_patch(chrome_ozone_default, '/usr/bin/google-chrome', Check, Fix) :-
    user_home(Home),
    format(atom(Check),
        "! grep -q ozone-platform-hint '~w/.config/google-chrome/Local State' 2>/dev/null",
        [Home]),
    run_as_user(User),
    format(atom(Fix),
        "jq '.browser.enabled_labs_experiments |= ((. // []) | map(select(startswith(\"ozone\") | not)))' '~w/.config/google-chrome/Local State' > '~w/.config/google-chrome/Local State.tmp' && mv '~w/.config/google-chrome/Local State.tmp' '~w/.config/google-chrome/Local State' && chown ~w:~w '~w/.config/google-chrome/Local State'",
        [Home, Home, Home, Home, User, User, Home]).
%% GDM's Wayland greeter leaks XDG_SESSION_TYPE=wayland and an empty
%% WAYLAND_DISPLAY into the login environment; apps launched via the
%% systemd/dbus activation environment (Plasma 6 launches everything that
%% way) then pick the Wayland backend inside an X11 session. This env
%% script, sourced by startplasma before the session settles, scrubs the
%% stale variables when the session is really X11.
config_patch(x11_env_scrub, '/usr/bin/startplasma-x11', Check, Fix) :-
    user_home(Home),
    % Not a bare sentinel: the script must exist AND, when the session is
    % genuinely X11, the live systemd activation environment must already
    % be clean (no WAYLAND_DISPLAY, XDG_SESSION_TYPE=x11) — apps launched
    % by Plasma inherit that environment, not the script's intent.
    format(atom(Check),
        "test -x ~w/.config/plasma-workspace/env/10-x11-scrub-wayland.sh && { ! pgrep -x startplasma-x11 >/dev/null || { systemctl --user show-environment 2>/dev/null | grep -qx XDG_SESSION_TYPE=x11 && ! systemctl --user show-environment 2>/dev/null | grep -q '^WAYLAND_DISPLAY='; }; }",
        [Home]),
    run_as_user(User),
    format(atom(Fix),
        "mkdir -p ~w/.config/plasma-workspace/env && printf '%s\\n' 'if [ -n \"$DISPLAY\" ] && [ -z \"$WAYLAND_DISPLAY\" ]; then' '    unset WAYLAND_DISPLAY' '    export XDG_SESSION_TYPE=x11' '    systemctl --user set-environment XDG_SESSION_TYPE=x11 2>/dev/null' '    systemctl --user unset-environment WAYLAND_DISPLAY 2>/dev/null' 'fi' > ~w/.config/plasma-workspace/env/10-x11-scrub-wayland.sh && chmod +x ~w/.config/plasma-workspace/env/10-x11-scrub-wayland.sh && chown -R ~w:~w ~w/.config/plasma-workspace && if pgrep -x startplasma-x11 >/dev/null; then sudo -u ~w XDG_RUNTIME_DIR=/run/user/$(id -u ~w) systemctl --user set-environment XDG_SESSION_TYPE=x11; sudo -u ~w XDG_RUNTIME_DIR=/run/user/$(id -u ~w) systemctl --user unset-environment WAYLAND_DISPLAY; fi",
        [Home, Home, Home, User, User, Home, User, User, User, User]).

config_patch(pycharm_menu_entry,
    '/opt/pycharm-community/bin/pycharm.sh',
    "test -f /usr/share/applications/pycharm-community.desktop",
    "printf '%s\\n' '[Desktop Entry]' 'Name=PyCharm Community Edition' 'Type=Application' 'Exec=/opt/pycharm-community/bin/pycharm.sh %f' 'Icon=/opt/pycharm-community/bin/pycharm.svg' 'Terminal=false' 'Categories=Development;IDE;' 'MimeType=text/x-python;' > /usr/share/applications/pycharm-community.desktop").
%% Lomiri on NVIDIA: Mir aborts at startup ("GBM display platform being
%% incompatible with Nvidia" → exception → SIGABRT, observed 2026-06-28).
%% Upstream-recommended fix for driver 565+: atomic-kms display platform +
%% gbm-kms rendering, plus a driver quirk lifting nvidia off the block list.
%% Delivered as a systemd user drop-in so it only affects lomiri.service.
config_patch(lomiri_nvidia_platform, '/usr/bin/lomiri', Check, Fix) :-
    has_nvidia,
    Check = "test -f /etc/systemd/user/lomiri.service.d/nvidia-platform.conf",
    Fix = "mkdir -p /etc/systemd/user/lomiri.service.d && printf '%s\\n' '[Service]' 'Environment=MIR_SERVER_PLATFORM_DISPLAY_LIBS=mir:atomic-kms' 'Environment=MIR_SERVER_PLATFORM_RENDERING_LIBS=mir:gbm-kms' 'Environment=MIR_SERVER_DRIVER_QUIRKS=allow:driver:nvidia' > /etc/systemd/user/lomiri.service.d/nvidia-platform.conf".

%% ── Selection: backtracking over ranked candidates ───────────────────────────
%% Generalizes the plasma-widget sentinel lesson: never trust the assumed
%% option. Candidates are declared in preference order (clause order = rank),
%% each must survive live heuristic probes, and the first survivor wins —
%% pure Prolog backtracking. Installed alternates are held standby-ready so
%% switching is a greeter choice, not a repair.

%% candidate(+Domain, -Option)
candidate(display_manager, gdm).      % proven here: launches X11, Wayland AND Lomiri sessions
candidate(display_manager, sddm).     % Plasma-native, plain INI config — first standby
candidate(display_manager, lightdm).  % cannot launch Wayland sessions — last resort
candidate(session, plasmax11).        % global menu needs X11 (KWin Wayland lacks appmenu)
candidate(session, plasmawayland).
candidate(session, lomiri).           % experimental — demoted while crash evidence stands

%% viable(+Domain, +Option) — live probes, not assumptions.
viable(display_manager, DM) :- dm_installed(DM).
viable(session, plasmax11) :-
    shell_ok("test -f /usr/share/xsessions/plasmax11.desktop").
viable(session, plasmawayland) :-
    shell_ok("test -f /usr/share/wayland-sessions/plasma.desktop").
viable(session, lomiri) :-
    shell_ok("test -f /usr/share/wayland-sessions/lomiri.desktop"),
    \+ lomiri_crash_evidence.

select(Domain, Choice) :- candidate(Domain, Choice), viable(Domain, Choice), !.

dm_installed(gdm)     :- shell_ok("test -x /usr/sbin/gdm3").
dm_installed(sddm)    :- shell_ok("test -x /usr/bin/sddm").
dm_installed(lightdm) :- shell_ok("test -x /usr/sbin/lightdm").

%% Lomiri session attempts leave component coredumps (Mir/NVIDIA SIGABRT
%% observed 2026-06-28). Once the NVIDIA platform fix is in place, only
%% crashes NEWER than the fix count — so one clean Lomiri login after
%% applying POST promotes the candidate without manual coredump clearing.
lomiri_crash_evidence :-
    shell_ok("test -f /etc/systemd/user/lomiri.service.d/nvidia-platform.conf"), !,
    shell_ok("coredumpctl list --since=@$(stat -c %Y /etc/systemd/user/lomiri.service.d/nvidia-platform.conf) --no-pager 2>/dev/null | grep -q lomiri").
lomiri_crash_evidence :-
    shell_ok("coredumpctl list --no-pager 2>/dev/null | grep -q lomiri").

lomiri_demotion_reason(Why) :-
    ( shell_ok("test -f /etc/systemd/user/lomiri.service.d/nvidia-platform.conf")
    -> Why = 'crashed again after NVIDIA platform fix — inspect coredumpctl'
    ;  Why = 'Mir rejects NVIDIA GBM — fix queued; apply POST, then retry a Lomiri login'
    ).

%% active_display_manager(-DM) — which greeter actually launches sessions.
%% /etc/X11/default-display-manager is authoritative on Debian/Ubuntu; if it
%% names nothing recognizable, fall back to the selector's choice.
active_display_manager(DM) :-
    member(DM, [gdm, sddm, lightdm]),
    format(atom(C), "grep -q ~w /etc/X11/default-display-manager 2>/dev/null", [DM]),
    shell_ok(C), !.
active_display_manager(DM) :- select(display_manager, DM).

%% dm_session_check(+DM, -CheckShell) / dm_session_fix(+DM, -FixCmd)
%% Is Plasma (X11) recorded as the default session where THIS display manager
%% actually reads it — and how to record it. GDM: AccountsService. SDDM:
%% /etc/sddm.conf.d + state.conf, with DisplayServer=x11 (the Wayland greeter
%% leaks WAYLAND_DISPLAY and KWin on Wayland lacks the appmenu protocol the
%% global menu needs). LightDM: conf.d user-session.
dm_session_check(gdm, Check) :-
    run_as_user(User),
    format(atom(Check),
        "busctl get-property org.freedesktop.Accounts /org/freedesktop/Accounts/User$(id -u ~w) org.freedesktop.Accounts.User Session | grep -q plasmax11",
        [User]).
dm_session_check(sddm,
    "grep -q 'Session=plasmax11' /etc/sddm.conf.d/20-kubuntu.conf 2>/dev/null && grep -q 'DisplayServer=x11' /etc/sddm.conf.d/30-x11-session.conf 2>/dev/null").
dm_session_check(lightdm,
    "grep -q 'user-session=plasmax11' /etc/lightdm/lightdm.conf.d/50-session.conf 2>/dev/null").

dm_session_fix(gdm, Cmd) :-
    run_as_user(User),
    format(atom(Cmd),
        "U=$(id -u ~w) && busctl call org.freedesktop.Accounts /org/freedesktop/Accounts/User$U org.freedesktop.Accounts.User SetSession s plasmax11 && busctl call org.freedesktop.Accounts /org/freedesktop/Accounts/User$U org.freedesktop.Accounts.User SetXSession s plasmax11",
        [User]).
dm_session_fix(sddm, Cmd) :-
    run_as_user(User),
    format(atom(Cmd),
        "mkdir -p /etc/sddm.conf.d /var/lib/sddm && rm -f /etc/sddm.conf.d/99-force-x11.conf && { test -f /etc/sddm.conf.d/20-kubuntu.conf && sed -i 's/^Session=plasma$/Session=plasmax11/' /etc/sddm.conf.d/20-kubuntu.conf || printf '[Autologin]\\nSession=plasmax11\\n' > /etc/sddm.conf.d/20-kubuntu.conf; } && printf '[General]\\nDisplayServer=x11\\n' > /etc/sddm.conf.d/30-x11-session.conf && printf '[Last]\\nUser=~w\\nSession=plasmax11.desktop\\n' > /var/lib/sddm/state.conf && chmod 600 /var/lib/sddm/state.conf && (chown sddm:sddm /var/lib/sddm/state.conf 2>/dev/null || true)",
        [User]).
dm_session_fix(lightdm,
    "mkdir -p /etc/lightdm/lightdm.conf.d && printf '[Seat:*]\\nuser-session=plasmax11\\n' > /etc/lightdm/lightdm.conf.d/50-session.conf").

%% saved_session_is_x11 — checked where the ACTIVE display manager reads it.
saved_session_is_x11 :-
    active_display_manager(DM),
    dm_session_check(DM, Check),
    shell_ok(Check).

%% session_rule(+Name, ?FixCmd) — FixCmd targets the active display manager.
session_rule(wayland_x11_mismatch, Cmd) :-
    active_display_manager(DM),
    dm_session_fix(DM, Cmd).

%% hardening_check(+Name, +CheckShell, +FixCmd)
hardening_check(inotify_limits,
    "test -f /etc/sysctl.d/90-inotify.conf",
    "printf 'fs.inotify.max_user_watches=524288\\nfs.inotify.max_queued_events=131072\\nfs.inotify.max_user_instances=4096\\n' > /etc/sysctl.d/90-inotify.conf && sysctl -p /etc/sysctl.d/90-inotify.conf").
hardening_check(no_snapd,
    "test -f /etc/apt/preferences.d/no-snapd",
    "snap list --all 2>/dev/null | awk 'NR>1{print $1}' | xargs -r snap remove --purge 2>/dev/null || true; apt-get purge -y snapd 2>/dev/null || true; rm -rf /snap /var/snap /var/lib/snapd /var/cache/snapd; printf 'Package: snapd\\nPin: release a=*\\nPin-Priority: -1\\n' > /etc/apt/preferences.d/no-snapd").
hardening_check(suspend_masked,
    "test -L /etc/systemd/system/suspend.target",
    "systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target").
hardening_check(parport_blacklisted,
    "test -f /etc/modprobe.d/blacklist-parport.conf",
    "printf 'blacklist lp\\nblacklist ppdev\\nblacklist parport_pc\\nblacklist parport\\n' > /etc/modprobe.d/blacklist-parport.conf").
hardening_check(grub_timeout,
    "test -f /etc/default/grub.d/99-timeout.cfg",
    "mkdir -p /etc/default/grub.d && printf 'GRUB_TIMEOUT=3\\n' > /etc/default/grub.d/99-timeout.cfg && update-grub").
%% masking packagekit leaves the symlink that doubles as the sentinel.
hardening_check(debloat,
    "test -L /etc/systemd/system/packagekit.service",
    "rm -f /etc/apt/sources.list.d/jammy-backports.list; systemctl disable --now ollama touchegg 2>/dev/null || true; apt-get purge -y ollama touchegg cockpit-packagekit 2>/dev/null || true; rm -f /usr/local/bin/ollama /etc/systemd/system/ollama.service; systemctl stop packagekit 2>/dev/null || true; systemctl mask packagekit; mkdir -p /etc/PackageKit; dpkg-divert --divert /etc/PackageKit/20packagekit.distrib --rename /etc/apt/apt.conf.d/20packagekit 2>/dev/null || true; systemctl daemon-reload").
hardening_check(pam_sss_absent,
    "! grep -rq pam_sss /etc/pam.d/ 2>/dev/null",
    "grep -rl pam_sss /etc/pam.d/ 2>/dev/null | xargs -r sed -i '/pam_sss/d'").
%% NVIDIA-gated checks: no GPU, no fact — the check never appears.
hardening_check(nouveau_blacklisted, Check, Fix) :-
    has_nvidia,
    Check = "test -f /etc/modprobe.d/blacklist-nouveau.conf",
    Fix = "printf 'blacklist nouveau\\nblacklist lbm-nouveau\\noptions nouveau modeset=0\\n' > /etc/modprobe.d/blacklist-nouveau.conf && update-initramfs -u".
hardening_check(nvidia_power, Check, Fix) :-
    has_nvidia,
    Check = "test -f /etc/modprobe.d/nvidia-power.conf",
    Fix = "printf 'options nvidia NVreg_PreserveVideoMemoryAllocations=1\\noptions nvidia NVreg_TemporaryFilePath=/tmp\\n' > /etc/modprobe.d/nvidia-power.conf".
%% BMC policy: enable IPMI where a controller exists, mask it where none does.
%% dmidecode needs root; the /sys probe works for any user once ipmi_si has
%% auto-loaded from SMBIOS, so unprivileged runs still see a live BMC.
has_bmc :- shell_ok("ls /sys/class/ipmi/ipmi* 2>/dev/null | grep -q ipmi"), !.
has_bmc :- shell_ok("dmidecode -t 38 2>/dev/null | grep -q 'IPMI Device Information'").
hardening_check(openipmi_policy, Check, Fix) :-
    ( has_bmc
    ->  Check = "systemctl is-enabled --quiet openipmi 2>/dev/null",
        Fix   = "apt install -y openipmi && systemctl enable --now openipmi"
    ;   Check = "test -L /etc/systemd/system/openipmi.service",
        Fix   = "systemctl mask openipmi; apt-get purge -y openipmi 2>/dev/null || true"
    ).
%% PLX ASPM pair. pcie_aspm=off is necessary but not sufficient on this board:
%% firmware keeps ASPM control (_OSC denies the OS), so the setpci service
%% clears the L1 bits on every switch port at boot.
%% Matches both the PEX 8749 bench switch (vendor PLX) and the target
%% PEX88048 (vendor Broadcom / LSI).
has_plx_switch :- shell_ok("lspci 2>/dev/null | grep -qiE '(PLX|Broadcom).*PEX ?8'").
hardening_check(plx_aspm_grub, Check, Fix) :-
    has_plx_switch,
    Check = "test -f /etc/default/grub.d/99-pcie-aspm.cfg",
    Fix = "mkdir -p /etc/default/grub.d && printf 'GRUB_CMDLINE_LINUX_DEFAULT=\"$GRUB_CMDLINE_LINUX_DEFAULT pcie_aspm=off\"\\n' > /etc/default/grub.d/99-pcie-aspm.cfg && update-grub".
hardening_check(plx_aspm_service, Check, Fix) :-
    has_plx_switch,
    Check = "test -f /etc/systemd/system/disable-gpu-aspm.service",
    Fix = "UP=$(lspci -D 2>/dev/null | grep -iE '(PLX|Broadcom).*PEX ?8' | awk '{print $1; exit}') && GPU=$(lspci -D 2>/dev/null | awk '/VGA.*NVIDIA/{print $1}') && DS=$(ls /sys/bus/pci/devices/$UP/ 2>/dev/null | grep '^0000:' || true) && { printf '%s\\n' '[Unit]' 'Description=Clear PCIe ASPM L1 on all PLX switch ports (upstream + downstream + GPU)' 'After=multi-user.target' '' '[Service]' 'Type=oneshot' 'RemainAfterExit=yes'; for b in $UP $DS $GPU; do echo \"ExecStart=/usr/bin/setpci -s $b CAP_EXP+0x10.w=0:3\"; done; printf '%s\\n' '' '[Install]' 'WantedBy=multi-user.target'; } > /etc/systemd/system/disable-gpu-aspm.service && rm -f /usr/local/sbin/disable-gpu-aspm && systemctl daemon-reload && systemctl enable --now disable-gpu-aspm.service".

%% user_tool(+Name, +SentinelRelToHome, +InstallCmd)
user_tool(uv,     '.local/bin/uv',     'curl -LsSf https://astral.sh/uv/install.sh | sh').
user_tool(kaggle, '.local/bin/kaggle', 'uv tool install kaggle').
user_tool(gemini, '.local/bin/gemini', 'npm install --prefix ~/.local -g @google/gemini-cli').

%% user_tool_deps(+Name, +Deps): explicit dep override (default: [user_tool_ready(uv)]).
user_tool_deps(uv,     [internet_ok]).
user_tool_deps(gemini, [internet_ok, packages_installed]).

%% service_check(+Name, +CheckShell, +FixCmd)
%% Root-scope services, units and daemon configuration. Conditional entries
%% are rule clauses whose body fails when the check is not applicable — the
%% check then simply doesn't exist on this machine.
service_check(cockpit_socket,
    "systemctl is-enabled --quiet cockpit.socket",
    "systemctl enable --now cockpit.socket").
service_check(captive_portal,
    "test -f /etc/NetworkManager/conf.d/captive-portal.conf",
    "mkdir -p /etc/NetworkManager/conf.d && printf '[connectivity]\\nuri=http://nmcheck.gnome.org/check_network_status.txt\\nresponse=NetworkManager is online\\ninterval=60\\n' > /etc/NetworkManager/conf.d/captive-portal.conf && systemctl reload NetworkManager").
%% LAN subnet is resolved at apply time on the machine being fixed.
service_check(ssh_lan_password,
    "test -f /etc/ssh/sshd_config.d/lan-password.conf",
    "SUBNET=$(ip route | awk '/proto kernel/ && !/wl|ww|lo|vir|br-|docker/{print $1; exit}') && mkdir -p /etc/ssh/sshd_config.d && printf 'PasswordAuthentication no\\n\\nMatch Address %s,127.0.0.1\\n\\tPasswordAuthentication yes\\n' \"$SUBNET\" > /etc/ssh/sshd_config.d/lan-password.conf && (systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true)").
%% Printer: applicable when already configured (verify) or currently
%% discoverable on the LAN (configure) — otherwise skipped, not failed.
service_check(printer_lpadmin, Check, Fix) :-
    once(( shell_ok("lpstat -p hp-laserjet-mfp-2604sdw")
         ; shell_ok("avahi-browse -t -r -p _ipp._tcp 2>/dev/null | grep -q 2604sdw")
         )),
    Check = "lpstat -p hp-laserjet-mfp-2604sdw >/dev/null 2>&1",
    Fix = "IP=$(avahi-browse -t -r -p _ipp._tcp 2>/dev/null | awk -F';' '/^=/ && /2604sdw/{print $8; exit}') && test -n \"$IP\" && lpadmin -p hp-laserjet-mfp-2604sdw -E -v \"ipp://$IP/ipp/print\" -m everywhere && lpoptions -d hp-laserjet-mfp-2604sdw".
%% Device-activated mount, NOT an automount: /mnt/backup is a plain empty dir
%% when the SN8100 is absent (no file-picker hang) and mounts on hotplug.
%% Only applicable while the labelled device is visible.
service_check(backup_mount, Check, Fix) :-
    shell_ok("test -e /dev/disk/by-label/backup"),
    Check = "test -f /etc/systemd/system/mnt-backup.mount && test -f /etc/systemd/system/mnt-backup-chmod.service",
    Fix = "mkdir -p /mnt/backup && sed -i '\\|/mnt/backup|d' /etc/fstab && printf '%s\\n' '[Unit]' 'Description=NVMe backup drive (SN8100)' '' '[Mount]' 'What=/dev/disk/by-label/backup' 'Where=/mnt/backup' 'Type=ext4' 'Options=defaults,noatime,nofail' '' '[Install]' 'WantedBy=dev-disk-by\\x2dlabel-backup.device' > /etc/systemd/system/mnt-backup.mount && printf '%s\\n' '[Unit]' 'Description=Set /mnt/backup permissions on mount' 'After=mnt-backup.mount' 'Requires=mnt-backup.mount' '' '[Service]' 'Type=oneshot' 'ExecStart=/bin/chmod 1777 /mnt/backup' 'RemainAfterExit=yes' '' '[Install]' 'WantedBy=mnt-backup.mount' > /etc/systemd/system/mnt-backup-chmod.service && systemctl daemon-reload && systemctl enable mnt-backup.mount mnt-backup-chmod.service".
service_check(syncthing_service, Check, Fix) :-
    run_as_user(User), user_home(Home),
    format(atom(Check),
        "test -e ~w/.config/systemd/user/default.target.wants/syncthing.service && test -e /var/lib/systemd/linger/~w",
        [Home, User]),
    format(atom(Fix),
        "loginctl enable-linger ~w && runuser -u ~w -- env XDG_RUNTIME_DIR=/run/user/$(id -u ~w) systemctl --user enable --now syncthing",
        [User, User, User]).
%% GUI remote access: bind Syncthing's web UI to 0.0.0.0 with auth. Password
%% comes from SYNCTHING_GUI_PASS at apply time (default change-me).
service_check(syncthing_gui_remote, Check, Fix) :-
    run_as_user(User), user_home(Home),
    format(atom(Check),
        "grep -hq '0\\.0\\.0\\.0:8384' '~w/.config/syncthing/config.xml' '~w/.local/state/syncthing/config.xml' 2>/dev/null",
        [Home, Home]),
    format(atom(Fix),
        "KEY=$(grep -h '<apikey>' '~w/.config/syncthing/config.xml' '~w/.local/state/syncthing/config.xml' 2>/dev/null | sed -n 's:.*<apikey>\\(.*\\)</apikey>.*:\\1:p' | head -1) && for i in $(seq 30); do curl -sf http://localhost:8384/rest/noauth/health >/dev/null 2>&1 && break || sleep 1; done && curl -sS -X PATCH http://localhost:8384/rest/config/gui -H \"X-API-Key: $KEY\" -H 'Content-Type: application/json' -d '{\"address\":\"0.0.0.0:8384\",\"user\":\"~w\",\"password\":\"'\"${SYNCTHING_GUI_PASS:-change-me}\"'\"}'",
        [Home, Home, User]).
%% Tailscale login — only fixable when TS_AUTHKEY is in the environment;
%% without it diagnose(services) emits a WARN instead.
service_check(tailscale_up, Check, Fix) :-
    getenv('TS_AUTHKEY', Key),
    Check = "tailscale status 2>/dev/null | grep -q '^100\\.'",
    format(atom(Fix),
        "tailscale up --authkey \"~w\" --accept-routes --accept-dns", [Key]).
%% claude-safe: sandboxed Claude Code as a system user. Three checks chained
%% by single-level deps (see service_deps): binary → user → sudoers.
service_check(claude_bin,
    "test -x /usr/local/bin/claude",
    "npm install -g @anthropic-ai/claude-code").
service_check(ai_agent_user, "id ai-agent >/dev/null 2>&1", Fix) :-
    user_home(Home),
    format(atom(Fix),
        "adduser --system --group --shell /bin/false --disabled-login --home /home/ai-agent ai-agent && chmod 700 /home/ai-agent && setfacl -m u:ai-agent:x ~w && { test -f ~w/.claude/.credentials.json && setfacl -m u:ai-agent:r ~w/.claude/.credentials.json || true; }",
        [Home, Home, Home]).
service_check(claude_safe_sudoers,
    "test -f /etc/sudoers.d/50-claude-safe",
    "printf '%s\\n' '# Allow any user to run claude as ai-agent without password, forwarding CLAUDE_CONFIG_DIR' 'ALL ALL=(ai-agent) NOPASSWD: SETENV: /usr/local/bin/claude' > /etc/sudoers.d/50-claude-safe && chmod 440 /etc/sudoers.d/50-claude-safe").

%% service_deps(+Name, +Deps): explicit dep override (default: [packages_installed]).
service_deps(claude_bin,           [packages_installed]).
service_deps(ai_agent_user,        [service_ready(claude_bin)]).
service_deps(claude_safe_sudoers,  [service_ready(ai_agent_user)]).
service_deps(syncthing_gui_remote, [service_ready(syncthing_service)]).

%% ── User configuration ───────────────────────────────────────────────────────
%% user_config(+Name, +CheckShell, +FixCmd)
%% Desktop/user-scope state. Checks run as the invoking user; fixes are
%% emitted wrapped in `sudo -u <user>` with the session bus environment
%% (gen_user_config_rules), inside a quoted heredoc so any quoting inside
%% the fix survives the root pipe unmodified.
:- discontiguous user_config/3.

project_dir(D) :- user_home(H), atom_concat(H, '/Desktop/Projects/Crucible', D).

user_config(xsessionrc, Check, Fix) :-
    user_home(Home),
    format(atom(Check),
        "grep -q 'import-environment DISPLAY' ~w/.xsessionrc 2>/dev/null", [Home]),
    format(atom(Fix),
        "printf '%s\\n' 'systemctl --user import-environment DISPLAY XAUTHORITY 2>/dev/null || true' > ~w/.xsessionrc",
        [Home]).
%% Whole-desktop truly-black scheme derived from BreezeDark (keeps its light
%% foregrounds), every background forced to #000000.
user_config(crucible_black, Check, Fix) :-
    user_home(Home),
    format(atom(Check),
        "test -f ~w/.local/share/color-schemes/CrucibleBlack.colors", [Home]),
    format(atom(Fix),
        "mkdir -p ~w/.local/share/color-schemes && sed -E 's/^(BackgroundNormal|BackgroundAlternate|activeBackground|inactiveBackground)=.*/\\1=0,0,0/; s/^Name=.*/Name=Crucible Black/; s/^ColorScheme=.*/ColorScheme=CrucibleBlack/' /usr/share/color-schemes/BreezeDark.colors > ~w/.local/share/color-schemes/CrucibleBlack.colors && (plasma-apply-colorscheme CrucibleBlack 2>/dev/null || true)",
        [Home, Home]).
user_config(dolphin_previews, Check,
    "kwriteconfig5 --file kdeglobals --group 'KFileDialog Settings' --key 'Show Preview' true") :-
    user_home(Home),
    format(atom(Check),
        "grep -q '^Show Preview=true' ~w/.config/kdeglobals 2>/dev/null", [Home]).
%% Screen-space: maximized windows lose their titlebar (the top panel's
%% application-title-bar widget takes over its role).
user_config(kwin_borderless, Check,
    "kwriteconfig6 --file kwinrc --group Windows --key BorderlessMaximizedWindows true && (gdbus call --session --dest org.kde.KWin --object-path /KWin --method org.kde.KWin.reconfigure >/dev/null 2>&1 || true)") :-
    user_home(Home),
    format(atom(Check),
        "grep -q '^BorderlessMaximizedWindows=true' ~w/.config/kwinrc 2>/dev/null", [Home]).
user_config(kwallet_disabled, Check, Fix) :-
    user_home(Home),
    format(atom(Check), "test -f ~w/.config/kwalletrc", [Home]),
    format(atom(Fix),
        "printf '[Wallet]\\nEnabled=false\\nFirst Use=false\\n' > ~w/.config/kwalletrc",
        [Home]).
user_config(terminator_black, Check, Fix) :-
    user_home(Home),
    format(atom(Check), "test -f ~w/.config/terminator/config", [Home]),
    format(atom(Fix),
        "mkdir -p ~w/.config/terminator && printf '%s\\n' '[profiles]' '  [[default]]' '    background_color = \"#000000\"' '    background_type = solid' '    foreground_color = \"#ffffff\"' > ~w/.config/terminator/config",
        [Home, Home]).
user_config(bashrc_make_completion, Check, Fix) :-
    user_home(Home),
    format(atom(Check),
        "grep -q 'bash-completion/completions/make' ~w/.bashrc 2>/dev/null", [Home]),
    format(atom(Fix),
        "printf 'source %s\\n' '/usr/share/bash-completion/completions/make' >> ~w/.bashrc",
        [Home]).
%% One autostart entry per connected output (kscreen-doctor enable only —
%% KScreen keeps the arrangement). Snapshot-free: the loop re-derives the
%% output list at apply time.
user_config(kscreen_autostart, Check, Fix) :-
    user_home(Home),
    format(atom(Check),
        "kscreen-doctor --json 2>/dev/null | jq -r '.outputs[] | select(.connected) | .name' | { while read -r o; do test -f ~w/.config/autostart/enable-$o.desktop || exit 1; done; }",
        [Home]),
    format(atom(Fix),
        "mkdir -p ~w/.config/autostart && kscreen-doctor --json 2>/dev/null | jq -r '.outputs[] | select(.connected) | .name' | while read -r o; do printf '[Desktop Entry]\\nType=Application\\nName=Enable monitor %s\\nExec=kscreen-doctor output.%s.enable\\nOnlyShowIn=KDE;\\n' \"$o\" \"$o\" > ~w/.config/autostart/enable-$o.desktop; kscreen-doctor output.$o.enable >/dev/null 2>&1 || true; done",
        [Home, Home]).
%% SSH: key → authorized for localhost → crucible host entry (Tailscale IPv4
%% via the crucible.dns.army A record; AddressFamily inet ignores the AAAA).
user_config(ssh_key, Check, Fix) :-
    user_home(Home),
    format(atom(Check), "test -f ~w/.ssh/id_ed25519", [Home]),
    format(atom(Fix),
        "mkdir -p ~w/.ssh && chmod 700 ~w/.ssh && ssh-keygen -t ed25519 -f ~w/.ssh/id_ed25519 -N ''",
        [Home, Home, Home]).
user_config(ssh_authorized_keys, Check, Fix) :-
    user_home(Home),
    format(atom(Check),
        "test -f ~w/.ssh/authorized_keys && grep -qf ~w/.ssh/id_ed25519.pub ~w/.ssh/authorized_keys 2>/dev/null",
        [Home, Home, Home]),
    format(atom(Fix),
        "cat ~w/.ssh/id_ed25519.pub >> ~w/.ssh/authorized_keys && chmod 600 ~w/.ssh/authorized_keys",
        [Home, Home, Home]).
user_config(ssh_config_crucible, Check, Fix) :-
    user_home(Home),
    format(atom(Check),
        "grep -q '^Host crucible' ~w/.ssh/config 2>/dev/null", [Home]),
    format(atom(Fix),
        "printf '%s\\n' 'Host crucible' '    HostName crucible.dns.army' '    AddressFamily inet' '    User m' '    IdentityFile ~w/.ssh/id_ed25519' '    ServerAliveInterval 60' >> ~w/.ssh/config && chmod 600 ~w/.ssh/config",
        [Home, Home, Home]).
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
%% KDE Store widgets — repo and package subdir, keyed by plugin id.
kde_widget('com.github.antroids.application-title-bar',
           'https://github.com/antroids/application-title-bar', package).
kde_widget('Plasma.Flex.Hub',
           'https://github.com/zayronxio/Plasma.Flex.Hub', '.').
kde_widget('com.github.chrtall.kppleMenu',
           'https://github.com/ChrTall/kppleMenu', package).
user_config(widget(Id), Check, Fix) :-
    kde_widget(Id, Repo, Sub),
    user_home(Home),
    format(atom(Check),
        "test -f ~w/.local/share/plasma/plasmoids/~w/metadata.json", [Home, Id]),
    format(atom(Fix),
        "rm -rf '/tmp/~w' && git clone --depth 1 ~w '/tmp/~w' && kpackagetool6 -t Plasma/Applet -i '/tmp/~w/~w'; rm -rf '/tmp/~w'",
        [Id, Repo, Id, Id, Sub, Id]).
%% Panels. Top: kppleMenu | title widget | GLOBAL MENU (appmenu) | spacer |
%% weather (DWD Berlin-Alexanderplatz) | tray | Flex Hub | clock. The JS is
%% single-quote-free by construction — the gdbus call wraps it in single
%% quotes. Bottom: auto-hide dock (kickoff + dashboard + icontasks).
top_panel_js(JS) :-
    atomic_list_concat([
        'var p = new Panel;',
        'p.location = "top";',
        'p.addWidget("com.github.chrtall.kppleMenu");',
        'var t = p.addWidget("com.github.antroids.application-title-bar");',
        't.currentConfigGroup = ["Appearance"];',
        't.writeConfig("widgetElements", ["windowTitle"]);',
        't.writeConfig("overrideElementsMaximized", true);',
        't.writeConfig("widgetElementsMaximized", ["windowCloseButton", "windowMinimizeButton", "windowMaximizeButton", "windowTitle"]);',
        't.writeConfig("windowTitleSource", 0);',
        't.writeConfig("windowTitleSourceMaximized", 0);',
        't.writeConfig("windowTitleFontSize", 10);',
        't.writeConfig("windowTitleUndefined", "Plasma");',
        'p.addWidget("org.kde.plasma.appmenu");',
        'p.addWidget("org.kde.plasma.panelspacer");',
        'var w = p.addWidget("org.kde.plasma.weather");',
        'w.currentConfigGroup = ["WeatherStation"];',
        'w.writeConfig("provider", "dwd");',
        'w.writeConfig("placeInfo", "Berlin-Alex.|10389");',
        'w.writeConfig("placeDisplayName", "Berlin-Alex.");',
        'w.currentConfigGroup = ["Appearance"];',
        'w.writeConfig("showTemperatureInCompactMode", true);',
        'var s = p.addWidget("org.kde.plasma.systemtray");',
        's.currentConfigGroup = ["General"];',
        's.writeConfig("extraItems", "");',
        's.writeConfig("knownItems", ["org.kde.plasma.weather"]);',
        'p.addWidget("Plasma.Flex.Hub");',
        'var c = p.addWidget("org.kde.plasma.digitalclock");',
        'c.currentConfigGroup = ["Appearance"];',
        'c.writeConfig("dateDisplayFormat", "BesideTime");',
        'c.writeConfig("use24hFormat", 2);',
        'c.writeConfig("autoFontAndSize", false);',
        'c.writeConfig("fontSize", 14);',
        'c.writeConfig("dateFormat", "custom");',
        'c.writeConfig("customDateFormat", "dd.MM.yy |");'
    ], ' ', JS).
bottom_panel_js(JS) :-
    atomic_list_concat([
        'var d = new Panel;',
        'd.location = "bottom";',
        'd.height = 60;',
        'd.hiding = "autohide";',
        'd.lengthMode = "fit";',
        'd.floating = false;',
        'd.opacity = "opaque";',
        'd.addWidget("org.kde.plasma.kickoff");',
        'd.addWidget("org.kde.plasma.applicationdashboard");',
        'd.addWidget("org.kde.plasma.icontasks");'
    ], ' ', JS).
user_config(top_panel, Check, Fix) :-
    user_home(Home),
    format(atom(Check),
        "grep -q 'location=3' ~w/.config/plasma-org.kde.plasma.desktop-appletsrc 2>/dev/null",
        [Home]),
    top_panel_js(JS),
    format(atom(Fix),
        "gdbus call --session --dest org.kde.plasmashell --object-path /PlasmaShell --method org.kde.PlasmaShell.evaluateScript '~w' >/dev/null",
        [JS]).
user_config(bottom_panel, Check, Fix) :-
    user_home(Home),
    format(atom(Check),
        "grep -q 'location=4' ~w/.config/plasma-org.kde.plasma.desktop-appletsrc 2>/dev/null",
        [Home]),
    bottom_panel_js(JS),
    format(atom(Fix),
        "gdbus call --session --dest org.kde.plasmashell --object-path /PlasmaShell --method org.kde.PlasmaShell.evaluateScript '~w' >/dev/null",
        [JS]).
%% Reference PDFs (the SN8100 datasheet has no stable public URL — excluded).
reference_pdf('References/Motherboard/E3C256D4I-2T.pdf',
    'https://download.asrock.com/Manual/E3C256D4I-2T.pdf').
reference_pdf('References/Motherboard/ASUS-Prime-X299-A-II.pdf',
    'https://dlcdnets.asus.com/pub/ASUS/mb/LGA2066/PRIME_X299-A_II/E15936_PRIME_X299-A_II_UM_V2_WEB.pdf').
reference_pdf('References/Case/ENTHOO-PRO-II/Enthoo_Pro2_Manual_v1.1.pdf',
    'https://phanteks.com/manuals/Enthoo_Pro2_Manual_v1.1.pdf').
reference_pdf('References/Storage/MB111VP-B/MB111VP_B_Manual.pdf',
    'https://global.icydock.com/vancheerfile/files/installation_guide/MB111VP_B_Manual.pdf').
reference_pdf('References/Storage/MB705M2P-B/MB705M2P-B_Manual.pdf',
    'https://www.icydock.com/Installation%20Guide/MB705M2P-B-webpage_manual.pdf').
user_config(reference_pdf(Rel), Check, Fix) :-
    reference_pdf(Rel, URL),
    project_dir(Proj),
    format(atom(Check), "test -s '~w/~w'", [Proj, Rel]),
    format(atom(Fix),
        "mkdir -p \"$(dirname '~w/~w')\" && curl -fL -o '~w/~w' '~w'",
        [Proj, Rel, Proj, Rel, URL]).

%% user_config_deps(+Name, +Deps): explicit dep override (default: []).
user_config_deps(vscode_workspace_settings, [packages_installed]).
user_config_deps(vscode_ext(_),             [packages_installed]).
user_config_deps(vscode_opencode_zen,       [packages_installed]).
user_config_deps(ssh_authorized_keys, [user_config_applied(ssh_key)]).
user_config_deps(ssh_config_crucible, [user_config_applied(ssh_key)]).
user_config_deps(top_panel,
    [user_config_applied(widget('com.github.antroids.application-title-bar')),
     user_config_applied(widget('Plasma.Flex.Hub')),
     user_config_applied(widget('com.github.chrtall.kppleMenu')),
     packages_installed]).
user_config_deps(bottom_panel, [packages_installed]).
user_config_deps(reference_pdf(_), [internet_ok]).

%% ── Shell helper ─────────────────────────────────────────────────────────────

shell_ok(Cmd) :-
    atomic_list_concat([Cmd, '>/dev/null 2>&1'], ' ', Silent),
    shell(Silent, 0).

%% ── Diagnostics ──────────────────────────────────────────────────────────────

diagnose(internet) :-
    section('01', 'INTERNET'),
    ( shell_ok("ip link show | grep -v lo | grep -q 'state UP'")
    -> assert(satisfied(internet_ok)),
       post_ok(internet, ethernet, 'link up')
    ;  assert(failed(internet, ethernet, no_link)),
       post_fail(internet, ethernet, 'no link — check cable')
    ),
    ( shell_ok("resolvectl status 2>/dev/null | grep -q 'DNS Servers'")
    -> post_ok(internet, dns, configured)
    ;  post_warn(internet, dns, 'not configured via resolvectl')
    ).

diagnose(packages) :-
    section('02', 'PACKAGES'),
    forall(binary_pkg(Bin, Pkg), (
        ( access_file(Bin, exist)
        -> post_ok(packages, Pkg, installed)
        ;  assert(failed(packages, Bin, missing)),
           post_fail(packages, Pkg, missing)
        )
    )),
    forall(opt_install(Name, Bin, _), (
        ( access_file(Bin, exist)
        -> post_ok(packages, Name, installed)
        ;  assert(failed(packages, Bin, missing)),
           post_fail(packages, Name, missing)
        )
    )).

diagnose(repos) :-
    findall(RepoName,
        ( failed(packages, Bin, missing), binary_pkg(Bin, Pkg), pkg_repo(Pkg, RepoName) ),
        Repos0),
    sort(Repos0, Repos),
    ( Repos = [] -> true
    ;  section('03', 'REPOS'),
       forall(member(RepoName, Repos), (
           apt_repo(RepoName, CheckCmd, _),
           ( shell_ok(CheckCmd)
           -> assert(satisfied(repo_ready(RepoName))),
              post_ok(repos, RepoName, present)
           ;  assert(failed(repos, RepoName, missing)),
              post_fail(repos, RepoName, missing)
           )
       ))
    ).

diagnose(hardening) :-
    section('04', 'HARDENING'),
    forall(hardening_check(Name, CheckCmd, _), (
        ( shell_ok(CheckCmd)
        -> post_ok(hardening, Name, applied)
        ;  assert(failed(hardening, Name, missing)),
           post_fail(hardening, Name, missing)
        )
    )).

diagnose(patches) :-
    section('05', 'PATCHES'),
    forall(config_patch(Name, Guard, CheckCmd, _), (
        ( access_file(Guard, exist)
        -> ( shell_ok(CheckCmd)
           -> post_ok(patches, Name, applied)
           ;  assert(failed(patches, Name, missing)),
              post_fail(patches, Name, missing)
           )
        ;  true
        )
    )).

%% Session health is judged by processes, not env vars: GDM's Wayland
%% greeter leaks XDG_SESSION_TYPE=wayland into the user environment even
%% when the session it launched is genuine X11 Plasma.
diagnose(desktop) :-
    section('06', 'DESKTOP'),
    ( shell_ok("pgrep -x startplasma-x11"), shell_ok("pgrep -x Xorg")
    ->  post_ok(desktop, session_type, 'plasma-x11'),
        % This process inherits the invoking terminal's environment: if it
        % still carries Wayland vars, GUI apps launched from that terminal
        % will pick the Wayland backend and die. No root fix exists for an
        % already-running shell — the terminal must be replaced.
        ( ( getenv('WAYLAND_DISPLAY', _) ; getenv('XDG_SESSION_TYPE', wayland) )
        ->  post_warn(desktop, terminal_env,
                'this terminal carries stale Wayland vars — close it and launch apps from a fresh one')
        ;   post_ok(desktop, terminal_env, clean)
        )
    ;   shell_ok("pgrep -x kwin_wayland")
    ->  post_ok(desktop, session_type, 'plasma-wayland')
    ;   shell_ok("pgrep -x kwin_x11")
    ->  % kwin_x11 without real Xorg: Wayland session fell back — Alt+Tab broken
        ( saved_session_is_x11
        ->  assert(satisfied(session_fixed(wayland_x11_mismatch))),
            post_warn(desktop, session_type,
                'X11 default recorded — log out and log back in to Plasma (X11)')
        ;   assert(failed(desktop, session_type, wayland_x11_mismatch)),
            post_fail(desktop, session_type,
                'kwin_x11 running without Xorg — broken Wayland fallback, Alt+Tab broken')
        )
    ;   post_ok(desktop, session_type, 'no plasma session')
    ).

diagnose(user_tools) :-
    section('07', 'USER TOOLS'),
    getenv('HOME', Home),
    forall(user_tool(Name, Rel, _), (
        atomic_list_concat([Home, '/', Rel], Sentinel),
        ( access_file(Sentinel, exist)
        -> post_ok(user_tools, Name, installed),
           assert(satisfied(user_tool_ready(Name)))
        ;  assert(failed(user_tools, Name, missing)),
           post_fail(user_tools, Name, missing)
        )
    )).

diagnose(services) :-
    section('08', 'SERVICES'),
    forall(service_check(Name, CheckCmd, _), (
        ( shell_ok(CheckCmd)
        -> post_ok(services, Name, applied),
           assert(satisfied(service_ready(Name)))
        ;  assert(failed(services, Name, missing)),
           post_fail(services, Name, missing)
        )
    )),
    % Tailscale login without TS_AUTHKEY: not fixable, but worth naming.
    ( \+ service_check(tailscale_up, _, _),
      \+ shell_ok("tailscale status 2>/dev/null | grep -q '^100\\.'")
    -> post_warn(services, tailscale_up,
           'not logged in — export TS_AUTHKEY to authenticate')
    ;  true
    ).

diagnose(user_config) :-
    section('10', 'USER CONFIG'),
    forall(user_config(Name, CheckCmd, _), (
        ( shell_ok(CheckCmd)
        -> post_ok(user_config, Name, applied),
           assert(satisfied(user_config_applied(Name)))
        ;  assert(failed(user_config, Name, missing)),
           post_fail(user_config, Name, missing)
        )
    )).

%% Which options won the backtracking, and are the losers standby-ready?
diagnose(selection) :-
    section('09', 'SELECTION'),
    ( active_display_manager(Active) -> true ; Active = none ),
    ( select(display_manager, Best)  -> true ; Best = none ),
    format(atom(DmDetail), 'active ~w, preferred ~w', [Active, Best]),
    post_ok(selection, display_manager, DmDetail),
    forall(( candidate(display_manager, DM), dm_installed(DM) ), (
        ( dm_session_check(DM, Check), shell_ok(Check)
        -> post_ok(selection, DM, 'standby-ready (plasmax11 recorded)')
        ;  assert(failed(selection, DM, standby)),
           post_fail(selection, DM, 'plasmax11 not recorded — standby fix queued')
        )
    )),
    ( select(session, S)
    -> post_ok(selection, session, S)
    ;  post_warn(selection, session, 'no viable session candidate')
    ),
    forall(candidate(session, Sess), (
        ( viable(session, Sess) -> true
        ;  Sess == lomiri, lomiri_crash_evidence
        -> lomiri_demotion_reason(Why),
           post_warn(selection, lomiri, Why)
        ;  post_warn(selection, Sess, 'not viable — session file missing')
        )
    )).

%% ── Rule generation ──────────────────────────────────────────────────────────

generate_rules :-
    gen_download_rules,
    gen_repo_rules,
    gen_package_rule,
    gen_opt_install_rules,
    gen_desktop_fix_rules,
    gen_patch_rules,
    gen_session_fix_rules,
    gen_hardening_rules,
    gen_service_rules,
    gen_selection_rules,
    gen_user_tool_rules,
    gen_user_config_rules,
    gen_top_rule.

%% Fixes run as the real user with their session bus, via a quoted heredoc
%% so quoting inside the raw fix survives the root pipe unmodified.
gen_user_config_rules :-
    run_as_user(User),
    forall(
        failed(user_config, Name, missing),
        ( user_config(Name, _, RawCmd),
          format(atom(Cmd),
              "sudo -u ~w XDG_RUNTIME_DIR=/run/user/$(id -u ~w) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u ~w)/bus bash <<'POST_USER_EOF'~n~w~nPOST_USER_EOF",
              [User, User, User, RawCmd]),
          ( user_config_deps(Name, Deps) -> true ; Deps = [] ),
          assert(build_rule(user_config_applied(Name), Deps, [Cmd]))
        )
    ).

gen_selection_rules :-
    forall(
        ( failed(selection, DM, standby), dm_session_fix(DM, FixCmd) ),
        assert(build_rule(dm_standby(DM), [], [FixCmd]))
    ).

gen_service_rules :-
    forall(
        ( failed(services, Name, missing), service_check(Name, _, FixCmd) ),
        ( ( service_deps(Name, Deps) -> true ; Deps = [packages_installed] ),
          assert(build_rule(service_ready(Name), Deps, [FixCmd]))
        )
    ).

gen_opt_install_rules :-
    forall(
        ( failed(packages, Bin, missing), opt_install(Name, Bin, Cmd) ),
        ( ( opt_install_deps(Name, Deps) -> true ; Deps = [internet_ok] ),
          assert(build_rule(opt_installed(Name), Deps, [Cmd]))
        )
    ).

gen_download_rules :-
    downloads_dir(DDir),
    forall(
        ( failed(packages, Bin, missing), deb_source(Bin, URL, Fname) ),
        ( atomic_list_concat([DDir, '/', Fname], Path),
          ( access_file(Path, exist)
          -> assert(satisfied(downloaded(Path)))
          ;  format(atom(Cmd), 'curl -fsSL ~w -o ~w', [URL, Path]),
             assert(build_rule(downloaded(Path), [internet_ok], [Cmd]))
          )
        )
    ).

gen_repo_rules :-
    forall(
        ( failed(repos, RepoName, missing), apt_repo(RepoName, _, AddCmd) ),
        assert(build_rule(repo_ready(RepoName), [internet_ok], [AddCmd]))
    ).

gen_package_rule :-
    downloads_dir(DDir),
    findall(Pkg,
        ( failed(packages, Bin, missing), binary_pkg(Bin, Pkg), \+ deb_install(Bin) ),
        RegPkgs),
    findall(Path,
        ( failed(packages, Bin, missing), deb_install(Bin),
          deb_source(Bin, _, Fname),
          atomic_list_concat([DDir, '/', Fname], Path) ),
        DebPaths),
    findall(downloaded(P), member(P, DebPaths), DebDeps),
    findall(repo_ready(R),
        ( member(Pkg, RegPkgs), pkg_repo(Pkg, R) ),
        RepoDeps0),
    sort(RepoDeps0, RepoDeps),
    append(RegPkgs, DebPaths, All),
    ( All \= []
    -> atomic_list_concat(['apt install -y' | All], ' ', InstallCmd),
       append([package_lists_fresh | DebDeps], [], InstDeps),
       assert(build_rule(packages_installed, InstDeps, [InstallCmd])),
       append([internet_ok | RepoDeps], [], UpdateDeps),
       assert(build_rule(package_lists_fresh, UpdateDeps, ['apt-get update']))
    ;  assert(build_rule(packages_installed, [], []))
    ).

gen_desktop_fix_rules :-
    forall(
        ( failed(packages, Bin, missing), desktop_fix(Bin, File, Expr) ),
        ( format(atom(Cmd), "sed -i '~w' ~w", [Expr, File]),
          assert(build_rule(desktop_fixed(File), [packages_installed], [Cmd]))
        )
    ).

%% Patches for currently-failing checks; patches for guards being installed this run.
%% A guard arriving via apt waits on packages_installed; one arriving via an
%% opt_install waits on that specific install.
gen_patch_rules :-
    forall(config_patch(Name, Guard, _, FixCmd), (
        ( failed(patches, Name, missing)
        -> assert(build_rule(patch_applied(Name), [], [FixCmd]))
        ;  failed(packages, Guard, missing), guard_install_dep(Guard, Dep)
        -> assert(build_rule(patch_applied(Name), [Dep], [FixCmd]))
        ;  true
        )
    )).

guard_install_dep(Guard, packages_installed)   :- binary_pkg(Guard, _), !.
guard_install_dep(Guard, opt_installed(Name))  :- opt_install(Name, Guard, _).

gen_session_fix_rules :-
    forall(
        ( failed(desktop, session_type, Name), session_rule(Name, FixCmd) ),
        assert(build_rule(session_fixed(Name), [], [FixCmd]))
    ).

gen_hardening_rules :-
    forall(
        ( failed(hardening, Name, missing), hardening_check(Name, _, FixCmd) ),
        assert(build_rule(hardening_applied(Name), [], [FixCmd]))
    ).

gen_user_tool_rules :-
    run_as_user(User),
    forall(
        failed(user_tools, Name, missing),
        ( user_tool(Name, _, RawCmd),
          format(atom(Cmd), "sudo -u ~w -i bash -c '~w'", [User, RawCmd]),
          ( user_tool_deps(Name, Deps) -> true ; Deps = [user_tool_ready(uv)] ),
          assert(build_rule(user_tool_ready(Name), Deps, [Cmd]))
        )
    ).

gen_top_rule :-
    findall(desktop_fixed(F),
        ( failed(packages, Bin, missing), desktop_fix(Bin, F, _) ),
        PkgFixDeps),
    findall(patch_applied(N),
        ( config_patch(N, Guard, _, _),
          ( failed(patches, N, missing)
          ; failed(packages, Guard, missing), guard_install_dep(Guard, _)
          )
        ),
        PatchDeps0),
    sort(PatchDeps0, PatchDeps),
    findall(opt_installed(N),
        ( failed(packages, Bin2, missing), opt_install(N, Bin2, _) ),
        OptDeps),
    findall(session_fixed(N),    failed(desktop, session_type, N),  SessionDeps),
    findall(hardening_applied(N), failed(hardening, N, missing),    HardeningDeps),
    findall(service_ready(N),    failed(services, N, missing),      ServiceDeps),
    findall(dm_standby(N),       failed(selection, N, standby),     StandbyDeps),
    findall(user_tool_ready(N),  failed(user_tools, N, missing),    ToolDeps),
    findall(user_config_applied(N), failed(user_config, N, missing), UserCfgDeps),
    flatten([packages_installed, PkgFixDeps, PatchDeps, OptDeps,
             SessionDeps, HardeningDeps, ServiceDeps, StandbyDeps,
             ToolDeps, UserCfgDeps], Deps),
    sort(Deps, UniqDeps),
    assert(build_rule(system_ready, UniqDeps, [])).

%% ── Planner (topological, propagates blocked) ─────────────────────────────────

collect(Goal, Vis0, Vis0, ok([])) :- memberchk(Goal, Vis0), !.
collect(Goal, Vis0, [Goal|Vis0], ok([])) :- satisfied(Goal), !.
collect(Goal, Vis0, Vis1, Result) :-
    build_rule(Goal, Deps, GoalCmds), !,
    collect_deps(Deps, Vis0, Vis2, DepsResult),
    ( DepsResult = blocked
    -> Vis1 = Vis2, Result = blocked
    ;  DepsResult = ok(DepCmds),
       Vis1 = [Goal|Vis2],
       append(DepCmds, GoalCmds, Cmds),
       Result = ok(Cmds)
    ).
collect(Goal, Vis0, Vis0, blocked) :-
    post_skip(Goal, 'no rule — dependency unachievable').

collect_deps([], Vis, Vis, ok([])).
collect_deps([H|T], Vis0, Vis2, Result) :-
    collect(H, Vis0, Vis1, HResult),
    ( HResult = blocked
    -> Vis2 = Vis1, Result = blocked
    ;  HResult = ok(HCmds),
       collect_deps(T, Vis1, Vis2, TResult),
       ( TResult = blocked
       -> Result = blocked
       ;  TResult = ok(TCmds),
          append(HCmds, TCmds, AllCmds),
          Result = ok(AllCmds)
       )
    ).

%% ── Entry point ──────────────────────────────────────────────────────────────

main :-
    set_stream(user_error, buffer(false)),
    maplist(diagnose, [internet, packages, repos, hardening, patches, desktop,
                       user_tools, services, selection, user_config]),
    nl(user_error),
    generate_rules,
    collect(system_ready, [], _, Result),
    ( Result = ok([])
    -> format(user_error, '\033[32mSystem is up to date.\033[0m~n', [])
    ; Result = ok(Cmds)
    -> catch(maplist(writeln, Cmds), error(io_error(_,_),_), true)
    ; format(user_error,
        '\033[31mFix blocked — resolve unachievable dependencies first.\033[0m~n', [])
    ).

:- initialization(main, main).
