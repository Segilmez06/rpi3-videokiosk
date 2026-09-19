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
APT_CACHE_DIR="$CACHE_DIR/apt-archives"
APT_LISTS_DIR="$CACHE_DIR/apt-lists"

DIETPI_IMG_URL="https://dietpi.com/downloads/images/DietPi_RPi234-ARMv8-Bookworm.img.xz"
DIETPI_IMG_XZ="$CACHE_DIR/DietPi_RPi234-ARMv8-Bookworm.img.xz"
TARGET_RAW="$BUILD_DIR/rpi3-videokiosk.raw"
TARGET_IMG="$BUILD_DIR/rpi3-videokiosk.img"
TARGET_XZ="$OUTPUT_DIR/rpi3-videokiosk.img.xz"
MNT_DIR="$BUILD_DIR/mnt"
LOOP_DEV=""

mkdir -p "$CACHE_DIR" "$BUILD_DIR" "$OUTPUT_DIR" "$APT_CACHE_DIR/partial" "$APT_LISTS_DIR/partial"

cleanup() {
    echo "--> Running cleanup..."
    set +e
    if [ -d "$MNT_DIR" ]; then
        umount -l "$MNT_DIR/var/cache/apt/archives" 2>/dev/null || true
        umount -l "$MNT_DIR/var/lib/apt/lists" 2>/dev/null || true
        umount -l "$MNT_DIR/dev/pts" 2>/dev/null || true
        umount -l "$MNT_DIR/dev" 2>/dev/null || true
        umount -l "$MNT_DIR/proc" 2>/dev/null || true
        umount -l "$MNT_DIR/sys" 2>/dev/null || true
        umount -l "$MNT_DIR/tmp" 2>/dev/null || true
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

# Pre-clean any stale mounts or loop devices from previously aborted runs
echo "--> Checking for and cleaning any stale mounts or loops..."
while findmnt -n -l -o TARGET | grep -q "$MNT_DIR"; do
    findmnt -n -l -o TARGET | grep "$MNT_DIR" | sort -r | while read -r m; do
        echo "Unmounting stale mount: $m"
        umount -l "$m" 2>/dev/null || true
    done
    sleep 1
done
if [ -f "$TARGET_RAW" ]; then
    losetup -j "$TARGET_RAW" -O NAME --noheadings 2>/dev/null | while read -r l; do
        echo "Detaching stale loop device: $l"
        losetup -d "$l" 2>/dev/null || true
    done
fi

# 3. Extract raw image
echo "--> Extracting base image to $TARGET_RAW..."
xz -dc "$DIETPI_IMG_XZ" > "$TARGET_RAW"

# 4. Resize virtual disk image to 1350MB (Safe compact layout for fast flashing)
echo "--> Resizing image file to 1350MB (Safe compact layout for fast flashing)..."
truncate -s 1350M "$TARGET_RAW"

# 5. Setup loopback device
echo "--> Attaching loopback device..."
LOOP_DEV=$(losetup -Pf --show "$TARGET_RAW")
sleep 1

# 6. Adjust Partition Table:
# - Partition 1: Boot (FAT32, ~134MB)
# - Partition 2: RootFS (ext4, ~1115MB, ends at 1250MB - ample room for dpkg unpack)
# - Partition 3: Media (FAT32, ~100MB, fills remaining space to 1350MB)
echo "--> Partitioning: Expanding RootFS (Part 2) to 1250MiB..."
parted -s "$LOOP_DEV" resizepart 2 1250MiB
e2fsck -f -y "${LOOP_DEV}p2" || true
resize2fs "${LOOP_DEV}p2"

echo "--> Partitioning: Creating Partition 3 (FAT32 Media, 'VIDEOS')..."
parted -s "$LOOP_DEV" mkpart primary fat32 1250MiB 100%
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
mkdir -p "$MNT_DIR/tmp"
mount -t tmpfs -o mode=1777 tmpfs "$MNT_DIR/tmp"
cp /etc/resolv.conf "$MNT_DIR/etc/resolv.conf"

# Persistent APT cache bind mounts (speeds up subsequent builds with zero network downloads)
mkdir -p "$MNT_DIR/var/cache/apt/archives/partial"
mkdir -p "$MNT_DIR/var/lib/apt/lists/partial"
mount --bind "$APT_CACHE_DIR" "$MNT_DIR/var/cache/apt/archives"
mount --bind "$APT_LISTS_DIR" "$MNT_DIR/var/lib/apt/lists"

# 8. Prevent service auto-start and sandbox restrictions during chroot install
cat << 'EOF' > "$MNT_DIR/usr/sbin/policy-rc.d"
#!/bin/sh
exit 101
EOF
chmod +x "$MNT_DIR/usr/sbin/policy-rc.d"

mkdir -p "$MNT_DIR/etc/apt/apt.conf.d"
echo 'APT::Sandbox::User "root";' > "$MNT_DIR/etc/apt/apt.conf.d/01sandbox"

# 9. Provision RootFS via QEMU AArch64 (uses persistent APT cache)
echo "--> Installing packages inside chroot (mpv, openssh, zram, DRM)..."
cp /usr/bin/qemu-aarch64-static "$MNT_DIR/usr/bin/qemu-aarch64-static"
chroot "$MNT_DIR" /bin/bash -c "
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive
    export LC_ALL=C
    apt-get update
    apt-get install -y --no-install-recommends \
        mpv \
        openssh-server \
        zram-tools \
        parted \
        dosfstools \
        mesa-va-drivers \
        libdrm2 \
        libgbm1
"
rm -f "$MNT_DIR/usr/bin/qemu-aarch64-static"
rm -f "$MNT_DIR/usr/sbin/policy-rc.d"
rm -f "$MNT_DIR/etc/apt/apt.conf.d/01sandbox"

# Unmount persistent cache so image rootfs contains 0MB cached debs
umount -l "$MNT_DIR/var/cache/apt/archives" 2>/dev/null || true
umount -l "$MNT_DIR/var/lib/apt/lists" 2>/dev/null || true
umount -l "$MNT_DIR/tmp" 2>/dev/null || true

# 10. Install Kiosk Scripts and Services
echo "--> Installing kiosk scripts and systemd services..."
mkdir -p "$MNT_DIR/etc/mpv"
cp "$BASE_DIR/configs/mpv.conf" "$MNT_DIR/etc/mpv/mpv.conf"
cp "$BASE_DIR/scripts/kiosk-player.sh" "$MNT_DIR/usr/local/bin/kiosk-player.sh"
cp "$BASE_DIR/scripts/kiosk-expand.sh" "$MNT_DIR/usr/local/bin/kiosk-expand.sh"
chmod +x "$MNT_DIR/usr/local/bin/kiosk-player.sh" "$MNT_DIR/usr/local/bin/kiosk-expand.sh"

cp "$BASE_DIR/scripts/kiosk-player.service" "$MNT_DIR/etc/systemd/system/kiosk-player.service"
cp "$BASE_DIR/scripts/kiosk-expand.service" "$MNT_DIR/etc/systemd/system/kiosk-expand.service"

mkdir -p "$MNT_DIR/usr/local/share/kiosk"
if [ -f "$BASE_DIR/assets/no-media.png" ]; then
    cp "$BASE_DIR/assets/no-media.png" "$MNT_DIR/usr/local/share/kiosk/no-media.png"
fi

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

# 13. Enable Services, mask unneeded background services, and silence TTY1
echo "--> Enabling systemd services, power-saving masks, and silencing TTY1..."
chroot "$MNT_DIR" /bin/bash -c "
    systemctl enable kiosk-player.service
    systemctl enable kiosk-expand.service
    systemctl enable ssh.service
    systemctl enable zramswap.service || true
    systemctl unmask serial-getty@ttyAMA0.service || true
    systemctl enable serial-getty@ttyAMA0.service || true
    systemctl mask getty@tty1.service
    systemctl mask bluetooth.service || true
    systemctl mask hciuart.service || true
    systemctl mask wpa_supplicant.service || true
    systemctl mask apt-daily.service || true
    systemctl mask apt-daily-upgrade.service || true
    systemctl mask apt-daily.timer || true
    systemctl mask apt-daily-upgrade.timer || true
    systemctl mask systemd-timesyncd.service || true
    systemctl mask logrotate.timer || true
    systemctl mask man-db.timer || true
    systemctl mask dpkg-db-backup.timer || true
    systemctl mask e2scrub_all.timer || true
    systemctl mask fstrim.timer || true
    systemctl mask systemd-random-seed.service || true
    systemctl mask dietpi-firstboot.service || true
    systemctl mask dietpi-fs_partition_resize.service || true
"

# 13a. Pre-mark DietPi setup as 100% completed to completely bypass the OOBE wizard
echo "--> Bypassing DietPi first-boot wizard (setting install_stage=2)..."
mkdir -p "$MNT_DIR/boot/dietpi" "$MNT_DIR/var/lib/dietpi"
echo 2 > "$MNT_DIR/boot/dietpi/.install_stage"
echo 2 > "$MNT_DIR/var/lib/dietpi/.install_stage" 2>/dev/null || true
touch "$MNT_DIR/boot/dietpi/.installed"
touch "$MNT_DIR/var/lib/dietpi/.installed" 2>/dev/null || true

# Remove DietPi login script interceptor so UART and SSH drop directly into clean bash prompt
rm -f "$MNT_DIR/etc/profile.d/dietpi-login.sh"
rm -f "$MNT_DIR/etc/bashrc.d/dietpi.bash" 2>/dev/null || true

# 13b. Configure Instant Root Auto-login on Serial Console (ttyAMA0)
# Uses Type=simple (instead of Type=idle) so it starts immediately without waiting for other jobs
echo "--> Configuring instant root autologin on UART (ttyAMA0)..."
mkdir -p "$MNT_DIR/etc/systemd/system/serial-getty@ttyAMA0.service.d"
cat << 'EOF' > "$MNT_DIR/etc/systemd/system/serial-getty@ttyAMA0.service.d/autologin.conf"
[Service]
Type=simple
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear -s %I 115200 vt220
EOF

# 13c. Configure Global Systemd Fast Timeouts (eliminate 90s/120s stalls)
echo "--> Configuring fast systemd timeouts (10s max)..."
mkdir -p "$MNT_DIR/etc/systemd/system.conf.d"
cat << 'EOF' > "$MNT_DIR/etc/systemd/system.conf.d/00-timeouts.conf"
[Manager]
DefaultTimeoutStartSec=10s
DefaultTimeoutStopSec=5s
EOF

# 13d. Configure Non-Blocking Ethernet (allow-hotplug avoids DHCP stall when unplugged)
echo "--> Configuring non-blocking network interfaces..."
cat << 'EOF' > "$MNT_DIR/etc/network/interfaces"
auto lo
iface lo inet loopback

allow-hotplug eth0
iface eth0 inet dhcp
EOF

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

# 16. Unmount cleanly and verify filesystem integrity
echo "--> Unmounting filesystems and syncing..."
sync
umount "$MNT_DIR/boot" 2>/dev/null || umount -l "$MNT_DIR/boot" 2>/dev/null || true
umount "$MNT_DIR/dev/pts" 2>/dev/null || umount -l "$MNT_DIR/dev/pts" 2>/dev/null || true
umount "$MNT_DIR/dev" 2>/dev/null || umount -l "$MNT_DIR/dev" 2>/dev/null || true
umount "$MNT_DIR/proc" 2>/dev/null || umount -l "$MNT_DIR/proc" 2>/dev/null || true
umount "$MNT_DIR/sys" 2>/dev/null || umount -l "$MNT_DIR/sys" 2>/dev/null || true
sync
umount "$MNT_DIR" 2>/dev/null || umount -l "$MNT_DIR" 2>/dev/null || true
rm -rf "$MNT_DIR"

echo "--> Verifying RootFS filesystem integrity..."
e2fsck -f -y "${LOOP_DEV}p2"

losetup -d "$LOOP_DEV"
LOOP_DEV=""

mv "$TARGET_RAW" "$TARGET_IMG"

# 17. Compress output image
echo "--> Compressing image to $TARGET_XZ (this may take a few minutes)..."
xz -T0 -k -9 -f "$TARGET_IMG" -c > "$TARGET_XZ"

echo "--> Generating SHA256 checksum..."
(cd "$OUTPUT_DIR" && sha256sum "$(basename "$TARGET_XZ")" > "$(basename "$TARGET_XZ").sha256")

if [ -n "${SUDO_USER:-}" ]; then
    chown -R "$SUDO_USER:$SUDO_USER" "$OUTPUT_DIR" "$BUILD_DIR" "$CACHE_DIR" 2>/dev/null || true
fi

echo "========================================================"
echo " BUILD SUCCESSFUL!"
echo " Image created: $TARGET_XZ"
echo " SHA256: $(cat "$TARGET_XZ.sha256")"
echo "========================================================"
