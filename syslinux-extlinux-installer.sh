#!/bin/sh -e

# kiss filename problem - erroneous directory is created
# .../.cache/kiss/sources/syslinux/│/syslinux-6.04-pre1.tar.xz
# Note:
# “│” U+2502 Box Drawings Light Vertical 
# 
# Install worked with internal USB and failed with external USB however YMMV
#
# 'dmesg' errors with extlinux 6.04-pre1, mbr.bin & xfs (gptmbr.bin & xfs fails to boot properly)
# 'df' displays /dev/root (/dev/sda1)
# exFAT-fs (sda1): invalid boot record signature
# exFAT-fs (sda1): failed to read boot sector
# exFAT-fs (sda1): failed to recognize exfat type
#
# Dependencies
# util-linux perl nasm popt

VERSION=6.04
CHECKSUM=3f6d50a57f3ed47d8234fd0ab4492634eb7c9aaf7dd902f33d3ac33564fd631d

curl -fLO https://mirrors.edge.kernel.org/pub/linux/utils/boot/syslinux/Testing/$VERSION/syslinux-$VERSION-pre1.tar.xz

SHASUM=$(shasum -a 256 syslinux-$VERSION-pre1.tar.xz)

if [ "$SHASUM" = "$CHECKSUM  syslinux-$VERSION-pre1.tar.xz" ] ; then
echo "Signature OK"
else
exit 1
fi

tar xf syslinux-$VERSION-pre1.tar.xz

cd syslinux-$VERSION-pre1

# fix undefined reference to major
sed s'+#include <sys/stat.h>+#include <sys/stat.h>\
#include <sys/sysmacros.h>+' extlinux/main.c > _
mv -f _ extlinux/main.c

make bios installer

mkdir -p /boot/extlinux

# install ldlinux.c32 & ldlinux.sys
# extlinux --install /boot/extlinux --device /dev/sda1
bios/extlinux/extlinux --install /boot/extlinux

install -m644 bios/mbr/mbr.bin /boot/extlinux
install -m644 bios/com32/libutil/libutil.c32 /boot/extlinux
install -m644 bios/com32/lib/libcom32.c32 /boot/extlinux
install -m644 bios/com32/menu/menu.c32 /boot/extlinux
install -m644 bios/com32/menu/vesamenu.c32 /boot/extlinux
install -m644 sample/syslinux_splash.jpg /boot/extlinux
install -m644 sample/m16-640x640-syslinux.jpg /boot/extlinux

tee /boot/extlinux/extlinux.conf << EOF
ui vesamenu.c32
menu title Welcome To Kiss Linux
menu background m16-640x640-syslinux.jpg
timeout 50

label Kiss
menu label kernel-5.15.6
linux /boot/vmlinuz-5.15.6
append root=PARTUUID=$(blkid -s PARTUUID -o value /dev/sda1) ro
EOF

echo "##############################"
echo "# INSTALL MASTER BOOT RECORD #"
echo "##############################"
echo "Note: https://wiki.syslinux.org/wiki/index.php?title=Mbr"
echo "      dd is the "safe approach""
echo "cat /boot/extlinux/mbr.bin > /dev/sda"
echo "dd bs=440 count=1 if=/boot/extlinux/mbr.bin of=/dev/sda"
echo "##############################"
