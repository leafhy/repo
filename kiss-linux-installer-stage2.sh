#!/bin/sh -e
username=
home=/home/$username
# Uncomment kver to download and patch kernel
# Building kernel requires "linux-5.15.6/.config"
#kver=linux-5.15.6
kernel=https://cdn.kernel.org/pub/linux/kernel/v5.x/$kver.tar.xz
#lver=linux-firmware-20211027
linuxfirmware=https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/snapshot/$lver.tar.gz
kissrepo=/var/db/kiss
kiss_cache=$kissrepo/cache
hostname=kiss

adduser $username
addgroup $username wheel

tee $home/.profile << EOF
export KISS_DEBUG=0
export KISS_COMPRESS=zst
export KISS_GET=curl
export CFLAGS="-O3 -pipe -march=native"
export CXXFLAGS="$CFLAGS"
export MAKEFLAGS="-j$(nproc)"
export KISSREPO="/var/db/kiss"
export KISS_PATH="\$KISSREPO/repo/core:\$KISSREPO/repo/extra:\$KISSREPO/community/community"
alias ls="ls --color=auto"
EOF

source /root/.profile

git clone https://github.com/leafhy/repo.git $kissrepo/repo
#git clone https://github.com/kisslinux/repo.git $kissrepo/repo
git clone https://github.com/dylanaraps/community.git $kissrepo/community

for f in build post-install pre-remove; do
find $kissrepo/repo -name $f -exec chmod +x {} +
done

kiss search \*

#cd $kissrepo/repo
#git config merge.verifySignatures true

#kiss build gnupg1$kissrepo/repo
#gpg --keyserver keyserver.ubuntu.com --recv-key 13295DAC2CF13B5C
#echo trusted-key 0x13295DAC2CF13B5C >> /root/.gnupg/gpg.conf

kiss update

# Change cache location to one more apt for Single User
if [[ $kiss_cache ]]; then
sed 's/cac_dir=/#cac_dir=/g' /usr/bin/kiss > _
mv -f _ /usr/bin/kiss

sed '/Top-level cache/a\
    cac_dir=/var/db/kiss/cache' /usr/bin/kiss > _
mv -f _ /usr/bin/kiss
chmod +x /usr/bin/kiss
fi

kiss update

#cd /var/db/kiss/installed && kiss build *

kiss build baseinit ssu efibootmgr intel-ucode tamsyn-font runit iproute2 zstd

printf '%s\n' $hostname > /etc/hostname

if [[ $kver ]]; then
cd $home
curl -fLO $kernel
tar xf $kver.tar.xz
cd  $kver
cp $kissrepo/repo/linux-kernel.config .config
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
echo "#####################"
echo "#### FINAL STEPS ####"
echo "#####################"
echo "### Build & install kernel"
echo "make && make install"
echo "mv /boot/vmlinuz /boot/efi/vmlinuz-5.15.6"
echo "mv /boot/System.map /boot/System.map-5.15.6"
echo "### Create boot entry for UEFI"
echo "./efiboot.sh"
echo "### Create boot entry for NON-UEFI"
echo "./syslinux-extlinux-installer.sh"
echo "#####################"
