%% platform/display — PRIME architecture (constitution XXVI, VGA-primary variant).
%% X ALWAYS boots on the ASPEED BMC head (the robust, dissimilar channel) as the
%% permanent display spine; the RTX A4000 is demoted to a render-offload + compute
%% device. The desktop therefore survives an nvidia driver death outright — X
%% never depends on the GPU stack — which is XXVI.VII (fail-operational) with no
%% dynamic selector and no moving parts: the robust channel is unconditional.
%%
%%   spine   (bmc_vga, ast)  — modesetting on the ASPEED VGA. Boots the desktop.
%%                             2D/software-composited (the ASPEED has no 3D), but
%%                             alive with the GPU driver dead, or the host off.
%%   offload (gpu_dp, nvidia)— the A4000 as a PRIME render-offload provider. Run
%%                             GPU work with `prime-run <app>`. Its loss costs
%%                             acceleration, never the desktop.
%%
%% BusIDs are SENSED at apply time from the VGA-class PCI device (XXVI.IV) — never
%% hardcoded, and never the AST1150 *bridge* at 0e:00.0 (a real trap: plain
%% "grep aspeed" matches the bridge, not the graphics at 0f:00.0). Config lives in
%% per-channel xorg.conf.d fragments (XXVI.III); the monolithic xorg.conf is
%% retired so no single artifact can coteinstate the shared-fate coupling.
%%
%% Dells on the GPU DisplayPort are an OPTIONAL, nvidia-dependent enhancement via
%% PRIME output offload (xrandr --setprovideroutputsource) — deliberately NOT in
%% the boot path, so the spine never inherits a GPU dependency. Left for a manual
%% target once the spine is proven.

display_channel(bmc_vga, ast, spine,
    'ASPEED BMC VGA — permanent display spine (X boots here; survives GPU/driver loss)').
display_channel(gpu_dp, 'nvidia-drm', offload,
    'RTX A4000 — render-offload + compute (prime-run); its loss costs acceleration, not the desktop').

%% Spine: X boots on the ASPEED via modesetting (the ast KERNEL module + the
%% modesetting X driver is the proven pair — there is no xserver-xorg-video-ast
%% on 26.04, so an X "Driver ast" fragment kills X with zero screens; learned
%% 2026-08-16). AllowNVIDIAGPUScreens lets the A4000 attach as an offload
%% provider when its driver is up. Gated on ASPEED presence; BusID sensed.
config_patch(xorg_bmc_primary, '/usr/lib/xorg/Xorg', Check, Fix) :-
    shell_ok("lspci 2>/dev/null | grep -iqE 'VGA.*ASPEED'"),
    Check = "grep -q AllowNVIDIAGPUScreens /etc/X11/xorg.conf.d/10-bmc-primary.conf 2>/dev/null && grep -q AutoAddGPU /etc/X11/xorg.conf.d/10-bmc-primary.conf && ! test -f /etc/X11/xorg.conf.d/10-aspeed-vga.conf",
    Fix = "rm -f /etc/X11/xorg.conf.d/10-aspeed-vga.conf; b=$(lspci -Dnn | grep -iE 'VGA.*ASPEED' | head -1 | cut -d' ' -f1); s=${b#*:}; bus=${s%%:*}; r=${s#*:}; dev=${r%%.*}; fn=${r#*.}; id=$(printf 'PCI:%d:%d:%d' \"0x$bus\" \"0x$dev\" \"0x$fn\"); mkdir -p /etc/X11/xorg.conf.d; { printf '%s\\n' 'Section \"ServerLayout\"' '    Identifier \"layout\"' '    Option \"AllowNVIDIAGPUScreens\"' 'EndSection' 'Section \"ServerFlags\"' '    Option \"AutoAddGPU\" \"false\"' 'EndSection' 'Section \"Device\"' '    Identifier \"BMC\"' '    Driver \"modesetting\"'; printf '    BusID \"%s\"\\n' \"$id\"; printf '%s\\n' 'EndSection' 'Section \"Screen\"' '    Identifier \"Screen0\"' '    Device \"BMC\"' 'EndSection'; } > /etc/X11/xorg.conf.d/10-bmc-primary.conf".

