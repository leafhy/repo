#!/bin/bash
set -e
#
# Script used with systemrescue 8.05 (contains all commands) & void linux musl (some commands need installing)
# https://www.system-rescue.org/ 
# https://voidlinux.org/
#
# Note: ext4 on usb/sdcard has a tendancy to corrupt

chrootver=2021.7-9
url=https://github.com/kisslinux/repo/releases/download/$chrootver
file=kiss-chroot-$chrootver.tar.xz
fsys=f2fs
label=KISS_LINUX
fsysopts="-O extra_attr,sb_checksum,inode_checksum,lost_found -f -l $label"
nameserver=192.168.1.1

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
# sed removes the single partition number:
# sda1 > sda
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
echo "May need to use [ wipefs --all $device ] if hardrive fails to format properly"
wipefs $device*
echo '--------------------------------------------'
sleep 5

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
echo "[ ! ] CREATE 'DOS' PARTITION & MAKE BOOT ACTIVE [ ! ]"
fdisk $device
mkfs.$fsys $fsysopts ${device}1"
mount ${device}1 /mnt
rootuuid=$(blkid -s UUID -o value ${device}1)
partuuid=$(blkid -s PARTUUID -o value ${device}1)
fi

tar xvf /root/$file -C /mnt --strip-components=1

if [[ $UEFI ]]; then
mkdir /mnt/boot/efi
mount ${device}1 /mnt/boot/efi
tee --append /mnt/etc/fstab <<EOF
LABEL=EFI         /boot/efi   vfat    defaults     0 0
UUID=$rootuuid    /           $fsys   defaults     0 0
EOF
else
echo "UUID=$rootuuid    /           $fsys   defaults     0 0" >> /mnt/etc/fstab
fi

echo "nameserver $nameserver" >> /mnt/etc/resolv.conf

mkdir -p /mnt/etc/rc.d

tee /mnt/etc/rc.d/setup.boot <<EOF
# Set font for tty1..tty6
for i in `seq 1 6`; do
  setfont /usr/share/consolefonts/Tamsyn8x16r.psf.gz -C /dev/tty$i
done

# Setup network
ip link set dev eth0 up
ip addr add 192.168.1.XX/24 brd + dev eth0
ip route add default via 192.168.1.1

# Ethernet on server board is slow to start thus
# sleep keeps log messages from overriding login prompt
sleep 4

dmesg >/var/log/dmesg.log
EOF

source $home/.profile

if [[ $UEFI ]]; then
tee /mnt/efiboot.sh << EOF
#!/bin/sh

# void linux
# can use UUID
#efibootmgr -c -d /dev/sda -p 1 -l '\vmlinuz-5.7.7_1' -L 'Void' initrd=\initramfs-5.7.7_1.img root=/dev/sda2

# kiss linux
# Kernel panic will occur without unicode - unable to find root
# PARTUUID is used as UUID doesn't work
efibootmgr --create --disk /dev/sda --loader '\vmlinuz-5.15.6' --label 'KISS LINUX' --unicode root=PARTUUID=$partuuid loglevel=4 Page_Poison=1
EOF
fi

tee /mnt/kiss-linux-installer-stage2.sh <<EOF
#!/bin/sh -e
username=
home=/home/$username
#kver=linux-5.15.6
kernel=https://cdn.kernel.org/pub/linux/kernel/v5.x/$kver.tar.xz
#lver=linux-firmware-20211027
linuxfirmware=https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/snapshot/$lver.tar.gz
kissrepo=/var/db/kiss
hostname=kiss

adduser $username

git clone https://github.com/leafhy/repo.git $kissrepo/repo
#git clone https://github.com/kisslinux/repo.git $kissrepo/repo
git clone https://github.com/dylanaraps/community.git $kissrepo/community

kiss search \*

#cd $kissrepo/repo
#git config merge.verifySignatures true

#kiss build gnupg1$kissrepo/repo
#gpg --keyserver keyserver.ubuntu.com --recv-key 13295DAC2CF13B5C
#echo trusted-key 0x13295DAC2CF13B5C >> /root/.gnupg/gpg.conf

#kiss update
#cd /var/db/kiss/installed && kiss build *

#kiss build baseinit libelf

printf '%s\n' $hostname > /etc/hostname

if [[ $kver ]]; then
cd $home
curl -fLO $kernel
tar xf $kver.tar.xz
cd  $kver
sed '/<stdlib.h>/a #include <linux/stddef.h>' tools/objtool/arch/x86/decode.c > _
mv -f _ tools/objtool/arch/x86/decode.c
fi

if [[ $kver && -f /usr/share/doc/kiss/wiki/kernel/patches/kernel-no-perl.patch ]]; then
patch -p1 < /usr/share/doc/kiss/wiki/kernel/patches/kernel-no-perl.patch
fi

if [[ $kver && -f /usr/share/doc/kiss/wiki/kernel/kernel-no-perl.patch ]]; then
patch -p1 < /usr/share/doc/kiss/wiki/kernel/kernel-no-perl.patch
fi

if [[ $lver ]]; then 
mkdir -p /usr/lib/firmware
curl -fLO $linuxfirmware
tar xf $lver.tar.xz
# git clone https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git
cp -R linux-firmware/intel /usr/lib/firmware/
fi
EOF

tee $home/.profile <<EOF
export CFLAGS="-O3 -pipe -march=native"
export CXXFLAGS="$CFLAGS"
export MAKEFLAGS="-j$(nproc)"
export KISSREPO="/var/db/kiss"
export KISS_PATH="\$KISSREPO/repo/core:\$KISSREPO/repo/extra:\$KISSREPO/community/community"
EOF

#/mnt/bin/kiss-chroot /mnt
