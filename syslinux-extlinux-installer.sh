#!/bin/sh -e

# kiss build failed with no error messages hence this script
# 
# Install worked with internal USB and failed with external USB however YMMV

# Dependencies
kiss b util-linux perl nasm popt

VERSION=6.04
CHECKSUM=3f6d50a57f3ed47d8234fd0ab4492634eb7c9aaf7dd902f33d3ac33564fd631d

curl -fLO https://mirrors.edge.kernel.org/pub/linux/utils/boot/syslinux/Testing/$VERSION/syslinux-$VERSION-pre1.tar.xz

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

install -Dm644 bios/mbr/mbr.bin /boot/extlinux/mbr.bin
install -Dm644 bios/com32/libutil/libutil.c32 /boot/extlinux/libutil.c32
install -Dm644 bios/com32/lib/libcom32.c32 /boot/extlinux/libcom32.c32
install -Dm644 bios/com32/menu/menu.c32 /boot/extlinux/menu.c32
install -Dm644 bios/com32/menu/vesamenu.c32 /boot/extlinux/vesamenu.c32
install -Dm644 sample/syslinux_splash.jpg /boot/extlinux/syslinux_splash.jpg
install -Dm644 sample/m16-640x640-syslinux.jpg /boot/extlinux/m16-640x640-syslinux.jpg

tee /boot/extlinux/extlinux.conf <<EOF
ui vesamenu.c32
menu title Welcome To Kiss Linux
menu background m16-640x640-syslinux.jpg
timeout 50

label Kiss
menu label kernel-5.15.6_1
linux /boot/vmlinuz-5.15.6_1
EOF

partuuid=$(blkid -s PARTUUID -o value /dev/sda1)
echo "append root=PARTUUID=$partuuid ro" >> /boot/extlinux/extlinux.conf

# install master boot record
# Note: https://wiki.syslinux.org/wiki/index.php?title=Mbr
#       dd is the "safe approach"
# cat mbr.bin > /dev/sda 
# dd bs=440 count=1 if=/boot/extlinux/mbr.bin of=/dev/sda