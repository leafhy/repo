#!/bin/sh -e

username="$1"
home="/home/${username:-empty}"
kver="5.15.6"
kernel="https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-$kver.tar.xz"
#lver="linux-firmware-20211027"
linuxfirmware="https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/snapshot/$lver.tar.gz"
kissrepo="/var/db/kiss"
kiss_cache="$kissrepo/cache"

line () { printf '%s\n' "-----------------------------------"; }

tmpfileA="$(printf 'mkstemp(/tmp/tmp.XXXXXX)' | m4)"
tmpfileB="$(printf 'mkstemp(/tmp/tmp.XXXXXX)' | m4)"
tmpfileC="$(printf 'mkstemp(/tmp/tmp.XXXXXX)' | m4)"
# https://unix.stackexchange.com/questions/520035/exit-trap-with-posix
trap 'rm "$tmpfileA" "$tmpfileB" "$tmpfileC"; printf "\n"; trap - EXIT; exit' EXIT INT

while true; do
read -p "Create user now? [yes/no]: "  ans
case "$ans" in

[Yy][Ee][Ss] )

if [ -z "$username" ]; then
   printf '\033[31;1m[  ERROR: Missing username.  ]\033[m'
   exit 1
fi

user="$(getent passwd | cut -d: -f1 | grep $username || :)"
#user="$(getent passwd 1000 | cut -d: -f1)"

if [ -z "$user" ]; then
   adduser "$username"

   for g in wheel audio; do
      addgroup "$username" "$g"
   done

   # Create needed directories.
   # Note: 'siren' does not create '.config'.
   mkdir \
       "$home/.config" \
       "$home/src"

   chown -R 1000:1000 "$home"
fi

if [ -d "$home" ] && [ ! -f "$home/.profile" ]; then
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

   printf '\033[92;1m[  INFO: No user added, continuing...  ]\033[m\n'
   sleep 1

break;;

*) echo retry;;

esac
done

source /root/.profile

###############################################
#           Github & SSH Key Setup            #
###############################################
### Create ssh key and add to github.com account.
# ssh-keygen -t ed25519 -C 'comment'
#
### Test ssh key works.
# ssh -T git@github.com
#
### Clone repo using ssh key.
# git clone git@github.com:leafhy/repo.git
#
### Create ~/.ssh/config.
# ------ BEGIN ------ #
# host github
# hostname github.com
# user git
# identityfile ~/.ssh/github-id_ed25519
# ------- END ------- #
### Test ssh config works.
# ssh -T github
#
### Clone repo using ssh config.
# git clone github:leafhy/repo.git
#
# NOTE: Re-clone repo if permission denied occurs.
#       i.e. repo out of sync.
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

# Note: There are (2) checksums for kiss docs -> 'f0525d4e00c5e07138ac2ceb53936d0b221608e7.tar.gz'.
#       kiss-5.5.14 -> old checksum 'efca06d0a52037c732007f33f99cd368a836b5f9fec3ae314cfd73182f337c01'
#       kiss-5.5.28 -> new checksum 'e8549203a55bef2cf7c900814e7c9c694beebe0178e42d82a0a873bf8baea522'

if [ "$kiss_cache" ] && [ ! -f "/usr/bin/kiss.orig" ]; then
   # Update package manager.
   kiss download kiss
   docschksum="$(sha256sum $kiss_cache/sources/kiss/docs/f0525d4e00c5e07138ac2ceb53936d0b221608e7.tar.gz | cut -d' ' -f1)"

   if [ "$docschksum" != "e8549203a55bef2cf7c900814e7c9c694beebe0178e42d82a0a873bf8baea522" ] && [ "$docschksum" != "efca06d0a52037c732007f33f99cd368a836b5f9fec3ae314cfd73182f337c01" ]; then
      printf '\033[31;1m[  FATAL: Aborting...kiss docs checksum mismatch.  ]\033[m\n'
      exit 1
   fi

   kiss update
   cp /usr/bin/kiss /usr/bin/kiss.orig
fi

if [ ! -f "/usr/bin/kiss" ] && [ -f "/usr/bin/kiss.orig" ]; then
   cp /usr/bin/kiss.orig /usr/bin/kiss
fi

kisssumA=$(sha256sum /usr/bin/kiss)
kisssumB=$(sha256sum /usr/bin/kiss.orig)

if [ "${kisssumA% *}" = "${kisssumB% *}" ] && [ "$kiss_cache" ]; then
# Change cache location to one more apt for Single User
# and fix log permissions so builds don't fail.
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

# Add extra tar command for when busybox tar
# is inadequate.
sed 's/tar cf/\$tar cf/' /usr/bin/kiss > _
mv -f _ /usr/bin/kiss

