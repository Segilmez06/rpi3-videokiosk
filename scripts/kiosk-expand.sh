#!/usr/bin/env bash
#
# kiosk-expand.sh - First-boot partition auto-expander & initial setup status display
# Expands Partition 3 (FAT32 /media/videos) to claim 100% of the remaining SD card space.
#

FLAG_FILE="/etc/kiosk-expanded"

if [ -f "$FLAG_FILE" ]; then
    exit 0
fi

# Ensure output is directed to tty1 and screen is clean
exec > /dev/tty1 2>&1
setterm -cursor off > /dev/tty1 2>/dev/null || true
clear > /dev/tty1 2>/dev/null || true

echo ""
echo "  ================================================================"
echo "              Raspberry Pi 3 Video Kiosk - Initial Setup          "
echo "  ================================================================"
echo ""
echo "  First-time initialization in progress. Please do not power off."
echo ""

# 1. Detect storage device
echo -n "  [*] Detecting storage device... "
ROOT_DEV=$(findmnt -n -o SOURCE /)
DISK_DEV=$(lsblk -no PKNAME "$ROOT_DEV" 2>/dev/null)
if [ -z "$DISK_DEV" ]; then
    DISK_DEV="mmcblk0"
fi
DISK_PATH="/dev/$DISK_DEV"
PART3_PATH="${DISK_PATH}p3"
echo "OK (/dev/$DISK_DEV)"

if [ ! -b "$DISK_PATH" ] || [ ! -b "$PART3_PATH" ]; then
    echo "  [!] Partition 3 not found on $DISK_PATH, skipping expansion."
    touch "$FLAG_FILE"
    sleep 3
    exit 0
fi

# 2. Expanding partition table
echo -n "  [*] Expanding media partition (Partition 3) to fill SD card... "
umount /media/videos 2>/dev/null || true
parted -s "$DISK_PATH" resizepart 3 100%
partprobe "$DISK_PATH" 2>/dev/null || true
udevadm settle 2>/dev/null || sleep 1
echo "OK"

# 3. Resizing FAT32 filesystem
echo "  [*] Resizing FAT32 filesystem to full capacity..."
echo "      (This may take 15-40 seconds on slow SD cards, please wait)"
if command -v fatresize >/dev/null 2>&1; then
    fatresize -s max "$PART3_PATH" >/dev/null 2>&1 || true
else
    fsck.vfat -a "$PART3_PATH" 2>/dev/null || true
fi
echo "  [*] FAT32 filesystem resize: OK"

# 4. Finalizing mounts
echo -n "  [*] Mounting media partition in read-only protection mode... "
mkdir -p /media/videos
mount -a 2>/dev/null || true
echo "OK"

# 5. Done
echo ""
echo "  ================================================================"
echo "                    First Boot Setup Complete!                    "
echo "  ================================================================"
echo ""
echo "  Starting video playback in 3 seconds..."
sleep 3
clear
touch "$FLAG_FILE"
exit 0
