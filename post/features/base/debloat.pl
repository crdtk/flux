%% base/debloat — strip Ubuntu of what this workstation never wants:
%% snapd, PackageKit, suspend, sssd PAM remnants, slow GRUB, low inotify
%% limits, crash-prone parport. Revoking this decision restores stock.

hardening_check(inotify_limits,
    "test -f /etc/sysctl.d/90-inotify.conf",
    "printf 'fs.inotify.max_user_watches=524288\\nfs.inotify.max_queued_events=131072\\nfs.inotify.max_user_instances=4096\\n' > /etc/sysctl.d/90-inotify.conf && sysctl -p /etc/sysctl.d/90-inotify.conf").
hardening_check(no_snapd,
    "test -f /etc/apt/preferences.d/no-snapd",
    "snap list --all 2>/dev/null | awk 'NR>1{print $1}' | xargs -r snap remove --purge 2>/dev/null || true; apt-get purge -y snapd 2>/dev/null || true; rm -rf /snap /var/snap /var/lib/snapd /var/cache/snapd /root/snap; printf 'Package: snapd\\nPin: release a=*\\nPin-Priority: -1\\n' > /etc/apt/preferences.d/no-snapd").
hardening_check(suspend_masked,
    "test -L /etc/systemd/system/suspend.target",
    "systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target").
%% lp/parport NULL-deref crashes kernel 7.0.0-22.
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
