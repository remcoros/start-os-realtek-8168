#!/bin/bash

set -e

# the current and new name of the .iso file
isofile=startos-0.3.5.1-39de098_x86_64-nonfree.iso
newisofile=startos-0.3.5.1-39de098_x86_64-nonfree-r8168.iso

# install required dependencies for building an iso
echo "Installing dependencies..."
apt install xorriso squashfs-tools rsync

# download iso file if it doesn't exist yet
echo "Downloading start-os iso..."
test -e $isofile || \
    wget https://github.com/Start9Labs/start-os/releases/download/v0.3.5.1/$isofile

# verify checksum of start-os iso file
echo "29b0f1e0211568ea66d6b729536ff84aed3b6cbc1c38540a7c80a391fd01616e $isofile" | sha256sum --check --status || (echo "invalid checksum" && exit 1)

# mount the iso and containing filesystem squashfs 
echo "Preparing..."
umount squashfs || true
umount iso || true

rm -f $newisofile
rm -f filesystem-mod.squashfs
rm -rf iso && mkdir iso
rm -rf squashfs && mkdir squashfs
rm -rf squashfs-mod && mkdir squashfs-mod

mount -o loop $isofile iso
mount -o loop iso/live/filesystem.squashfs squashfs

# mounting an iso/squashfs file is read-only, copy 'squashfs' dir so we can modify it
echo "Copy squashs into squashfs-mod..."
rsync -a squashfs/ squashfs-mod/

# now chroot into filesystem and install driver from debian snapshot repository
# the snapshot date matches the date around when start-os 0.3.5.1 was build
# we do this to prevent updating the kernel version due to the dkms tools
echo "Installing driver..."
chroot squashfs-mod /bin/bash -x <<'EOT'
mount -t proc none /proc/
mount -t sysfs none /sys/

echo "deb [check-valid-until=no] https://snapshot.debian.org/archive/debian/20231121T031647Z stable main contrib non-free non-free-firmware" > /etc/apt/sources.list
apt update && apt install -y linux-headers-6.1.0-13-amd64 r8168-dkms

apt clean
rm -rf /tmp/*
umount /proc/
umount /sys/
EOT

# make a new squashfs filesystem
echo "Creating new squashfs filesystem..."

mksquashfs squashfs-mod filesystem-mod.squashfs

# create a new iso based on existing with updated filesystem and kernel files
echo "Creating iso..."

xorriso \
   -indev $isofile \
   -overwrite "on" \
   -compliance no_emul_toc \
   -update filesystem-mod.squashfs live/filesystem.squashfs \
   -update squashfs-mod/boot/initrd.img-6.1.0-13-amd64 live/initrd.img \
   -update squashfs-mod/boot/vmlinuz-6.1.0-13-amd64 live/vmlinuz \
   -map squashfs-mod/boot/initrd.img-6.1.0-13-amd64 live/initrd.img-6.1.0-13-amd64 \
   -map squashfs-mod/boot/vmlinuz-6.1.0-13-amd64 live/vmlinuz-6.1.0-13-amd64 \
   -map squashfs-mod/boot/System.map-6.1.0-13-amd64 live/System.map-6.1.0-13-amd64 \
   -outdev $newisofile \
   -boot_image any replay \
   -padding included

# some cleanup
echo "Cleaning up..."

umount squashfs || true
umount iso || true
rm -rf squashfs-mod
rm -rf squashfs
rm -rf iso
rm -f filesystem-mod.squashfs

echo "Done"