sed '/: "${LOGNAME:?POSIX requires LOGNAME be set}"/a\
\
    # Set the prefered tar command to use for creating lz, zst tarballs.\
    # NOTE: busybox tar can create broken lz, zst tarballs.\
    #     : schilytools & GNU tar created lz, zst tarballs\
    #       are compatible with busybox tar.\
    #     : schilytools tar created lz tarball is compatible with tarlz.\
    if [ "$KISS_COMPRESS" = "lz" ] || [ "$KISS_COMPRESS" = "zst" ]; then\
       msg() {\
          c1='\033[1;33m'\
          c2='\033[1;31'\
          c3='\033[m'\
          c4='\033[1;36m'\
\
          printf '%b%s%b %s %b%s %b%s%b %s\n' \
              "$c1" "$1" "$c2" "$2" "$c3" "$3" "$c4" "$4" "$c3" "$2"\
       }\
\
       end() {\
          msg "$1" "$2" "$3" "$4" "$5"\
          exit 1\
       }\
\
       ! [ -x "/opt/schily/bin/tar" ] && end "->" "ERROR" "Install" "schilytools" "to use (lz, zst) compression."\
       tar=/opt/schily/bin/tar\
    fi\
\
    tar="${tar:-tar}"' /usr/bin/kiss > _
mv -f _ /usr/bin/kiss

chmod +x /usr/bin/kiss
fi

# Make sure all 'repo' pkgs + dependencies are downloaded.
for d in core extra; do
   find "$kissrepo/repo/$d" -maxdepth 1 -type d -print0 | xargs -0 -n1 basename | sed "s/^$d$//" >> $tmpfileA
done

find "$kissrepo/repo/extra" -name depends -print0 | xargs -0 sed 's/[[:space:]]\{1,\}/\n/' | sed 's/ //g' >> $tmpfileA

for pkg in $(sort $tmpfileA | uniq); do
   kiss download "$pkg" || printf '%s\n' "$pkg" >> _PKG-DOWNLOAD-FAILURE.log
done

#kiss download $(ls "$kissrepo/repo/core" ; ls "$kissrepo/repo/extra")

if [ -z "$kiss_cache" ]; then
   cd "$kissrepo/installed" && kiss build *
fi

line

# Install requisite packages.
for pkg in baseinit baselayout ssu efibootmgr intel-ucode tamsyn-font runit iproute2 zstd lzip util-linux nasm popt f2fs-tools e2fsprogs xfsprogs dosfstools; do
   [ -d "$kissrepo/installed/$pkg" ] && installed="$(cat $kissrepo/installed/$pkg/version)"
   [ -d "$kissrepo/repo/core/$pkg" ] && repo="$(cat $kissrepo/repo/core/$pkg/version)"
   [ -d "$kissrepo/repo/extra/$pkg" ] && repo="$(cat $kissrepo/repo/extra/$pkg/version)"

if [ "$installed" != "$repo" ]; then
   printf '%s\n' "$pkg" >> $tmpfileB
   # Get list of required deps.
   for d in core extra; do
      [ -f "$kissrepo/repo/$d/$pkg/depends" ] && cat "$kissrepo/repo/$d/$pkg/depends" | sed 's/[[:space:]]\{1,\}/\n/' | sed 's/ //g' >> $tmpfileC
   done
fi

done

if [ -f _PKG-DOWNLOAD-FAILURE.log ]; then
   printf '\033[31;1m[  ERROR: Failed to download package.  ]\033[m\n'
   for f in $(cat _PKG-DOWNLOAD-FAILURE.log); do
      printf '%s\n' "=> $f"
   done

      line

   if [ -s "$tmpfileB" ]; then
      for p in $(sort $tmpfileB $tmpfileC | uniq); do
         grep -qw "$p" _PKG-DOWNLOAD-FAILURE.log &&
         [ ! -d "$kissrepo/installed/$p" ] && printf '%s\n' "$p" >> _REQ-PKG-NOT-FOUND.log
      done
   fi

else
   # Update other pkgs.
   kiss update
fi

if [ -f _REQ-PKG-NOT-FOUND.log ]; then
   printf '\033[31;1m[  FATAL: Aborting...Required package not found.  ]\033[m\n'
      for pk in $(cat _REQ-PKG-NOT-FOUND.log); do
         printf '%s\n' "=> $pk"
      done
   line
   exit 1
fi

# NOTE: 'util-linux' -> 'blkid' supports PARTUUID which is required to use 'efiboot.sh'.
#       'busybox' -> 'blkid' does not support PARTUUID.
bbver="$(cat $kissrepo/repo/core/busybox/version)"
bbfix="$(printf '%s' "$bbver" | cut -d' ' -f1 | sed 's/\./_/g')"
bbbin="$(printf '%s' "$bbver" | sed 's/\ /-/')"
bbsrc="$(basename $(head -n1 $kissrepo/repo/core/busybox/sources) | sed "s/MAJOR_MINOR_PATCH/$bbfix/")"

if [ -f "$kiss_cache/sources/busybox/$bbsrc" ] && [ ! -f "$kiss_cache/bin/busybox@$bbbin.tar.gz" ]; then
   # Re-build 'busybox' without 'blkid' so as to avoid swapping to 'util-linux'.
   kiss build busybox
fi

[ -s "$tmpfileB" ] && kiss build $(cat $tmpfileB)

[ -d "$kiss_cache" ] && chown -R 1000:1000 "$kiss_cache"

if [ "$kver" ] && [ ! -f "$kissrepo/src/linux-$kver.tar.xz" ]; then
   printf "\033[92;1m[  INFO: Downloading -> $kernel...  ]\033[m\n"
   curl -fL $kernel -o "$kissrepo/src/linux-$kver.tar.xz"
fi

if [ -f "$kissrepo/src/linux-$kver.tar.xz" ] && [ ! -d "$kissrepo/src/linux-$kver" ]; then
   printf "\033[92;1m[  INFO: Extracting -> linux-$kver...  ]\033[m\n"
   tar xf "$kissrepo/src/linux-$kver.tar.xz" -C "$kissrepo/src"
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
   printf "\033[92;1m[  INFO: Downloading -> $linuxfirmware...  ]\033[m\n"
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
echo "cd $kissrepo/src/linux-$kver"
echo "make && make install"
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

