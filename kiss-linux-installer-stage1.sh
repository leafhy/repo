#!/bin/bash

set -e

# This script has been used with:

# Systemrescue 8.05 (contains all commands)
# https://www.system-rescue.org/

# Void Linux musl (some commands need installing)
# https://voidlinux.org/

# NOTE: EXTLINUX [6.03+] supports: FAT12/16/32, NTFS, ext2/3/4, Btrfs, XFS, UFS/FFS.
#       f2fs is not compatable with extlinux.

kver=5.15.6
efilabel=KISS_LINUX-$kver
fsyslabel=KISS_LINUX
chrootver=2021.7-9
url=https://github.com/kisslinux/repo/releases/download/$chrootver
file=${1-kiss-chroot-$chrootver.tar.xz}
ipaddress=192.168.1.XX
nameserver=192.168.1.1
hostname=kiss
efifsys=f2fs
efifsysopts="-O extra_attr,sb_checksum,inode_checksum,lost_found -f -l $fsyslabel"
extfsys=xfs
extfsysopts="-f -L $fsyslabel"
# NOTE: Leave "kiss_cache" empty for default cache locations.
#       '$HOME/.cache/kiss' '/root/.cache/kiss'
kiss_cache="/var/db/kiss/cache"
kissrepo="/var/db/kiss"

# kiss-chroot-2021.7-9.tar.xz
checksum=3f4ebe1c6ade01fff1230638d37dea942c28ef85969b84d6787d90a9db6a5bf5

if [[ ! -f $file ]]; then
   wget "$url/$file" || curl -fLO "$url/$file"
fi

if [[ -z $checksum ]]; then
   wget "$url/$file.sha256" || curl -fLO "$url/$file.sha256"
fi

if [[ $file = kiss-chroot-$chrootver.tar.xz ]] && [[ $checksum ]]; then
   sha256sum -c <(echo "$checksum  $file") || exit 1
fi

if [[ -f $file.sha256 ]]; then
   sha256sum -c < "$file.sha256" || exit 1
fi

#curl -fLO "$url/$file.asc"
#gpg --keyserver keyserver.ubuntu.com --recv-key 13295DAC2CF13B5C
#gpg --verify "$file.asc"

echo '********************************************'
echo '                                            '
echo '[ ! ] Verify listed drives are correct [ ! ]'
echo '                                            '
echo '********************************************'
lsblk -f -l | grep sd

# Generate drive options dynamically.
PS3="Select drive to format: "
echo ''
select device in $(blkid | grep -e sd | cut -d : -f 1 | sed -e 's/[1-9]\+$//' | uniq | sort)
do
if [[ $device = "" ]]; then
echo "try again"
continue
fi
break
done
echo "$device has been selected"
echo ''
echo '--------------------------------------------'
echo ''
echo "NOTE: Use \"wipefs --all $device\" if hardrive fails to format properly."
echo ''
echo  "Showing \"wipefs $device*\" information."
wipefs $device*
echo ''
echo '--------------------------------------------'

# Detect if we're in UEFI or legacy mode.
[[ -d /sys/firmware/efi ]] && UEFI=1

# Creation of partitions & filesystems.
read -p 'Do you want to format "$device"? [yes/No]: '
if [[ $REPLY =~ ^([Yy][Ee][Ss])$ ]]; then
if [[ $UEFI ]]; then
   sgdisk --zap-all $device
   sgdisk -n 1:2048:550M -t 1:ef00 $device
   sgdisk -n 2:0:0 -t 2:8300 $device
   sgdisk --verify $device

   mkfs.vfat -F 32 -n EFI ${device}1
   mkfs.$efifsys $efifsysopts ${device}2
   mount ${device}2 /mnt
else
   echo "[ ! ] EFI NOT FOUND [ ! ]"
   echo ''
   echo "[ ! ] CREATE 'DOS' PARTITION & MAKE BOOT ACTIVE [ ! ]"
   fdisk $device
   mkfs.$extfsys $extfsysopts ${device}1
   mount ${device}1 /mnt
fi
fi

# Extract 'KISS Linux' filesystem.
tar xvf "$file" -C /mnt --strip-components=1

# Create 'src/' for tarballs, etc needed for installing 'KISS Linux'.
mkdir -p /mnt/$kissrepo/src
[[ ! -f /mnt/$kissrepo/src/$file ]] && cp --verbose "$file" /mnt/$kissrepo/src

