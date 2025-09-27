#!/bin/sh
#
# The basis for this script is available here -> https://armadeus.org/wiki/index.php?title=Automatically_mount_removable_media

# NOTE: This script is included with the 'mdevd' package as it's preferred over 'mdev'.

# To enable automounting add the following rules to '/etc/mdev.conf' or '/etc/mdevd.conf' & enable the corresponding service.
# =>  sr[0-9]*    root:cdrom    660    */usr/lib/mdev/automounter.sh
# =>  sd[a-z].*   root:disk     660    */usr/lib/mdev/automounter.sh

# NOTE: This *NOTE* may not be indicative of other devices but a quirk/fault of the tested device.
#     : Mounting of a block device ( i.e. /dev/sdb ) which has no partition table will initially fail to mount.
#     : Mounting can be achieved by restarting the 'mdev' service or by running 'mdevd-coldplug'.
#     : Alternativly access can be acquired by the utilization of 'autofs'.

destdir=/run/media

cleanup() {

       # The removal of drives that have been accessed via 'autofs' can cause the non-removal of mountpoints due to I/O errors.
       # This 'cleanup' function purges the empty mountpoints of devices that are no longer attached.
       [ -x /usr/bin/automount ] && blkid > "$destdir/.blkid_chk"

       if [ -f "$destdir/.blkid_chk" ]; then
          for dev in "$destdir"/*; do
             if [ -d "$dev" ]; then
             dev="${dev##/*/}"
                if ! grep "$dev" "$destdir/.blkid_chk"; then
                   umount "/dev/$dev" "$destdir/$dev"
                   rmdir "$destdir/$dev"
                fi
             fi
          done
       fi

}

my_umount() {

         # NOTE: 'util-linux umount' supports (-q)uiet.
         #       'busybox umount' does not support (-q)uiet.
         #       'gnu grep' & 'busybox grep' support (-q)uiet.
         if grep -q "/dev/$1" /proc/mounts; then
            umount  "/dev/$1"
         fi

         [ -d "$destdir/$1" ] && rmdir "$destdir/$1"

}

my_mount() {
        mkdir -p "$destdir/$1" || exit 1

        if [ ! -L "$(command -v blkid >/dev/null)" ]; then
           fstype=$(blkid --match-tag TYPE "/dev/$1" \
           | cut -d' ' -f2 \
           | sed -e 's/TYPE=//' -e 's/\"//g' \
           || :)
        fi

        case "${fstype:-auto}" in
           ntfs           )
                         mount -t ntfs    -o ro,async             "/dev/$1" "$destdir/$1" || rmdir "$destdir/$1" ;;
                       # ntfs-3g          -o rw,uid=1000,gid=1000 "/dev/$1" "$destdir/$1" || rmdir "$destdir/$1" ;;
           xfs            )
                         mount -t xfs     -o async                "/dev/$1" "$destdir/$1" || rmdir "$destdir/$1" ;;
           vfat           )
                         mount -t vfat    -o async                "/dev/$1" "$destdir/$1" || rmdir "$destdir/$1" ;;
           f2fs           )
                         mount -t f2fs    -o async                "/dev/$1" "$destdir/$1" || rmdir "$destdir/$1" ;;
           exfat          )
                         mount -t exfat   -o async                "/dev/$1" "$destdir/$1" || rmdir "$destdir/$1" ;;
           ext2|ext3|ext4 )
                         mount -t $fstype -o async                "/dev/$1" "$destdir/$1" || rmdir "$destdir/$1" ;;
           hfsplus        )
                         mount -t hfsplus -o async                "/dev/$1" "$destdir/$1" || rmdir "$destdir/$1" ;;
           auto           )
                         mount -t auto    -o async                "/dev/$1" "$destdir/$1" || rmdir "$destdir/$1" ;;
        esac

}

case $ACTION in
   add    )
         my_umount $MDEV
         my_mount  $MDEV ;;

   remove )
         my_umount $MDEV
         cleanup         ;;
esac
