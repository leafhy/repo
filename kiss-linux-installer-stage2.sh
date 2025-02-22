#!/bin/sh -e

username=
home="/home/$username"
kver="5.15.6"
kernel="https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-$kver.tar.xz"
#lver="linux-firmware-20211027"
linuxfirmware="https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/snapshot/$lver.tar.gz"
kissrepo="/var/db/kiss"
kiss_cache="$kissrepo/cache"

while true; do
read -p "Create user now? [yes/no]: "  ans
case "$ans" in

[Yy][Ee][Ss] )

if [ -z "$username" ]; then
   printf '\033[31;1m[ ERR: Missing username ]\033[m\n'
   exit 1
fi

user="$(getent passwd | cut -d: -f1 | grep $username || :)"
#user="$(getent passwd 1000 | cut -d: -f1)"

if [ -z "$user" ]; then
   adduser "$username"
   addgroup "$username" wheel
fi

if [ ! -f "$home/.profile" ]; then
tee $home/.profile << EOF >/dev/null
export KISS_DEBUG="0"
export KISS_SU="ssu"
export KISS_COMPRESS="zst"
export KISS_GET="curl"
export CFLAGS="-O2 -pipe -march=x86-64 -mtune=generic"
#export CFLAGS="-O3 -pipe -march=native"
export CXXFLAGS="\$CFLAGS"
export MAKEFLAGS="-j\$(nproc)"
export KISSREPO="$kissrepo"
export KISS_PATH="\$KISSREPO/repo/core:\$KISSREPO/repo/extra:\$KISSREPO/community/community"
alias ls="ls --color=auto"
EOF
chown 1000:1000 "$home/.profile"
fi

break;;

[Nn][Oo] )

   printf '\033[92;1m[ INFO: No user added, continuing... ]\033[m\n'
   sleep 1
break;;

*) echo retry;;

esac
done

source /root/.profile

###############################################
#           Github & SSH Key Setup            #
###############################################
### Create ssh key and add to github.com account
# ssh-keygen -t ed25519 -C 'comment'
#
### Test ssh key works
# ssh -T git@github.com
#
### Clone repo using ssh key
# git clone git@github.com:leafhy/repo.git
#
### Create ~/.ssh/config
# ------ BEGIN ------ #
# host github
# hostname github.com
# user git
# identityfile ~/.ssh/github-id_ed25519
# ------- END ------- #
### Test ssh config works
# ssh -T github
#
### Clone repo using ssh config
# git clone github:leafhy/repo.git
#
# NOTE: Re-clone repo if permission denied occurs
#       i.e. repo out of sync
###############################################

[ ! -d "$kissrepo/repo" ] && git clone https://github.com/leafhy/repo.git $kissrepo/repo
                           # git clone https://github.com/kisslinux/repo.git $kissrepo/repo

[ ! -d "$kissrepo/community" ] && git clone https://github.com/dylanaraps/community.git $kissrepo/community

# Fix git dubious permissions.
if [ ! -f /root/.gitconfig ]; then
   git config --global --add safe.directory "$kissrepo/repo"

for pkg in "$kissrepo/repo/extra/"*; do
   url="$(grep git+ $pkg/sources | grep -v '#')" && url="$url"
   [ "$url" ] && git config --global --add safe.directory $(echo $kiss_cache/sources/$(basename $pkg)/$(basename $url))
done

fi

if [ -d "$home" ] && [ ! -f "$home/.gitconfig" ]; then
   cp /root/.gitconfig "$home"
   chown 1000:1000 "$home/.gitconfig"
fi

kiss search \*

# ----------------- #
# Trusted Key Setup #
# ----------------- #
# kiss build gnupg1
#
# gpg --keyserver keyserver.ubuntu.com --recv-key 13295DAC2CF13B5C
# echo trusted-key 0x13295DAC2CF13B5C >> /root/.gnupg/gpg.conf
#
# cd $kissrepo/repo
# git config merge.verifySignatures true
# ----------------- #

# Update package manager.
kiss update

# Change cache location to one more apt for Single User
# and fix log permissions so builds don't fail.
if [ "$kiss_cache" ] && [ ! -f "/usr/bin/kiss.orig" ]; then
   cp /usr/bin/kiss /usr/bin/kiss.orig

sed '/# SOFTWARE./a\
\
kiss_cache="/var/db/kiss/cache"\
\
if [ "$(id -u)" != 0 ]; then\
   ssu chown -R 1000:1000 "$kiss_cache/logs"\
fi' /usr/bin/kiss > _
mv -f _ /usr/bin/kiss

sed 's/cac_dir=/#cac_dir=/g' /usr/bin/kiss > _
mv -f _ /usr/bin/kiss

sed '/Top-level cache/a\
\ \ \ \ cac_dir=\$kiss_cache' /usr/bin/kiss > _
mv -f _ /usr/bin/kiss

