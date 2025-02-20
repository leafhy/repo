#!/bin/bash

set -e

# This script has been used with:

# Systemrescue 8.05 (contains all commands)
# https://www.system-rescue.org/

# Void Linux musl (some commands need installing)
# https://voidlinux.org/

# NOTE: EXTLINUX [6.03+] supports: FAT12/16/32, NTFS, ext2/3/4, Btrfs, XFS, UFS/FFS.
#     : f2fs is not compatable with extlinux.
#     : setcap(libcap) uses filesystem xattrs.

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
kissrepo="/var/db/kiss"
kiss_cache="/var/db/kiss/cache"

# NOTE: Leave "kiss_cache" empty for default cache locations.
#       '$HOME/.cache/kiss' '/root/.cache/kiss'

# kiss-chroot-2021.7-9.tar.xz
checksum=3f4ebe1c6ade01fff1230638d37dea942c28ef85969b84d6787d90a9db6a5bf5

if mountpoint -q /mnt; then
   echo -e "\e[1;31m[ ERR: /mnt is already mounted. ]\e[0m"
   exit 1
fi

if ! [[ -f $file ]]; then
   echo -e "\e[1;92m[ INFO: Downloading fallback -> $file... ]\e[0m"
   wget "$url/$file" || curl -fLO "$url/$file"
   echo '--------------------------------------------'
fi

if [[ -z $checksum ]]; then
   echo -e "\e[1;92m[ INFO: Downloading checksum -> $file.sha256... ]\e[0m"
   wget "$url/$file.sha256" || curl -fLO "$url/$file.sha256"
   echo '--------------------------------------------'
fi

if [[ $file = kiss-chroot-$chrootver.tar.xz && $checksum ]]; then
   echo -e "\e[1;92m[ INFO: Verifying $file checksum... ]\e[0m"
   sha256sum -c <(echo "$checksum  $file") || exit 1
   echo '--------------------------------------------'
fi

if [[ -f $file.sha256 ]]; then
   echo -e "\e[1;92m[ INFO: Verifying $file checksum... ]\e[0m"
   sha256sum -c < "$file.sha256" || exit 1
   echo '--------------------------------------------'
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
PS3="Select drive for installing KISS Linux: "
echo ''
select device in $(blkid | grep -e sd | cut -d : -f 1 | sed -e 's/[1-9]\+$//' | uniq | sort)
do
if [[ $device = "" ]]; then
echo "try again"
continue
fi
break
done

echo -e "\e[1;92m[ INFO: $device has been selected. ]\e[0m"

# Detect if we're in UEFI or legacy mode.
[[ -d /sys/firmware/efi ]] && UEFI=1

if [[ $UEFI ]]; then
   echo -e "\e[1;92m[ INFO: EFI has been found. ]\e[0m"
else
   echo -e "\e[1;31m[ INFO: EFI not found. ]\e[0m"
fi

# Partition selection.
if [[ $UEFI ]]; then
PS3="Select partition type or ABORT: "
select opt in EFI MBR ABORT
do

if [[ $opt = "" ]]; then
echo "try again"
continue
fi
break
done
fi

if [[ -z $UEFI ]]; then
PS3="Select partition type or ABORT: "
select opt in MBR ABORT
do

if [[ $opt = "" ]]; then
echo "try again"
continue
fi
break
done

fi

[[ $opt = ABORT ]] && exit 1

echo '--------------------------------------------'
echo ''
echo -e "\e[1;92m[ INFO: Listing \"$device\" filesystems. ]\e[0m"
wipefs $device*
echo ''
echo "Note: Use \"wipefs --all $device\" if hardrive fails to format properly."
echo ''
echo '--------------------------------------------'

# Filesystem creation.
read -p "Do you want to format $device? [yes/No]: "
if [[ $REPLY =~ ^([Yy][Ee][Ss])$ ]]; then
if [[ $opt = EFI ]]; then
   sgdisk --zap-all $device
   sgdisk -n 1:2048:96M -t 1:ef00 $device
   sgdisk -n 2:0:0 -t 2:8300 $device
   sgdisk --verify $device

   mkfs.vfat -F 32 -n EFI ${device}1
   mkfs.$efifsys $efifsysopts ${device}2

elif [[ $opt = MBR ]]; then
     echo "[ ! ] CREATE 'DOS' PARTITION & MAKE BOOT ACTIVE [ ! ]"
     fdisk $device
     mkfs.$extfsys $extfsysopts ${device}1
fi
fi

# Mount the filesystems.
if [[ $opt = EFI ]]; then
   mount ${device}2 /mnt
   mkdir -p /mnt/boot/efi
   mount ${device}1 /mnt/boot/efi

elif [[ $opt = MBR ]]; then
     mount ${device}1 /mnt
fi

# Extract 'KISS Linux' to filesystem.
if ! [[ -d /mnt/usr ]]; then
   echo  -e "\e[1;92m[ INFO: Extracting $file... ]\e[0m"
   tar xf "$file" -C /mnt --strip-components=1
   echo '--------------------------------------------'
fi

if ! [[ -f /mnt/root/.profile ]]; then
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
fi

# Change cache location to one more apt for Single User.
kisschecksumA=6ff56f886ca76d93b0c88ffae267432474fb38399b151ccbacf519869114e234 # 5.5.14.tar.gz -> kiss
kisschecksumB=$(sha256sum /mnt/usr/bin/kiss | cut -d' ' -f1)

