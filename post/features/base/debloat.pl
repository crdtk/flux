%% base/debloat — strip Ubuntu of what this workstation never wants:
%% snapd, PackageKit, suspend, sssd PAM remnants, slow GRUB, low inotify
%% limits, crash-prone parport, the real PulseAudio daemon. Revoking
%% this decision restores stock.

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
%% PipeWire is this system's audio server; the real pulseaudio daemon
%% package is a saboteur — libpulse clients autospawn it when the pulse
%% socket blips, it steals the socket path from pipewire-pulse, then
%% dies and leaves an orphaned bind (ECONNREFUSED for every client;
%% seen 2026-08-05, repair in desktop/audio.pl). apt swaps in
%% pipewire-alsa + pipewire-audio as the audio provider; bluetooth is
%% wireplumber's job. pulseaudio-utils (pactl) and libpulse0 stay.
%% Check demands the binary gone, not just the pin — a failed purge
%% must keep FAILing, so the fix only pins after purge succeeds.
hardening_check(no_pulseaudio_daemon,
    "! test -x /usr/bin/pulseaudio && test -f /etc/apt/preferences.d/no-pulseaudio-daemon",
    "apt-get purge -y pulseaudio pulseaudio-module-bluetooth && printf 'Package: pulseaudio\\nPin: release a=*\\nPin-Priority: -1\\n\\nPackage: pulseaudio-module-bluetooth\\nPin: release a=*\\nPin-Priority: -1\\n' > /etc/apt/preferences.d/no-pulseaudio-daemon").
%% nano is not this workstation's editor; purge and pin it so no
%% package drags it back as a Recommends. Check demands the binary
%% gone, not just the pin — the fix only pins after purge succeeds.
hardening_check(no_nano,
    "! test -x /usr/bin/nano && test -f /etc/apt/preferences.d/no-nano",
    "apt-get purge -y nano && printf 'Package: nano\\nPin: release a=*\\nPin-Priority: -1\\n' > /etc/apt/preferences.d/no-nano").
%% Root-owned skeleton (~/turboquant-demo/.sentinel, empty) left by a
%% 2026-06-07 sudo-make run of the removed TurboQuant pilot. Junk on
%% both machines; the root-owned copy also broke the first user-level
%% `make sync` pull (rsync cannot chgrp a dir the user does not own).
hardening_check(turboquant_leftover_absent, Check, Fix) :-
    user_home(Home),
    format(atom(Check), "! test -e ~w/turboquant-demo", [Home]),
    format(atom(Fix), "rm -rf ~w/turboquant-demo", [Home]).
hardening_check(pam_sss_absent,
    "! grep -rq pam_sss /etc/pam.d/ 2>/dev/null",
    "grep -rl pam_sss /etc/pam.d/ 2>/dev/null | xargs -r sed -i '/pam_sss/d'").
