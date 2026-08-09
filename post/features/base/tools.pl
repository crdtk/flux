%% base/tools — the honest flat list: CLI utilities, probes the gates rely
%% on (pciutils, dmidecode, avahi, apt-file), and desktop apps with no
%% story of their own. A tool graduates to its own module the day it
%% accretes a gate or a second fact type.

binary_pkg('/usr/bin/flameshot',     flameshot).
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
binary_pkg('/usr/bin/bleachbit',     bleachbit).

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
binary_pkg('/usr/bin/obs',           'obs-studio').
binary_pkg('/usr/bin/blender',       blender).
binary_pkg('/usr/bin/xournalpp',     xournalpp).
binary_pkg('/usr/bin/AusweisApp',    ausweisapp).
binary_pkg('/usr/bin/vlc',           vlc).
binary_pkg('/usr/bin/bleachbit',     bleachbit).
binary_pkg('/usr/bin/git',           git).

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
