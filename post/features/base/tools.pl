%% base/tools — the honest flat list: CLI utilities, probes the gates rely
%% on (pciutils, dmidecode, avahi, apt-file), and desktop apps with no
%% story of their own. A tool graduates to its own module the day it
%% accretes a gate or a second fact type.

%% ── Early gates (run first, before other provisioning) ────────────────────
%% Tailscale auth key from environment variable. Usage:
%% TS_AUTHKEY="tskey-..." make | sudo bash
%% Prefixed with "0_" to sort first in execution order.

hardening_check('0_tailscale_authkey',
    "test -f /etc/tailscale/authkey",
    Cmd) :-
    getenv('TS_AUTHKEY', Key),
    format(atom(Cmd),
        "mkdir -p /etc/tailscale && chmod 700 /etc/tailscale && echo '~w' | tee /etc/tailscale/authkey >/dev/null && chmod 600 /etc/tailscale/authkey",
        [Key]).

binary_pkg('/usr/bin/flameshot',     flameshot).
binary_pkg('/usr/bin/gimp',          gimp).
binary_pkg('/usr/bin/gwenview',      gwenview).
binary_pkg('/usr/bin/heif-convert',  'libheif-examples').
binary_pkg('/usr/lib/x86_64-linux-gnu/qt5/plugins/imageformats/kimg_heif.so',
                                     'kimageformat-plugins').
binary_pkg('/usr/bin/terminator',    terminator).
binary_pkg('/usr/bin/mc',            mc).
binary_pkg('/usr/bin/plank',         plank).
binary_pkg('/usr/bin/rclone',        rclone).
binary_pkg('/usr/bin/xclip',         xclip).
binary_pkg('/usr/bin/jq',            jq).
binary_pkg('/usr/bin/plantuml',      plantuml).
%% project management app — complements ganttproject for plan/schedule tracking
binary_pkg('/usr/bin/planner',       planner).
%% lightweight 3D viewer for the vessels demo GLB/PLY artifacts
binary_pkg('/usr/bin/f3d',           f3d).
%% npx runner for node CLI specialists (gltf-transform) — nothing global
binary_pkg('/usr/bin/npm',           npm).
%% imagemagick: kept for digikam's dependency chain (libmagickcore, libmagickwand,
%% libmagick++). It was added 2026-08-10 as a render-critique tool for vessels
%% look-dev but nothing checked in invokes convert/montage. The no_imagemagick
%% hardening check was too aggressive — `apt-get purge -y 'imagemagick*'`
%% removes both binaries and libs, breaking digikam. Since digikam is essential
%% for photo work, keeping imagemagick (unused binaries, needed libs) is the
%% pragmatic choice: no-consumer rule relaxed 2026-09-04 due to dependency clash.
binary_pkg('/usr/bin/convert',       imagemagick).

