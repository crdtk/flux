%% desktop/lomiri — the experimental Lomiri session track (see memory:
%% project-lomiri-nvidia). Mir aborts at startup on NVIDIA ("GBM display
%% platform being incompatible with Nvidia" → exception → SIGABRT,
%% observed 2026-06-28). Upstream-recommended fix for driver 565+:
%% atomic-kms display platform + gbm-kms rendering, plus a driver quirk
%% lifting nvidia off the block list, delivered as a systemd user drop-in
%% so it only affects lomiri.service. Abandoning Lomiri deletes this file;
%% its candidate ranking stays in desktop/session-select.pl.

%% Lomiri (Unity 8 successor) — experimental session candidate, kept
%% installed for redundancy; the selection engine ranks it last.
binary_pkg('/usr/share/wayland-sessions/lomiri.desktop', lomiri).

%% Mir's atomic-kms display platform: the supported NVIDIA path on driver
%% 565+ (EGLStream is broken there, and gbm-kms block-lists nvidia).
%% Only needed where Lomiri is installed on an NVIDIA box.
binary_pkg('/usr/lib/x86_64-linux-gnu/mir/server-platform/graphics-atomic-kms.so.23',
           'mir-platform-graphics-atomic-kms') :-
    has_nvidia,
    shell_ok("test -x /usr/bin/lomiri").

config_patch(lomiri_nvidia_platform, '/usr/bin/lomiri', Check, Fix) :-
    has_nvidia,
    Check = "test -f /etc/systemd/user/lomiri.service.d/nvidia-platform.conf",
    Fix = "mkdir -p /etc/systemd/user/lomiri.service.d && printf '%s\\n' '[Service]' 'Environment=MIR_SERVER_PLATFORM_DISPLAY_LIBS=mir:atomic-kms' 'Environment=MIR_SERVER_PLATFORM_RENDERING_LIBS=mir:gbm-kms' 'Environment=MIR_SERVER_DRIVER_QUIRKS=allow:driver:nvidia' > /etc/systemd/user/lomiri.service.d/nvidia-platform.conf".

viable(session, lomiri) :-
    shell_ok("test -f /usr/share/wayland-sessions/lomiri.desktop"),
    \+ lomiri_crash_evidence.

%% Lomiri session attempts leave component coredumps (Mir/NVIDIA SIGABRT
%% observed 2026-06-28). Once the NVIDIA platform fix is in place, only
%% crashes NEWER than the fix count — so one clean Lomiri login after
%% applying POST promotes the candidate without manual coredump clearing.
lomiri_crash_evidence :-
    shell_ok("test -f /etc/systemd/user/lomiri.service.d/nvidia-platform.conf"), !,
    shell_ok("coredumpctl list --since=@$(stat -c %Y /etc/systemd/user/lomiri.service.d/nvidia-platform.conf) --no-pager 2>/dev/null | grep -q lomiri").
lomiri_crash_evidence :-
    shell_ok("coredumpctl list --no-pager 2>/dev/null | grep -q lomiri").

demotion_reason(session, lomiri, Why) :-
    lomiri_crash_evidence,
    ( shell_ok("test -f /etc/systemd/user/lomiri.service.d/nvidia-platform.conf")
    -> Why = 'crashed again after NVIDIA platform fix — inspect coredumpctl'
    ;  Why = 'Mir rejects NVIDIA GBM — fix queued; apply POST, then retry a Lomiri login'
    ).