if [[ $kiss_cache && $file = kiss-chroot-2021.7-9.tar.xz && $kisschecksumA = $kisschecksumB ]]; then
   sed 's/cac_dir=/#cac_dir=/g' /mnt/usr/bin/kiss > _
   mv -f _ /mnt/usr/bin/kiss

   sed "/Top-level cache/a\
   cac_dir=$kiss_cache" /mnt/usr/bin/kiss > _
   mv -f _ /mnt/usr/bin/kiss
   chmod +x /mnt/usr/bin/kiss
fi

# Create 'src/' for tarballs, etc needed for installing 'KISS Linux'.
   mkdir -p /mnt/$kissrepo/src
   echo  -e "\e[1;92m[ INFO: Transferring $file... ]\e[0m"
   cp --verbose --no-clobber "$file" /mnt/$kissrepo/src
   echo '--------------------------------------------'

# Remove unneeded directories + broken symbolic link.
[[ -d /mnt/usr/local ]] && rm -r /mnt/usr/local

if ! [[ -f /mnt/etc/fstab.orig ]]; then
   cp /mnt/etc/fstab /mnt/etc/fstab.orig

if [[ $opt = EFI ]]; then
tee --append /mnt/etc/fstab << EOF >/dev/null

LABEL=EFI        /boot/efi    vfat    defaults    0 0

# UUID=$(blkid -s UUID -o value ${device}2)
LABEL=$fsyslabel /           $efifsys    defaults    0 0
EOF
elif [[ $opt = MBR ]]; then
tee --append /mnt/etc/fstab << EOF >/dev/null

# UUID=$(blkid -s UUID -o value ${device}1)
LABEL=$fsyslabel    $extfsys    defaults    0 0
EOF
fi
fi

if ! [[ -f /mnt/etc/hostname ]]; then
   printf '%s\n' $hostname > /mnt/etc/hostname
fi

if ! [[ -f /mnt/etc/resolv.conf.orig ]]; then
   printf '%s\n' "nameserver $nameserver" > /mnt/etc/resolv.conf.orig
   # NOTE: 'kiss-chroot' will overwrite '/etc/resolv.conf'
   #       and apon exiting chroot, '/etc/resolv.conf' will be deleted.
fi

mkdir -p /mnt/etc/rc.d

if ! [[ -f /mnt/etc/rc.d/setup.boot ]]; then
tee /mnt/etc/rc.d/setup.boot << EOF >/dev/null
# Set font for tty1..tty6
log "Setting up tty..."
for i in \`seq 1 6\`; do
  setfont /usr/share/consolefonts/Tamsyn8x16r.psf.gz -C /dev/tty\$i
done

# Setup network
log "Setting up network..."
ip link set dev eth0 up
ip addr add $ipaddress/24 brd + dev eth0
ip route add default via $nameserver

# Ethernet on server board is slow to start thus
# sleep keeps log messages from overriding login prompt.
sleep 4

EOF

tee --append /mnt/etc/rc.d/setup.boot << 'EOF' >/dev/null
# Setup zram if totalmem is => 8GB
# https://stackoverflow.com/questions/20348007/how-can-i-find-out-the-total-physical-memory-ram-of-my-linux-box-suitable-to-b/53186875#53186875
if [ -b /dev/zram0 ]; then
totmem=0
for mem in /sys/devices/system/memory/memory*; do
  [ "$(cat ${mem}/online)" = "1" ] && totalmem=$((totalmem+$((0x$(cat /sys/devices/system/memory/block_size_bytes)))))
done

if ! [ "$(( totalmem / 1024 ** 3 ))" -lt "8" ]; then
   log "Setting up zram..."
   zramsize=$(printf "$(awk '/MemTotal/ { print $2 }' /proc/meminfo) * 1.5 / 1024 / 1024" | bc) &&
   echo "${zramsize}"G > /sys/block/zram0/disksize &&
   [ -x /usr/bin/mkfs.xfs ] &&
   mkfs.xfs -m finobt=0,reflink=0,rmapbt=0 /dev/zram0 >/dev/null &&
   mount -t xfs -o discard /dev/zram0 /var/db/kiss/cache/proc &&
   chown 1000:1000 /var/db/kiss/cache/proc
fi
fi

dmesg >/var/log/dmesg.log
EOF
fi

if [[ $opt = EFI && ! -f /mnt/efiboot.sh ]]; then
tee /mnt/efiboot.sh << EOF >/dev/null
#!/bin/sh

device=$device
efilabel=$efilabel
kver=$kver

EOF

tee --append /mnt/efiboot.sh << 'EOF' >/dev/null
# void linux
# initramfs uses 'UUID'
#efibootmgr -c -d /dev/sda -p 1 -l '\vmlinuz-5.7.7_1' -L 'Void' initrd=\initramfs-5.7.7_1.img root=/dev/sda2

# kiss linux
# Kernel panic will occur without unicode -> unable to find root
# 'PARTUUID' is used as initramfs is required to use 'UUID'
efibootmgr --create --disk $device --loader \vmlinuz-$kver --label $efilabel --unicode root=PARTUUID=$(blkid -s PARTUUID -o value ${device}2) loglevel=4 Page_Poison=1

echo '******************************************'
echo ''
echo -e "\x1B[1;31m[ ! ] Check\x1B[1;92m BootOrder:\x1B[1;31m is correct [ ! ]\x1B[1;0m"
echo ''
echo '******************************************'
echo ''
echo 'Note: Boot entry needs to be towards the top of list'
echo '      otherwise it will not appear in the UEFI boot menu.'
echo ''
efibootmgr
EOF
chmod +x /mnt/efiboot.sh
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

