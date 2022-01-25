#!/bin/bash
set -e
#
# Script used with systemrescue 8.05 (contains all commands) & void linux musl (some commands need installing)
# https://www.system-rescue.org/ 
# https://voidlinux.org/

chrootver=2021.7-9
url=https://github.com/kisslinux/repo/releases/download/$chrootver
file=kiss-chroot-$chrootver.tar.xz
fsys=f2fs
label=KISS_LINUX
fsysopts="-O extra_attr,sb_checksum,inode_checksum,lost_found -f -l $label"
stage2=/root/kiss-linux-installer-stage2.sh

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
sgdisk --zap-all $device
sgdisk -n 1:2048:550M -t 1:ef00 $device
sgdisk -n 2:0:0 -t 2:8300 $device
sgdisk --verify $device

mkfs.vfat -F 32 -n EFI ${device}1
mkfs.$fsys $fsysopts ${device}2

mount ${device}2 /mnt

tar xvf /root/$file -C /mnt --strip-components=1

mkdir /mnt/boot/efi

mount ${device}1 /mnt/boot/efi

rootuuid=$(blkid -s UUID -o value ${device}2)
partuuid=$(blkid -s PARTUUID -o value ${device}2)

tee --append /mnt/etc/fstab <<EOF
LABEL=EFI         /boot/efi   vfat    defaults     0 0
UUID=$rootuuid    /           $fsys   defaults     0 0 
EOF

tee /mnt/efiboot.sh << EOF
#!/bin/sh

# void linux
# can use UUID
#efibootmgr -c -d /dev/sda -p 1 -l '\vmlinuz-5.7.7_1' -L 'Void' initrd=\initramfs-5.7.7_1.img root=/dev/sda2

# kiss linux
# Kernel panic will occur without unicode - unable to find root
# need to use PARTUUID
#efibootmgr --create --disk /dev/sda --loader '\vmlinuz-5.15.6' --label 'KISS LINUX' --unicode root=PARTUUID=$partuuid loglevel=4 Page_Poison=1
EOF

cp $stage2 /mnt

#/mnt/bin/kiss-chroot /mnt
