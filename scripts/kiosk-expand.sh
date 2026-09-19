#!/usr/bin/env bash
#
# kiosk-expand.sh - First-boot partition auto-expander for Raspberry Pi 3 Video Kiosk
# Expands Partition 3 (FAT32 /media/videos) to claim 100% of the remaining SD card space.
#

FLAG_FILE="/etc/kiosk-expanded"

if [ -f "$FLAG_FILE" ]; then
    exit 0
fi

# Detect root block device (typically /dev/mmcblk0)
ROOT_DEV=$(findmnt -n -o SOURCE /)
DISK_DEV=$(lsblk -no PKNAME "$ROOT_DEV" 2>/dev/null)

if [ -z "$DISK_DEV" ]; then
    DISK_DEV="mmcblk0"
fi
DISK_PATH="/dev/$DISK_DEV"
PART3_PATH="${DISK_PATH}p3"

# Check if target disk and partition 3 exist
if [ ! -b "$DISK_PATH" ] || [ ! -b "$PART3_PATH" ]; then
    echo "Disk or partition 3 not found, skipping expansion."
    touch "$FLAG_FILE"
    exit 0
fi

echo "Expanding $PART3_PATH to fill available space on $DISK_PATH..."

# Unmount /media/videos if mounted
umount /media/videos 2>/dev/null || true

# Resize partition 3 table entry to 100% using parted
parted -s "$DISK_PATH" resizepart 3 100%
partprobe "$DISK_PATH" 2>/dev/null || true
sleep 1
udevadm settle 2>/dev/null || true

# Non-destructively resize FAT32 filesystem
if command -v fatresize >/dev/null 2>&1; then
    echo "Running fatresize on $PART3_PATH..."
    fatresize -s max "$PART3_PATH" || true
else
    echo "fatresize not found, checking filesystem..."
    fsck.vfat -a "$PART3_PATH" 2>/dev/null || true
fi

# Remount /media/videos
mkdir -p /media/videos
mount -a 2>/dev/null || true

touch "$FLAG_FILE"
echo "Partition expansion completed."
exit 0
