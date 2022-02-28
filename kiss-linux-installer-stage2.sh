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

tee $home/.profile <<EOF
export CFLAGS="-O3 -pipe -march=native"                                                                                                                                                                           
export CXXFLAGS="$CFLAGS"                                                                                                                                                                                         
export MAKEFLAGS="-j$(nproc)"                                                                                                                                                                                     
export KISSREPO="/var/db/kiss"                                                                                                                                                                                    
export KISS_PATH="\$KISSREPO/repo/core:\$KISSREPO/repo/extra:\$KISSREPO/community/community"                                                                                                                      
EOF     

source $home/.profile

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