# Remove unneeded directories + broken symbolic link.
[[ -d /mnt/usr/local ]] && rm -r /mnt/usr/local

if [[ $UEFI ]]; then
mkdir -p /mnt/boot/efi
mount ${device}1 /mnt/boot/efi
tee --append /mnt/etc/fstab << EOF >/dev/null
LABEL=EFI        /boot/efi    vfat    defaults    0 0

# UUID=$(blkid -s UUID -o value ${device}2)
LABEL=$fsyslabel /           $efifsys    defaults    0 0
EOF
else
tee --append /mnt/etc/fstab << EOF >/dev/null
# UUID=$(blkid -s UUID -o value ${device}1)
LABEL=$fsyslabel    $extfsys    defaults    0 0
EOF
fi

printf '%s\n' $hostname > /mnt/etc/hostname

# NOTE: 'kiss-chroot' will overwrite '/etc/resolv.conf'
#       and apon exiting chroot, '/etc/resolv.conf' will be deleted.
printf '%s\n' "nameserver $nameserver" > /mnt/etc/resolv.conf.orig

mkdir -p /mnt/etc/rc.d

tee /mnt/etc/rc.d/setup.boot << EOF >/dev/null
# Set font for tty1..tty6
for i in \`seq 1 6\`; do
  setfont /usr/share/consolefonts/Tamsyn8x16r.psf.gz -C /dev/tty\$i
done

# Setup network
ip link set dev eth0 up
ip addr add $ipaddress/24 brd + dev eth0
ip route add default via $nameserver

# Ethernet on server board is slow to start thus
# sleep keeps log messages from overriding login prompt.
sleep 4

dmesg >/var/log/dmesg.log
EOF

if [[ $UEFI ]]; then
tee /mnt/efiboot.sh << EOF >/dev/null
#!/bin/sh

# void linux
# initramfs uses 'UUID'
#efibootmgr -c -d /dev/sda -p 1 -l '\vmlinuz-5.7.7_1' -L 'Void' initrd=\initramfs-5.7.7_1.img root=/dev/sda2

# kiss linux
# Kernel panic will occur without unicode -> unable to find root
# 'PARTUUID' is used as initramfs is required to use 'UUID'
efibootmgr --create --disk /dev/sda --loader '\vmlinuz-$kver' --label '$efilabel' --unicode root=PARTUUID=$(blkid -s PARTUUID -o value ${device}2) loglevel=4 Page_Poison=1

echo '******************************************'
echo ''
echo -e "\x1B[1;31m [ ! ] Check \x1B[1;92m BootOrder: \x1B[1;31m is correct [ ! ]\x1B[1;0m"
echo ''
echo '******************************************'
echo ''
echo 'NOTE: Boot entry needs to be towards the top of list'
echo '      otherwise it will not appear in the boot menu.'
echo ''
efibootmgr
EOF
chmod +x /mnt/efiboot.sh
fi

tee /mnt/root/.profile << EOF >/dev/null
export KISS_DEBUG="0"
export KISS_COMPRESS="gz"
export KISS_GET="curl"
export CFLAGS="-O2 -pipe -march=x86-64 -mtune=generic"
#export CFLAGS="-O3 -pipe -march=native"
export CXXFLAGS="\$CFLAGS"
export MAKEFLAGS="-j\$(nproc)"
export KISSREPO="$kissrepo"
export KISS_PATH="\$KISSREPO/repo/core:\$KISSREPO/repo/extra:\$KISSREPO/community/community"
alias ls="ls --color=auto"
EOF

# Change cache location to one more apt for Single User.
if [[ $kiss_cache ]]; then
   sed 's/cac_dir=/#cac_dir=/g' /mnt/usr/bin/kiss > _
   mv -f _ /mnt/usr/bin/kiss

   sed "/Top-level cache/a\
 cac_dir=$kiss_cache" /mnt/usr/bin/kiss > _
   mv -f _ /mnt/usr/bin/kiss
   chmod +x /mnt/usr/bin/kiss
fi

echo "#####################"
echo "#### FINAL STEPS ####"
echo "#####################"
echo "### Copy stage2 installer to /mnt"
echo "cp kiss-linux-installer-stage2.sh /mnt"
echo ''
echo "### Enter chroot"
echo "/mnt/bin/kiss-chroot /mnt"
echo ''
echo "### Run stage2 installer"
echo "./kiss-linux-installer-stage2.sh"
echo "#####################"
echo '++ EOF ++'

