#!/bin/bash
set -e
#
# Script used with systemrescue 8.05 (contains all commands) & void linux musl (some commands need installing)
# https://www.system-rescue.org/ 
# https://voidlinux.org/
#
# [!] EXTLINUX [6.03+] supports: FAT12/16/32, NTFS, ext2/3/4, Btrfs, XFS, UFS/FFS [!]
# [!] f2fs is not compatable with extlinux [!]

efikver=5.15.6
efilabel=KISS_LINUX
fsyslabel=KISS_LINUX
chrootver=2021.7-9
url=https://github.com/kisslinux/repo/releases/download/$chrootver
file=kiss-chroot-$chrootver.tar.xz
ipaddress=192.168.1.XX
nameserver=192.168.1.1
home=/mnt/root
#fsys=f2fs
#fsysopts="-O extra_attr,sb_checksum,inode_checksum,lost_found -f -l $fsyslabel"
fsys=xfs
fsysopts="-f -L $fsyslabel"
# /usr/bin/kiss cache default locations "$HOME/.cache/kiss" "/root/.cache/kiss"
kiss_cache="/var/db/kiss/cache" 

wget "$url/$file" || curl -fLO "$url/$file"
wget "$url/$file.sha256" || curl -fLO "$url/$file.sha256"

sha256sum -c < "$file.sha256"

#curl -fLO "$url/$file.asc"
#gpg --keyserver keyserver.ubuntu.com --recv-key 13295DAC2CF13B5C
#gpg --verify "$file.asc"

lsblk -f -l | grep sd

echo '****************************************'
echo '[!] Verify Connected Drive Is Listed [!]'
echo '****************************************'
# Generate drive options dynamically
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
echo "May need to use "wipefs --all $device" if hardrive fails to format properly"
wipefs $device*
echo '--------------------------------------------'

# Detect if we're in UEFI or legacy mode
[[ -d /sys/firmware/efi ]] && UEFI=1

if [[ $UEFI ]]; then
sgdisk --zap-all $device
sgdisk -n 1:2048:550M -t 1:ef00 $device
sgdisk -n 2:0:0 -t 2:8300 $device
sgdisk --verify $device

mkfs.vfat -F 32 -n EFI ${device}1
mkfs.$fsys $fsysopts ${device}2
mount ${device}2 /mnt
rootuuid=$(blkid -s UUID -o value ${device}2)
partuuid=$(blkid -s PARTUUID -o value ${device}2)
else
echo "[ ! ] EFI NOT FOUND [ ! ]"
echo ""
echo "[ ! ] CREATE 'DOS' PARTITION & MAKE BOOT ACTIVE [ ! ]"
fdisk $device
mkfs.$fsys $fsysopts ${device}1
mount ${device}1 /mnt
rootuuid=$(blkid -s UUID -o value ${device}1)
partuuid=$(blkid -s PARTUUID -o value ${device}1)
fi

tar xvf /root/$file -C /mnt --strip-components=1

if [[ $UEFI ]]; then
mkdir /mnt/boot/efi
mount ${device}1 /mnt/boot/efi
tee --append /mnt/etc/fstab << EOF
LABEL=EFI         /boot/efi   vfat    defaults     0 0
UUID=$rootuuid    /           $fsys   defaults     0 0
EOF
else
echo "UUID=$rootuuid    /           $fsys   defaults     0 0" >> /mnt/etc/fstab
fi

echo "nameserver $nameserver" >> /mnt/etc/resolv.conf

mkdir -p /mnt/etc/rc.d

tee /mnt/etc/rc.d/setup.boot << EOF
# Set font for tty1..tty6
for i in \`seq 1 6\`; do
  setfont /usr/share/consolefonts/Tamsyn8x16r.psf.gz -C /dev/tty$i
done

# Setup network
ip link set dev eth0 up
ip addr add $ipaddress/24 brd + dev eth0
ip route add default via $nameserver

# Ethernet on server board is slow to start thus
# sleep keeps log messages from overriding login prompt
sleep 4

dmesg >/var/log/dmesg.log
EOF

if [[ $UEFI ]]; then
tee /mnt/efiboot.sh << EOF
#!/bin/sh

# void linux
# can use UUID
#efibootmgr -c -d /dev/sda -p 1 -l '\vmlinuz-5.7.7_1' -L 'Void' initrd=\initramfs-5.7.7_1.img root=/dev/sda2

# kiss linux
# Kernel panic will occur without unicode - unable to find root
# PARTUUID is used as UUID doesn't work
efibootmgr --create --disk /dev/sda --loader '\vmlinuz-$efikver' --label '$efilabel' --unicode root=PARTUUID=$partuuid loglevel=4 Page_Poison=1

echo '**********************************************************'
echo -e "[!] Check \x1B[1;92m BootOrder: \x1B[1;0m is correct [!]"
echo ' Boot entry needs to be towards the top of list otherwise '
echo '       it will not appear in the boot menu                '
echo '**********************************************************'
echo '**********************************************************'
echo '      Resetting BIOS will restore default boot order      '
echo '**********************************************************'
efibootmgr -v
EOF
fi

tee $home/.profile << EOF
export KISS_DEBUG=0
export KISS_COMPRESS=gz
export KISS_GET=curl
export CFLAGS="-O3 -pipe -march=native"
export CXXFLAGS="$CFLAGS"
export MAKEFLAGS="-j$(nproc)"
export KISSREPO="/var/db/kiss"
export KISS_PATH="\$KISSREPO/repo/core:\$KISSREPO/repo/extra:\$KISSREPO/community/community"
alias ls="ls --color=auto"
EOF

# Change cache location to one more apt for Single User
if [[ $kiss_cache ]]; then
sed 's/cac_dir=/#cac_dir=/g' /mnt/usr/bin/kiss > _
mv -f _ /mnt/usr/bin/kiss

sed '/Top-level cache/a\
    cac_dir=$kiss_cache' /mnt/usr/bin/kiss > _
mv -f _ /mnt/usr/bin/kiss
chmod +x /mnt/usr/bin/kiss
fi

echo "#####################"
echo "#### FINAL STEPS ####"
echo "#####################"
echo "Copy kiss-linux-installer-stage2.sh to /mnt"
echo "cp kiss-linux-installer-stage2.sh /mnt"
echo "### Enter chroot"
echo "/mnt/bin/kiss-chroot /mnt"
echo "### Make kiss-linux-installer-stage2.sh executable"
echo "chmod +x kiss-linux-installer-stage2.sh"
echo "### Run kiss-linux-installer-stage2.sh"
echo "./kiss-linux-installer-stage2.sh"
echo "#####################"