chmod +x /usr/bin/kiss
fi

# Make sure all 'repo' pkgs are downloaded.
kiss download $(ls "$kissrepo/repo/core" ; ls "$kissrepo/repo/extra")

if [ -z "$kiss_cache" ]; then
   cd "$kissrepo/installed" && kiss build *
fi

# Update other pkgs.
kiss update

# Install requisite packages.
tmpfile="$(printf 'mkstemp(/tmp/tmp.XXXXXX)' | m4)"

# https://unix.stackexchange.com/questions/520035/exit-trap-with-posix
trap 'rm "$tmpfile"; trap - EXIT; exit' EXIT INT

for pkg in baseinit baselayout ssu efibootmgr intel-ucode tamsyn-font runit iproute2 zstd lzip util-linux nasm popt f2fs-tools e2fsprogs xfsprogs dosfstools; do
   [ -d "$kissrepo/installed/$pkg" ] && installed="$(cat $kissrepo/installed/$pkg/version)"
   [ -d "$kissrepo/repo/core/$pkg" ] && repo="$(cat $kissrepo/repo/core/$pkg/version)"
   [ -d "$kissrepo/repo/extra/$pkg" ] && repo="$(cat $kissrepo/repo/extra/$pkg/version)"

if [ "$installed" != "$repo" ]; then
   printf '%s\n' "$pkg" >> $tmpfile
fi

done

[ -s "$tmpfile" ] && kiss build $(cat $tmpfile)

[ -d "$kiss_cache" ] && chown -R 1000:1000 "$kiss_cache"

if [ "$kver" ] && [ ! -f "$kissrepo/src/linux-$kver.tar.xz" ]; then
   printf "\033[92;1m[ INFO: Downloading -> $kernel... ]\033[m\n"
   curl -fL $kernel -o "$kissrepo/src/linux-$kver.tar.xz"
fi

if [ ! -f "/boot/vmlinuz-$kver" ] && [ -f "$kissrepo/src/linux-$kver.tar.xz" ] && [ ! -d "$kissrepo/src/linux-$kver" ]; then
   printf "\033[92;1m[ INFO: Extracting -> linux-$kver... ]\033[m\n"
   tar xf "$kissrepo/src/linux-$kver.tar.xz" -C "$kissrepo/src/"
   cp "$kissrepo/repo/linux-kernel-$kver.config" "$kissrepo/src/linux-$kver/.config"
   cd "$kissrepo/src/linux-$kver"

   sed '/<stdlib.h>/a #include <linux/stddef.h>' tools/objtool/arch/x86/decode.c > _
   mv -f _ tools/objtool/arch/x86/decode.c

   [ -f /usr/share/doc/kiss/wiki/kernel/patches/kernel-no-perl.patch ] && \
   patch -p1 < /usr/share/doc/kiss/wiki/kernel/patches/kernel-no-perl.patch

   [ -f /usr/share/doc/kiss/wiki/kernel/no-perl.patch ] && \
   patch -p1 < /usr/share/doc/kiss/wiki/kernel/no-perl.patch
fi

if [ "$lver" ] && [ ! -f "$kissrepo/src/$lver.tar.xz" ]; then
   printf "\033[92;1m[ INFO: Downloading -> $linuxfirmware... ]\033[m\n"
   curl -fL $linuxfirmware -o "$kissrepo/src/$lver.tar.xz"
   tar xf "$kissrepo/src/$lver.tar.xz"
   mkdir -p /usr/lib/firmware
   cp -R linux-firmware/intel /usr/lib/firmware
   # git clone https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git
   # cp -R linux-firmware.git/intel /usr/lib/firmware
fi

echo "#####################"
echo "#### FINAL STEPS ####"
echo "#####################"
echo "### Build & install kernel"
echo "cd linux-$kver"
echo "make && make install"
echo "mv linux-$kver $kissrepo/src"
echo ''
echo "### Create boot entry for UEFI"
echo "mv /boot/vmlinuz /boot/vmlinuz-$kver"
echo "cp /boot/vmlinuz-$kver /boot/efi"
echo "mv /boot/System.map /boot/System.map-$kver"
echo "./efiboot.sh"
echo ''
echo "### Create boot entry for NON-UEFI"
echo "mv /boot/vmlinuz /boot/vmlinuz-$kver"
echo "mv /boot/System.map /boot/System.map-$kver"
echo "./syslinux-extlinux-installer.sh"
echo "mv syslinux-6.04-pre1.tar.xz $kissrepo/src"
echo ''
echo "### Rename resolv.conf.orig"
echo "mv /etc/resolv.conf.orig /etc/resolv.conf"
echo "Note: Exit chroot before renaming 'resolv.conf.orig', else it will be 'rm'."
echo "#####################"
echo '++ EOF ++'

