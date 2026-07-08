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

%% Single-screen X11 on the bench A4000: the ASPEED BMC head has no monitor
%% and parks plasmashell panels on a phantom output, so X drives the GPU
%% only. Applies at next login — never restart the DM for it (that tears
%% down the session and resets the KScreen layout).
config_patch(xorg_nvidia_a4000, '/usr/lib/xorg/Xorg', Check, Fix) :-
    shell_ok("lspci 2>/dev/null | grep -q GA104GL"),
    Check = "grep -q 'NVIDIA A4000' /etc/X11/xorg.conf 2>/dev/null",
    Fix = "printf '%s\\n' 'Section \"Device\"' '    Identifier \"NVIDIA A4000\"' '    Driver     \"nvidia\"' '    Option     \"AllowEmptyInitialConfiguration\" \"true\"' 'EndSection' '' 'Section \"Screen\"' '    Identifier \"Screen0\"' '    Device     \"NVIDIA A4000\"' 'EndSection' > /etc/X11/xorg.conf".