%% Convert3D (ITK-SNAP's CLI): NIfTI mask morphology as one pipeline —
%% the vessels demo's CLI specialist for Otsu/components/distance
%% transforms. Not in the archive; static binary from the project's
%% nightly channel (URL verified 2026-08-10, ~55MB).
opt_install(c3d, '/opt/c3d/bin/c3d', Cmd) :-
    downloads_dir(DDir),
    format(atom(Cmd),
        "curl -fsSL 'https://sourceforge.net/projects/c3d/files/c3d/Nightly/c3d-nightly-Linux-x86_64.tar.gz/download' -o ~w/c3d-nightly-Linux-x86_64.tar.gz && mkdir -p /opt/c3d && tar -xzf ~w/c3d-nightly-Linux-x86_64.tar.gz -C /opt/c3d --strip-components=1 && ln -sf /opt/c3d/bin/c3d /usr/local/bin/c3d",
        [DDir, DDir]).
binary_pkg('/usr/bin/bleachbit',     bleachbit).
%% disk-usage pair, chosen 2026-08-14: filelight = the Plasma-native
%% sunburst for the human; ncdu = the terminal specialist for sweeps
%% (replaces hand-rolled du|sort pipelines). Baobab redundant on KDE.
binary_pkg('/usr/bin/filelight',     filelight).
binary_pkg('/usr/bin/ncdu',          ncdu).
%% duplicate finder, chosen 2026-08-15: Czkawka (Rust, multithreaded)
%% over dupeGuru (Python, ~10x slower) — exact dupes + perceptual
%% image/video similarity; in the archive since 26.04.
binary_pkg('/usr/bin/czkawka_gui',   'czkawka-gui').
%% same engine headless — drives `make dup-report` (Filesystem/user.mk)
%% without the GUI's large-result-set freeze.
binary_pkg('/usr/bin/czkawka_cli',   'czkawka-cli').

%% Blender comes from blender.org, not the archive: distro builds are
%% compiled without the CUDA/OptiX Cycles kernels, so GPU rendering
%% silently falls back to CPU — the official tarball ships them all.
%% The fix purges any distro copy first (transition is one-way; the
%% /usr/local/bin symlink outranks /usr/bin on PATH anyway) and
%% registers the launcher + icon from the tarball itself.
opt_install(blender_official, '/opt/blender/blender', Cmd) :-
    downloads_dir(DDir),
    format(atom(Cmd),
        "apt-get purge -y blender 2>/dev/null || true; curl -fsSL https://download.blender.org/release/Blender5.0/blender-5.0.1-linux-x64.tar.xz -o ~w/blender-5.0.1-linux-x64.tar.xz && mkdir -p /opt/blender && tar -xJf ~w/blender-5.0.1-linux-x64.tar.xz -C /opt/blender --strip-components=1 && ln -sf /opt/blender/blender /usr/local/bin/blender && mkdir -p /usr/local/share/applications /usr/local/share/icons/hicolor/scalable/apps && sed 's|^Exec=blender|Exec=/usr/local/bin/blender|' /opt/blender/blender.desktop > /usr/local/share/applications/blender.desktop && cp /opt/blender/blender.svg /usr/local/share/icons/hicolor/scalable/apps/blender.svg && (update-desktop-database /usr/local/share/applications 2>/dev/null || true)",
        [DDir, DDir]).
binary_pkg('/usr/bin/kdenlive',      kdenlive).
binary_pkg('/usr/bin/digikam',       digikam).
%% digiKam 8's metadata engine shells out to ExifTool; without it every
%% startup logs "ExifTool process cannot be started" and metadata
%% read/write is dead (found 2026-08-15). Lives with digikam (XXV).
binary_pkg('/usr/bin/exiftool',      'libimage-exiftool-perl').
binary_pkg('/usr/bin/obs',           'obs-studio').
binary_pkg('/usr/bin/xournalpp',     xournalpp).
%% GanttProject: not in Ubuntu repos; obtained as .deb from GitHub releases
%% (bardsoftware/ganttproject). Latest pinned to 3.3.3316 (2026-09-04).
%% apt-get install ./file.deb resolves dependencies automatically; dpkg -i alone
%% leaves broken dependencies. apt install -f cleans up after dpkg failures.
opt_install(ganttproject, '/usr/bin/ganttproject', Cmd) :-
    downloads_dir(DDir),
    format(atom(Cmd),
        "curl -fsSL 'https://github.com/bardsoftware/ganttproject/releases/download/ganttproject-3.3.3316/ganttproject_3.3.3316-1_all.deb' -o ~w/ganttproject_3.3.3316-1_all.deb && apt-get install -y ~w/ganttproject_3.3.3316-1_all.deb",
        [DDir, DDir]).
binary_pkg('/usr/bin/AusweisApp',    ausweisapp).
binary_pkg('/usr/bin/vlc',           vlc).
binary_pkg('/usr/bin/kdeconnect-app', kdeconnect).
binary_pkg('/usr/bin/git',           git).
%% Java runtime for GanttProject (3.3.3316 requires Java 17+)
binary_pkg('/usr/bin/java',          'openjdk-21-jre').

%% Git edits (commit messages, rebase todos) open in vi — system tier
%% (/etc/gitconfig) so every user including ai-agent gets it, and no
%% fallback to the `editor` alternative, which dangles now that nano
%% is purged (debloat.pl no_nano). vi ships as vim.tiny.
hardening_check(git_editor_vi,
    "git config --system core.editor 2>/dev/null | grep -qx vi",
    "git config --system core.editor vi").
binary_pkg('/usr/sbin/avahi-daemon', 'avahi-daemon').
binary_pkg('/usr/sbin/arp-scan',     'arp-scan').
binary_pkg('/usr/bin/nmap',          nmap).
binary_pkg('/usr/bin/lspci',         pciutils).
binary_pkg('/usr/sbin/dmidecode',    dmidecode).
binary_pkg('/usr/bin/apt-file',      'apt-file').

apt_repo(kubuntu_backports,
    "find /etc/apt/sources.list.d/ -name 'kubuntu-ppa-ubuntu-backports*' 2>/dev/null | grep -q .",
    "add-apt-repository -y ppa:kubuntu-ppa/backports").
apt_repo(obsproject,
    "find /etc/apt/sources.list.d/ -name 'obsproject*' 2>/dev/null | grep -q .",
    "add-apt-repository -y ppa:obsproject/obs-studio").

pkg_repo(kdenlive,     kubuntu_backports).
pkg_repo(digikam,      kubuntu_backports).
pkg_repo('obs-studio', obsproject).

config_patch(heif_mime_types,
    '/usr/lib/x86_64-linux-gnu/qt5/plugins/imageformats/kimg_heif.so',
    "! test -f /usr/share/kservices5/imagethumbnail.desktop || grep -q 'image/heif' /usr/share/kservices5/imagethumbnail.desktop 2>/dev/null",
    "sed -i 's|image/avif;|image/avif;image/heif;image/heic;|' /usr/share/kservices5/imagethumbnail.desktop 2>/dev/null || true").

%% ── Nix (NixOS-alongside ISO builds, mk/features/System/NixOS) ──────────────
%% nix-bin alone ships no daemon; nix-setup-systemd carries the units. The
%% daemon socket is 0660 root:nix-users — the human user must be in the
%% group (takes effect at next login). `make nixos-iso` builds the
%% self-installing USB from nixos/flake.nix on top of this.
binary_pkg('/usr/bin/nix', 'nix-bin').
binary_pkg('/usr/lib/systemd/system/nix-daemon.service', 'nix-setup-systemd').

service_check(nix_daemon,
    "systemctl is-enabled nix-daemon.socket >/dev/null 2>&1",
    "systemctl enable --now nix-daemon.socket").

hardening_check(nix_users_group, Check, Fix) :-
    run_as_user(U),
    format(atom(Check), "id -nG ~w | grep -qw nix-users", [U]),
    format(atom(Fix),   "usermod -aG nix-users ~w", [U]).

%% Sends the WoL magic packet from the laptop (make rig-wake).
binary_pkg('/usr/bin/wakeonlan', wakeonlan).

%% VM rehearsal for the NixOS ISOs (make nixos-vm): boot the artifact
%% in UEFI QEMU before it ever meets a real disk. ovmf ships the
%% single-file UEFI firmware image qemu points at.
binary_pkg('/usr/bin/qemu-system-x86_64', 'qemu-system-x86').
binary_pkg('/usr/share/ovmf/OVMF.fd',     ovmf).
