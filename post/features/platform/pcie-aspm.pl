%% platform/pcie-aspm — the PLX switch link-power saga (see memory:
%% project-pcie-switch-bench). pcie_aspm=off is necessary but not
%% sufficient on this board: firmware keeps ASPM control (_OSC denies the
%% OS), so the setpci service clears the L1 bits on every switch port at
%% boot. Dies the day the switch path is fully validated or replaced.
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
