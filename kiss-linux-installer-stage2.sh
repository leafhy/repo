#!/bin/sh -e

username=
home="/home/$username"
kver="linux-5.15.6"
kernel="https://cdn.kernel.org/pub/linux/kernel/v5.x/$kver.tar.xz"
#lver="linux-firmware-20211027"
linuxfirmware="https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/snapshot/$lver.tar.gz"
kissrepo="/var/db/kiss"
kiss_cache="$kissrepo/cache"

if [ ! "$username" ]; then
   echo "Missing username"
   exit
fi

user="$(getent passwd 1000 | cut -d: -f1)"

if [ ! "$user" ]; then
   adduser "$username"
   addgroup "$username" wheel
fi

if [ ! -f "$home/.profile" ]; then
tee $home/.profile << EOF
export KISS_DEBUG="0"
export KISS_SU="ssu"
export KISS_COMPRESS="zst"
export KISS_GET="curl"
export CFLAGS="-O3 -pipe -march=native"
export CXXFLAGS="$CFLAGS"
export MAKEFLAGS="-j$(nproc)"
export KISSREPO="/var/db/kiss"
export KISS_PATH="\$KISSREPO/repo/core:\$KISSREPO/repo/extra:\$KISSREPO/community/community"
alias ls="ls --color=auto"
EOF
fi

source /root/.profile

###############################################
#           Github & SSH Key Setup            #
###############################################
# Create ssh key and add to github.com account
# ssh-keygen -t ed25519 -C 'comment'
#
# Test ssh key works
# ssh -T git@github.com
#
# Clone repo using ssh key
# git clone git@github.com:leafhy/repo.git
#
# Create ~/.ssh/config
# -------------------------------------
# host github
# hostname github.com
# user git
# identityfile ~/.ssh/github-id_ed25519
# -------------------------------------
# Test ssh config works
# ssh -T github
#
# Clone repo using ssh config
# git clone github:leafhy/repo.git
#
# NOTE: Re-clone repo if permission denied occurs
# ie. repo out of sync
###############################################

if [ ! -d "$kissrepo/repo" ]; then
   git clone https://github.com/leafhy/repo.git $kissrepo/repo
   #git clone https://github.com/kisslinux/repo.git $kissrepo/repo
   git clone https://github.com/dylanaraps/community.git $kissrepo/community

   # fix git dubious permissions
   git config --global --add safe.directory "$kissrepo/repo"
   cp /root/.gitconfig "$home"
fi

kiss search \*

#kiss build gnupg1

#gpg --keyserver keyserver.ubuntu.com --recv-key 13295DAC2CF13B5C
#echo trusted-key 0x13295DAC2CF13B5C >> /root/.gnupg/gpg.conf

#cd $kissrepo/repo
#git config merge.verifySignatures true

kiss update

# Change cache location to one more apt for Single User
# and fix log permissions so builds don't fail
if [ "$kiss_cache" ] && [ ! -f "/usr/bin/kiss.orig" ]; then
   cp /usr/bin/kiss /usr/bin/kiss.orig

sed '/# SOFTWARE./a\
\
kiss_cache="/var/db/kiss/cache"\
\
uid="$(id | cut -d "(" -f 1)"\
\
if [ "$uid" != uid=0 ]; then\
   ssu chown -R 1000:1000 "$kiss_cache/logs"\
fi' /usr/bin/kiss > _
mv -f _ /usr/bin/kiss

sed 's/cac_dir=/#cac_dir=/g' /usr/bin/kiss > _
mv -f _ /usr/bin/kiss

sed '/Top-level cache/a\
    cac_dir=$kiss_cache' /usr/bin/kiss > _
mv -f _ /usr/bin/kiss

chmod +x /usr/bin/kiss
fi

kiss update

if [ -d "$kiss_cache" ]; then
   chown -R 1000:1000 "$kiss_cache"
fi

#cd /var/db/kiss/installed && kiss build *

# Install requisite packages
kiss build baseinit baselayout ssu efibootmgr intel-ucode tamsyn-font runit iproute2 zstd util-linux nasm popt

if [ "$kver" ] && [ ! "$kver.tar.xz" ]; then
   curl -fLO "$kernel"
fi

if [ -f "$kver.tar.xz" ]; then
   tar xf "$kver.tar.xz"
   cd  "$kver"
   cp "$kissrepo/repo/linux-kernel.config" .config

   sed '/<stdlib.h>/a #include <linux/stddef.h>' tools/objtool/arch/x86/decode.c > _
   mv -f _ tools/objtool/arch/x86/decode.c

   [ -f /usr/share/doc/kiss/wiki/kernel/patches/kernel-no-perl.patch ] && \
   patch -p1 < /usr/share/doc/kiss/wiki/kernel/patches/kernel-no-perl.patch

   [ -f /usr/share/doc/kiss/wiki/kernel/kernel-no-perl.patch ] && \
   patch -p1 < /usr/share/doc/kiss/wiki/kernel/kernel-no-perl.patch
fi

chown -R 1000:1000 "$home"

if [ "$lver" ]; then
   mkdir -p /usr/lib/firmware
   curl -fLO "$linuxfirmware"
   tar xf "$lver.tar.xz"
   # git clone https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git
   cp -R linux-firmware/intel /usr/lib/firmware/
fi

echo "#####################"
echo "#### FINAL STEPS ####"
echo "#####################"
echo "### Build & install kernel"
echo "cd $home/$kver"
echo "make && make install"
echo "cp /boot/vmlinuz /boot/efi/vmlinuz-5.15.6"
echo "cp /boot/System.map /boot/System.map-5.15.6"
echo "### Create boot entry for UEFI"
echo "./efiboot.sh"
echo "### Create boot entry for NON-UEFI"
echo "./syslinux-extlinux-installer.sh"
echo "#####################"