%% Offload provider: the A4000 as a PRIME GPU screen. Gated on GPU PRESENCE
%% (lspci), not driver liveness — with AllowNVIDIAGPUScreens a failed nvidia load
%% is a non-fatal secondary, so the spine still comes up (XXVI.VII). BusID sensed.
config_patch(xorg_nvidia_offload, '/usr/lib/xorg/Xorg', Check, Fix) :-
    shell_ok("lspci 2>/dev/null | grep -iqE 'VGA.*NVIDIA|3D.*NVIDIA'"),
    Check = "grep -q 'Driver \"nvidia\"' /etc/X11/xorg.conf.d/10-nvidia-offload.conf 2>/dev/null",
    Fix = "b=$(lspci -Dnn | grep -iE 'VGA.*NVIDIA|3D.*NVIDIA' | head -1 | cut -d' ' -f1); s=${b#*:}; bus=${s%%:*}; r=${s#*:}; dev=${r%%.*}; fn=${r#*.}; id=$(printf 'PCI:%d:%d:%d' \"0x$bus\" \"0x$dev\" \"0x$fn\"); mkdir -p /etc/X11/xorg.conf.d; { printf '%s\\n' 'Section \"Device\"' '    Identifier \"nvidia\"' '    Driver \"nvidia\"'; printf '    BusID \"%s\"\\n' \"$id\"; printf '%s\\n' '    Option \"AllowEmptyInitialConfiguration\" \"true\"' 'EndSection'; } > /etc/X11/xorg.conf.d/10-nvidia-offload.conf".

%% Retire the monolith once a fragment exists (XXVI.III): applicable only while
%% the monolith is present, and removed only after the spine fragment is written,
%% so there is never a window with no display config. Self-disabling thereafter.
config_patch(xorg_monolith_retired, '/etc/X11/xorg.conf', Check, Fix) :-
    Check = "test ! -f /etc/X11/xorg.conf",
    Fix = "test -f /etc/X11/xorg.conf.d/10-bmc-primary.conf && rm -f /etc/X11/xorg.conf".

%% Spine resolution: the iKVM mirrors whatever mode the ASPEED head runs, and
%% with no monitor attached there is no EDID, so X falls back to 640x480 — the
%% remote console becomes a postage stamp. Pin 1920x1080@60 via a Modeline in a
%% per-channel fragment (AST2500 ceiling is 1920x1200). Connector name VGA-1 is
%% the ast driver's stable name for the BMC head. Applicable only where the
%% ASPEED graphics exist; delete the fragment to fall back to auto-modes.
config_patch(xorg_bmc_mode, '/usr/lib/xorg/Xorg', Check, Fix) :-
    shell_ok("lspci 2>/dev/null | grep -iqE 'VGA.*ASPEED'"),
    Check = "grep -q 1920x1080_60 /etc/X11/xorg.conf.d/20-bmc-mode.conf 2>/dev/null && grep -q Monitor-VGA-1 /etc/X11/xorg.conf.d/10-bmc-primary.conf 2>/dev/null",
    Fix = "mkdir -p /etc/X11/xorg.conf.d && printf '%s\\n' 'Section \"Monitor\"' '    Identifier \"BMCVGA\"' '    Modeline \"1920x1080_60\" 173.00 1920 2048 2248 2576 1080 1083 1088 1120 -hsync +vsync' '    Option \"PreferredMode\" \"1920x1080_60\"' 'EndSection' > /etc/X11/xorg.conf.d/20-bmc-mode.conf && grep -q Monitor-VGA-1 /etc/X11/xorg.conf.d/10-bmc-primary.conf || sed -i '/Driver \"modesetting\"/a\\    Option \"Monitor-VGA-1\" \"BMCVGA\"' /etc/X11/xorg.conf.d/10-bmc-primary.conf".

%% prime-run: the render-offload wrapper (user phase). GPU work opts in explicitly
%% — `prime-run glxgears`, `prime-run blender` — so the default desktop stays on
%% the robust software path and only named apps take the nvidia dependency.
user_config(prime_run_alias, Check, Fix) :-
    user_home(Home),
    format(atom(Check), "grep -q 'prime-run()' ~w/.bashrc 2>/dev/null", [Home]),
    format(atom(Fix),
        "printf '%s\\n' 'prime-run() { __NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia \"$@\"; }' >> ~w/.bashrc",
        [Home]).
