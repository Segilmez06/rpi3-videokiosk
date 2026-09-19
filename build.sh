#!/usr/bin/env bash
#
# build.sh - Automated Image Builder for Raspberry Pi 3 Video Kiosk
# Produces a zero-UI, 3-partition, DRM/KMS headless mpv kiosk image based on DietPi.
#

set -euo pipefail

# Ensure graphical privilege escalation if not running as root
if [ "$EUID" -ne 0 ]; then
    echo "Root privileges required. Requesting authentication via askpass..."
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    export SUDO_ASKPASS="$SCRIPT_DIR/scripts/askpass.sh"
    exec sudo -A "$0" "$@"
fi

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="$BASE_DIR/cache"
BUILD_DIR="$BASE_DIR/build"
OUTPUT_DIR="$BASE_DIR/output"

DIETPI_IMG_URL="https://dietpi.com/downloads/images/DietPi_RPi234-ARMv8-Bookworm.img.xz"
DIETPI_IMG_XZ="$CACHE_DIR/DietPi_RPi234-ARMv8-Bookworm.img.xz"
TARGET_RAW="$BUILD_DIR/rpi3-videokiosk.raw"
TARGET_IMG="$BUILD_DIR/rpi3-videokiosk.img"
TARGET_XZ="$OUTPUT_DIR/rpi3-videokiosk.img.xz"
MNT_DIR="$BUILD_DIR/mnt"
LOOP_DEV=""

mkdir -p "$CACHE_DIR" "$BUILD_DIR" "$OUTPUT_DIR"

cleanup() {
    echo "--> Running cleanup..."
    set +e
    if [ -d "$MNT_DIR" ]; then
        umount -l "$MNT_DIR/dev/pts" 2>/dev/null || true
        umount -l "$MNT_DIR/dev" 2>/dev/null || true
        umount -l "$MNT_DIR/proc" 2>/dev/null || true
        umount -l "$MNT_DIR/sys" 2>/dev/null || true
        umount -l "$MNT_DIR/boot" 2>/dev/null || true
        umount -l "$MNT_DIR" 2>/dev/null || true
        rm -rf "$MNT_DIR" 2>/dev/null || true
    fi
    if [ -n "$LOOP_DEV" ] && [ -b "$LOOP_DEV" ]; then
        losetup -d "$LOOP_DEV" 2>/dev/null || true
    fi
}
trap cleanup EXIT

echo "========================================================"
echo " Starting Raspberry Pi 3 Video Kiosk Build Pipeline"
echo "========================================================"

# 1. Check prerequisites
echo "--> Checking host tools..."
for tool in parted losetup mkfs.vfat xz curl qemu-aarch64-static resize2fs e2fsck; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Error: Required tool '$tool' is not installed."
        exit 1
    fi
done

# 2. Download base DietPi image if not in cache
if [ ! -f "$DIETPI_IMG_XZ" ]; then
    echo "--> Downloading DietPi ARMv8 Bookworm base image..."
    curl -fL -C - -o "$DIETPI_IMG_XZ" "$DIETPI_IMG_URL"
else
    echo "--> Using cached DietPi image: $DIETPI_IMG_XZ"
fi

# 3. Extract raw image
echo "--> Extracting base image to $TARGET_RAW..."
xz -dc "$DIETPI_IMG_XZ" > "$TARGET_RAW"

# 4. Resize virtual disk image to 1800MB (ensures fit on 2GB cards)
echo "--> Resizing image file to 1800MB (2GB SD card compatibility)..."
truncate -s 1800M "$TARGET_RAW"

# 5. Setup loopback device
echo "--> Attaching loopback device..."
LOOP_DEV=$(losetup -Pf --show "$TARGET_RAW")
sleep 1

# 6. Adjust Partition Table:
# - Partition 1: Boot (FAT32, ~134MB)
# - Partition 2: RootFS (ext4, ~1316MB, ends at 1450MB)
# - Partition 3: Media (FAT32, ~350MB, fills remaining space)
echo "--> Partitioning: Expanding RootFS (Part 2) to 1450MB..."
parted -s "$LOOP_DEV" resizepart 2 1450MiB
e2fsck -f -y "${LOOP_DEV}p2" || true
resize2fs "${LOOP_DEV}p2"

echo "--> Partitioning: Creating Partition 3 (FAT32 Media, 'VIDEOS')..."
parted -s "$LOOP_DEV" mkpart primary fat32 1450MiB 100%
parted -s "$LOOP_DEV" set 3 lba on
partprobe "$LOOP_DEV" 2>/dev/null || true
sleep 1
udevadm settle 2>/dev/null || true

echo "--> Formatting Partition 3 as FAT32 labeled 'VIDEOS'..."
mkfs.vfat -F 32 -n "VIDEOS" "${LOOP_DEV}p3"

# 7. Mount partitions
echo "--> Mounting partitions..."
mkdir -p "$MNT_DIR"
mount "${LOOP_DEV}p2" "$MNT_DIR"
mkdir -p "$MNT_DIR/boot" "$MNT_DIR/media/videos"
mount "${LOOP_DEV}p1" "$MNT_DIR/boot"

# Bind mounts for QEMU chroot
mount --bind /dev "$MNT_DIR/dev"
mount --bind /dev/pts "$MNT_DIR/dev/pts"
mount --bind /proc "$MNT_DIR/proc"
mount --bind /sys "$MNT_DIR/sys"
cp /etc/resolv.conf "$MNT_DIR/etc/resolv.conf"

# 8. Prevent service auto-start during apt installation
cat << 'EOF' > "$MNT_DIR/usr/sbin/policy-rc.d"
#!/bin/sh
exit 101
EOF
chmod +x "$MNT_DIR/usr/sbin/policy-rc.d"

