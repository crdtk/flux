{ config, pkgs, lib, flakeSelf, ... }:
{
  # The fenced alongside-installer, shared by BOTH ISOs (installer.nix
  # console stick, live.nix Plasma stick): one procedure, two vehicles.
  # The flake rides along read-only so nixos-install has its target.
  environment.etc."serval-flake".source = flakeSelf;

  environment.systemPackages = [
    pkgs.lvm2 pkgs.btrfs-progs pkgs.e2fsprogs

    (pkgs.writeShellApplication {
      name = "serval-nixos-install";
      runtimeInputs = [ pkgs.lvm2 pkgs.btrfs-progs pkgs.e2fsprogs pkgs.util-linux ];
      text = ''
        # Offline NixOS-alongside install for the serval laptop.
        # Layout it expects (and ONLY this layout — anything else refuses):
        #   nvme0n1p1  vfat ESP, UUID 7278-528B   (shared, never formatted)
        #   nvme0n1p2  LVM PV, VG "VG", single LV "root" (ext4, Kubuntu)
        # What it does:
        #   1. fsck the ext4 root (unmounted — we booted from USB)
        #   2. shrink ext4 to $SHRINK_FS, lvreduce root to $SHRINK_LV,
        #      grow ext4 back to fill the LV exactly
        #   3. lvcreate -L $NIXOS_SIZE -n nixos VG ; mkfs.btrfs (@, @home)
        #   4. nixos-install --flake /etc/serval-flake#serval
        # Kubuntu is modified ONLY by the shrink; rollback of the whole
        # install is `lvremove VG/nixos` + efibootmgr cleanup.

        SHRINK_FS=''${SHRINK_FS:-396G}     # resize2fs target (4G under the LV)
        SHRINK_LV=''${SHRINK_LV:-400G}     # lvreduce target for VG/root
        NIXOS_SIZE=''${NIXOS_SIZE:-64G}    # new LV for NixOS
        ESP_UUID=7278-528B

        [ "$(id -u)" = 0 ] || { echo "run as root (sudo serval-nixos-install)"; exit 1; }

        vgchange -ay VG >/dev/null
        [ -e /dev/VG/root ] || { echo "FENCE: VG/root not found — wrong machine?"; exit 1; }
        grep -q 'VG-root' /proc/mounts && { echo "FENCE: VG/root is mounted"; exit 1; }
        [ "$(blkid -o value -s TYPE /dev/VG/root)" = ext4 ] \
          || { echo "FENCE: VG/root is not ext4 (already converted?)"; exit 1; }
        [ -e "/dev/disk/by-uuid/$ESP_UUID" ] || { echo "FENCE: ESP $ESP_UUID not found"; exit 1; }

        if [ -e /dev/VG/nixos ] && [ "''${REINSTALL:-0}" != 1 ]; then
          echo "FENCE: VG/nixos already exists. Set REINSTALL=1 to re-format it"
          echo "       (skips the shrink; Kubuntu untouched), or lvremove it first."
          exit 1
        fi

        # Fence: never shrink below 120% of what ext4 actually holds.
        bs=$(dumpe2fs -h /dev/VG/root 2>/dev/null | awk '/^Block size:/{print $3}')
        total=$(dumpe2fs -h /dev/VG/root 2>/dev/null | awk '/^Block count:/{print $3}')
        free=$(dumpe2fs -h /dev/VG/root 2>/dev/null | awk '/^Free blocks:/{print $3}')
        used_g=$(( (total - free) / (1024*1024*1024/bs) ))
        tgt_g=''${SHRINK_FS%G}
        [ $(( used_g * 12 / 10 )) -lt "$tgt_g" ] \
          || { echo "FENCE: ext4 holds ''${used_g}G — too full to shrink to $SHRINK_FS"; exit 1; }

        echo "Plan: fsck; ext4 ''${total}blk → $SHRINK_FS; LV root → $SHRINK_LV;"
        echo "      grow ext4 to fill; create VG/nixos ($NIXOS_SIZE, btrfs); install."
        read -rp "Type YES to proceed: " a; [ "$a" = YES ] || exit 1

        if [ ! -e /dev/VG/nixos ]; then
          e2fsck -f /dev/VG/root
          resize2fs /dev/VG/root "$SHRINK_FS"
          lvreduce -f -L "$SHRINK_LV" VG/root
          resize2fs /dev/VG/root            # grow to fill the LV exactly
          e2fsck -f /dev/VG/root
          lvcreate -L "$NIXOS_SIZE" -n nixos VG
        fi

        mkfs.btrfs -f -L nixos /dev/VG/nixos
        mount /dev/VG/nixos /mnt
        btrfs subvolume create /mnt/@
        btrfs subvolume create /mnt/@home
        umount /mnt
        mount -o subvol=@,compress=zstd,noatime /dev/VG/nixos /mnt
        mkdir -p /mnt/home /mnt/boot
        mount -o subvol=@home,compress=zstd,noatime /dev/VG/nixos /mnt/home
        mount "/dev/disk/by-uuid/$ESP_UUID" /mnt/boot

        nixos-install --no-root-passwd --flake /etc/serval-flake#serval

        echo "Done. reboot, pick 'Linux Boot Manager' (systemd-boot) in the"
        echo "firmware menu for NixOS; the Ubuntu GRUB entry is untouched."
        echo "Rollback: boot Kubuntu, sudo lvremove VG/nixos."
      '';
    })
  ];
}
