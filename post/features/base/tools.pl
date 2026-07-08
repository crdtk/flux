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
binary_pkg('/usr/bin/kdenlive',      kdenlive).
binary_pkg('/usr/bin/digikam',       digikam).
binary_pkg('/usr/bin/obs',           'obs-studio').
binary_pkg('/usr/bin/git',           git).
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