# 9. Provision RootFS via QEMU AArch64
echo "--> Installing packages inside chroot (mpv, fatresize, openssh, zram, DRM)..."
chroot "$MNT_DIR" /bin/bash -c "
    export DEBIAN_FRONTEND=noninteractive
    export LC_ALL=C
    apt-get update
    apt-get install -y --no-install-recommends \
        mpv \
        fatresize \
        openssh-server \
        zram-tools \
        parted \
        dosfstools \
        mesa-va-drivers \
        libdrm2 \
        libgbm1

    apt-get clean
    rm -rf /var/lib/apt/lists/*
"
rm -f "$MNT_DIR/usr/sbin/policy-rc.d"

# 10. Install Kiosk Scripts and Services
echo "--> Installing kiosk scripts and systemd services..."
mkdir -p "$MNT_DIR/etc/mpv"
cp "$BASE_DIR/configs/mpv.conf" "$MNT_DIR/etc/mpv/mpv.conf"
cp "$BASE_DIR/scripts/kiosk-player.sh" "$MNT_DIR/usr/local/bin/kiosk-player.sh"
cp "$BASE_DIR/scripts/kiosk-expand.sh" "$MNT_DIR/usr/local/bin/kiosk-expand.sh"
chmod +x "$MNT_DIR/usr/local/bin/kiosk-player.sh" "$MNT_DIR/usr/local/bin/kiosk-expand.sh"

cp "$BASE_DIR/scripts/kiosk-player.service" "$MNT_DIR/etc/systemd/system/kiosk-player.service"
cp "$BASE_DIR/scripts/kiosk-expand.service" "$MNT_DIR/etc/systemd/system/kiosk-expand.service"

# 11. Configure SSH Public Keys
echo "--> Configuring authorized SSH keys..."
mkdir -p "$MNT_DIR/root/.ssh"
cp "$BASE_DIR/assets/authorized_keys" "$MNT_DIR/root/.ssh/authorized_keys"
chmod 700 "$MNT_DIR/root/.ssh"
chmod 600 "$MNT_DIR/root/.ssh/authorized_keys"

if [ -d "$MNT_DIR/home/dietpi" ]; then
    mkdir -p "$MNT_DIR/home/dietpi/.ssh"
    cp "$BASE_DIR/assets/authorized_keys" "$MNT_DIR/home/dietpi/.ssh/authorized_keys"
    chmod 700 "$MNT_DIR/home/dietpi/.ssh"
    chmod 600 "$MNT_DIR/home/dietpi/.ssh/authorized_keys"
    chroot "$MNT_DIR" chown -R dietpi:dietpi /home/dietpi/.ssh
fi

# 12. Configure ZRAM Swap (zstd, 50% RAM)
echo "--> Configuring ZRAM swap..."
cat << 'EOF' > "$MNT_DIR/etc/default/zramswap"
ALGO=zstd
PERCENT=50
PRIORITY=100
EOF

# 13. Enable Services and mask getty@tty1 (Zero UI)
echo "--> Enabling systemd services and silencing TTY1..."
chroot "$MNT_DIR" /bin/bash -c "
    systemctl enable kiosk-player.service
    systemctl enable kiosk-expand.service
    systemctl enable ssh.service
    systemctl enable zramswap.service || true
    systemctl mask getty@tty1.service
"

# 14. Configure /etc/fstab for SD Wear Reduction and Read-Only Media Mount
echo "--> Configuring /etc/fstab..."
if ! grep -q "/media/videos" "$MNT_DIR/etc/fstab"; then
    echo "/dev/mmcblk0p3  /media/videos  vfat  ro,defaults,noatime,umask=000,nofail  0  0" >> "$MNT_DIR/etc/fstab"
fi
sed -i 's/defaults/noatime,defaults/' "$MNT_DIR/etc/fstab" 2>/dev/null || true

# 15. Inject Boot and Firmware Configuration
echo "--> Injecting silent boot configuration to /boot..."
cp "$BASE_DIR/configs/dietpi.txt" "$MNT_DIR/boot/dietpi.txt"
cp "$BASE_DIR/configs/config.txt" "$MNT_DIR/boot/config.txt"
cp "$BASE_DIR/assets/cmdline.txt" "$MNT_DIR/boot/cmdline.txt"
cp "$BASE_DIR/assets/authorized_keys" "$MNT_DIR/boot/authorized_keys"

# Clean up chroot networking file
rm -f "$MNT_DIR/etc/resolv.conf"

# 16. Unmount cleanly
echo "--> Unmounting filesystems..."
umount -l "$MNT_DIR/dev/pts" 2>/dev/null || true
umount -l "$MNT_DIR/dev" 2>/dev/null || true
umount -l "$MNT_DIR/proc" 2>/dev/null || true
umount -l "$MNT_DIR/sys" 2>/dev/null || true
umount -l "$MNT_DIR/boot" 2>/dev/null || true
umount -l "$MNT_DIR" 2>/dev/null || true
rm -rf "$MNT_DIR"

losetup -d "$LOOP_DEV"
LOOP_DEV=""

mv "$TARGET_RAW" "$TARGET_IMG"

# 17. Compress output image
echo "--> Compressing image to $TARGET_XZ (this may take a few minutes)..."
xz -T0 -k -9 -f "$TARGET_IMG" -c > "$TARGET_XZ"

echo "--> Generating SHA256 checksum..."
(cd "$OUTPUT_DIR" && sha256sum "$(basename "$TARGET_XZ")" > "$(basename "$TARGET_XZ").sha256")

echo "========================================================"
echo " BUILD SUCCESSFUL!"
echo " Image created: $TARGET_XZ"
echo " SHA256: $(cat "$TARGET_XZ.sha256")"
echo "========================================================"
