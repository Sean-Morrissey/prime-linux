#!/bin/bash
# Runs INSIDE the CachyOS live ISO, as root, from prime-vm-install.service
# (put into the live system's writable layer — see tests/vm/run.sh). Installs a minimal CachyOS onto
# /dev/vda the way the CachyOS CLI install would, with:
#   · btrfs root, systemd-boot, linux-cachyos, NetworkManager, sshd
#   · user "alex" (password "prime", passwordless sudo — TEST VM ONLY)
#   · the host's SSH test key, the keyboard layout from /root/prime/kb
#   · NO desktop and NO login screen: install.sh must bring both
# Progress goes to the serial console; the last line is PRIME-VM-INSTALL: OK
# or PRIME-VM-INSTALL: FAILED. The VM powers off when this returns.
set -euo pipefail
exec > >(tee -a /dev/ttyS0 /root/prime-vm-install.log) 2>&1
trap 'echo "PRIME-VM-INSTALL: FAILED (line $LINENO)"' ERR
cfg() { cat "/root/prime/$1" 2>/dev/null || true; }
say() { echo "[prime-vm] $*"; }

DISK=/dev/vda
KB="$(cfg kb)"; KB="${KB:-us}"
PUBKEY="$(cfg pubkey)"

say "network"
for i in $(seq 20); do curl -fsS --max-time 5 -o /dev/null https://cachyos.org && break; sleep 3; done
if ! curl -fsS --max-time 5 -o /dev/null https://cachyos.org; then
    # NetworkManager didn't bring it up: QEMU user net is always 10.0.2.15 / gw .2 / dns .3
    IF="$(ip -o link | awk -F': ' '$2 != "lo" {print $2; exit}')"
    ip link set "$IF" up; ip addr add 10.0.2.15/24 dev "$IF" 2>/dev/null || true
    ip route add default via 10.0.2.2 2>/dev/null || true
    rm -f /etc/resolv.conf; echo "nameserver 10.0.2.3" > /etc/resolv.conf
    for i in $(seq 10); do curl -fsS --max-time 5 -o /dev/null https://cachyos.org && break; sleep 3; done
fi

say "pacman keyring"
pacman-key --init >/dev/null
pacman-key --populate archlinux cachyos >/dev/null

# the target is the empty 40 GB disk; the 8 GB one is this live system's own layer
[ "$(lsblk -bndo SIZE "$DISK")" -gt $((30*1024*1024*1024)) ] || { echo "PRIME-VM-INSTALL: FAILED ($DISK is not the 40 GB target)"; exit 1; }
say "partitioning $DISK (GPT: 1 GiB EFI + btrfs)"
wipefs -af "$DISK" >/dev/null
sfdisk -q "$DISK" <<EOF
label: gpt
size=1GiB, type=uefi, name=EFI
type=linux, name=root
EOF
udevadm settle
mkfs.fat -F32 -n EFI "${DISK}1" >/dev/null
mkfs.btrfs -fq -L cachyos "${DISK}2"
mount "${DISK}2" /mnt
btrfs subvolume create /mnt/@ >/dev/null
btrfs subvolume create /mnt/@home >/dev/null
umount /mnt
mount -o subvol=@,compress=zstd "${DISK}2" /mnt
mkdir -p /mnt/home /mnt/boot
mount -o subvol=@home,compress=zstd "${DISK}2" /mnt/home
mount "${DISK}1" /mnt/boot

say "pacstrap (CachyOS repos from the live system's pacman.conf)"
pacstrap -P /mnt base linux-cachyos mkinitcpio btrfs-progs dosfstools \
    cachyos-keyring cachyos-mirrorlist cachyos-v3-mirrorlist cachyos-v4-mirrorlist \
    networkmanager openssh sudo nano curl
cp -a /etc/pacman.d/*mirrorlist* /mnt/etc/pacman.d/ 2>/dev/null || true
genfstab -U /mnt >> /mnt/etc/fstab

say "configuring the installed system"
ROOTUUID="$(blkid -s UUID -o value "${DISK}2")"
arch-chroot /mnt /bin/bash -euo pipefail <<CHROOT
echo prime-vm > /etc/hostname
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen && locale-gen >/dev/null
echo LANG=en_US.UTF-8 > /etc/locale.conf
echo KEYMAP=$KB > /etc/vconsole.conf
mkdir -p /etc/X11/xorg.conf.d
printf 'Section "InputClass"\n    Identifier "system-keyboard"\n    MatchIsKeyboard "on"\n    Option "XkbLayout" "%s"\nEndSection\n' "$KB" > /etc/X11/xorg.conf.d/00-keyboard.conf
useradd -m -G wheel -s /bin/bash alex
echo 'alex:prime' | chpasswd
echo 'alex ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/10-prime-vm-test
chmod 440 /etc/sudoers.d/10-prime-vm-test
install -d -m 700 -o alex -g alex /home/alex/.ssh
echo "$PUBKEY" > /home/alex/.ssh/authorized_keys
chown alex:alex /home/alex/.ssh/authorized_keys; chmod 600 /home/alex/.ssh/authorized_keys
systemctl enable NetworkManager sshd >/dev/null 2>&1
bootctl install --esp-path=/boot --no-variables >/dev/null 2>&1
mkdir -p /boot/loader/entries
printf 'default cachyos.conf\ntimeout 1\n' > /boot/loader/loader.conf
printf 'title CachyOS (Prime VM test)\nlinux /vmlinuz-linux-cachyos\ninitrd /initramfs-linux-cachyos.img\noptions root=UUID=$ROOTUUID rootflags=subvol=@ rw console=ttyS0 console=tty0\n' > /boot/loader/entries/cachyos.conf
CHROOT
sync
umount -R /mnt
say "PRIME-VM-INSTALL: OK"
