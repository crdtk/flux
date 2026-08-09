%% platform/nvidia — everything that dies if the GPU goes AMD: driver,
%% nouveau blacklist, VRAM-preserve power options, CUDA stack, and the
%% bench-A4000 single-screen X11 config. Gate: has_nvidia (engine).

opt_install(nvidia_driver, '/usr/bin/nvidia-smi', 'ubuntu-drivers install') :-
    has_nvidia.

%% CUDA toolkit — only a fact when an NVIDIA GPU is present.
binary_pkg('/usr/local/cuda/bin/nvcc', 'cuda-toolkit') :- has_nvidia.

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

pkg_repo('cuda-toolkit', cuda_repo).

hardening_check(nouveau_blacklisted, Check, Fix) :-
    has_nvidia,
    Check = "test -f /etc/modprobe.d/blacklist-nouveau.conf",
    Fix = "printf 'blacklist nouveau\\nblacklist lbm-nouveau\\noptions nouveau modeset=0\\n' > /etc/modprobe.d/blacklist-nouveau.conf && update-initramfs -u".
hardening_check(nvidia_power, Check, Fix) :-
    has_nvidia,
    Check = "test -f /etc/modprobe.d/nvidia-power.conf",
    Fix = "printf 'options nvidia NVreg_PreserveVideoMemoryAllocations=1\\noptions nvidia NVreg_TemporaryFilePath=/tmp\\n' > /etc/modprobe.d/nvidia-power.conf".
%% The nvidia module must match BOTH the running kernel AND the installed driver
%% (XXVI offload channel). Ubuntu's precompiled modules make this a version dance:
%% each kernel's module package is built against ONE driver release, and an older
%% kernel's module lags the current driver (7.0.0-27's module Depends
%% nvidia-kernel-common-595 <= 595.71.05, unco-installable with the 595.84 now
%% present). So the ONLY kernel guaranteed a driver-matching module is the LATEST,
%% tracked by the -generic meta. Therefore: auto-fix ONLY when running the latest
%% kernel (install meta → matching module → modprobe); when running an OLDER
%% kernel, do not fight apt — advise a reboot (below, XXIV). Branch+flavor <bf>
%% (e.g. 595-open) is DERIVED from the installed module (XXVI.IV — no hardcode).
hardening_check(nvidia_module_tracks_kernel, Check, Fix) :-
    has_nvidia,
    shell_ok("test \"$(uname -r)\" = \"$(ls -1 /boot/vmlinuz-* 2>/dev/null | sed 's#.*vmlinuz-##' | sort -V | tail -1)\""),
    Check = "modinfo nvidia >/dev/null 2>&1",
    Fix = "bf=$(dpkg-query -W -f='${Package}\\n' 'linux-modules-nvidia-*' 2>/dev/null | grep -E '[0-9]+\\.[0-9]+\\.[0-9]+-[0-9]+-generic$' | head -1 | sed -E 's/^linux-modules-nvidia-//; s/-[0-9]+\\.[0-9]+\\.[0-9]+-[0-9]+-generic$//'); test -n \"$bf\" && apt-get install -y \"linux-modules-nvidia-$bf-generic\" && depmod -a && modprobe nvidia nvidia_drm".

%% Running an older kernel than the driver's module targets: the module can't be
%% force-installed (version skew above), so the cure is a reboot into the latest
%% kernel (GRUB default). Human-only (XXIV) — POST never reboots.
advisory(hardening, nvidia_boot_latest_kernel,
    'nvidia module absent for the running kernel and its package lags the installed driver — reboot into the latest kernel (GRUB default) so the module matches; desktop stays up on the VGA spine meanwhile') :-
    has_nvidia,
    \+ shell_ok("modinfo nvidia >/dev/null 2>&1"),
    \+ shell_ok("test \"$(uname -r)\" = \"$(ls -1 /boot/vmlinuz-* 2>/dev/null | sed 's#.*vmlinuz-##' | sort -V | tail -1)\"").

%% X11 GPU-head configuration moved to platform/display (XXV: one decision, one
%% module; XXVI: it is one display CHANNEL among several, not an nvidia-private
%% fact). The old monolithic /etc/X11/xorg.conf here wired the entire desktop to
%% this driver — when the driver dropped, X fell to an 800x600 firmware
%% framebuffer while a healthy head sat dark. display.pl now writes a per-channel
%% xorg.conf.d fragment and retires the monolith. The former baked assumption
%% ("the ASPEED head has no monitor") was exactly the XXVI.IV violation.

%% CUDA header vs modern glibc/gcc: math_functions.h redeclares rsqrt/rsqrtf
%% with a trailing `noexcept` that the host compiler rejects ("expected
%% initializer before 'noexcept'"), killing every nvcc JIT — FlashInfer's
%% fp8-KV kernels (vLLM bench), torch inductor, any runtime compile. The
%% bf16 path compiles nothing, which masks it. Dropping the trailer matches
%% the exception spec of glibc's own declaration. Re-applies after every
%% cuda-toolkit upgrade rewrites the header — exactly why it is POST-owned.
config_patch(cuda_rsqrt_noexcept, '/usr/local/cuda/include/crt/math_functions.h', Check, Fix) :-
    Check = "! grep -q '_NV_RSQRT_SPECIFIER) noexcept' /usr/local/cuda/include/crt/math_functions.h",
    Fix = "sed -i 's/\\(_NV_RSQRT_SPECIFIER)\\) noexcept;/\\1;/' /usr/local/cuda/include/crt/math_functions.h".
