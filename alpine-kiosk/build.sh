#!/usr/bin/env bash
# ==============================================================================
# Raspberry Pi 3 Model B (aarch64) Video Kiosk Builder
# OS: Alpine Linux 3.24.2 (Diskless / Pure Run-from-RAM Architecture)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

ALPINE_VER="3.24.2"
ALPINE_BRANCH="v3.24"
ARCH="aarch64"

CACHE_DIR="${ROOT_DIR}/cache/alpine-${ALPINE_VER}"
BIN_CACHE="${ROOT_DIR}/cache/bin"
BUILD_DIR="${SCRIPT_DIR}/build"
STAGING_DIR="${BUILD_DIR}/staging"
OUTPUT_DIR="${ROOT_DIR}/output"

MIRROR_URL="https://dl-cdn.alpinelinux.org/alpine"
TARBALL_NAME="alpine-rpi-${ALPINE_VER}-${ARCH}.tar.gz"
TARBALL_URL="${MIRROR_URL}/${ALPINE_BRANCH}/releases/${ARCH}/${TARBALL_NAME}"

echo "============================================================"
echo " Building Raspberry Pi 3 Video Kiosk (Alpine Linux ${ALPINE_VER})"
echo "============================================================"

# ------------------------------------------------------------------------------
# 1. Host Dependency Check
# ------------------------------------------------------------------------------
echo "[*] Checking host dependencies..."
MISSING_TOOLS=()
for tool in curl tar gzip xz parted mkfs.vfat mcopy mmd mdir; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        MISSING_TOOLS+=("$tool")
    fi
done

if [ ${#MISSING_TOOLS[@]} -gt 0 ]; then
    echo "[-] Error: Missing required host tools: ${MISSING_TOOLS[*]}"
    echo "    Install them with: sudo pacman -S --needed curl tar gzip xz parted dosfstools mtools"
    exit 1
fi

mkdir -p "${CACHE_DIR}" "${BIN_CACHE}" "${BUILD_DIR}" "${OUTPUT_DIR}"

# ------------------------------------------------------------------------------
# 2. Download & Cache Official Alpine Release Tarball
# ------------------------------------------------------------------------------
if [ ! -f "${CACHE_DIR}/${TARBALL_NAME}" ]; then
    echo "[*] Downloading official Alpine ${ALPINE_VER} RPi tarball..."
    curl -fL --progress-bar -o "${CACHE_DIR}/${TARBALL_NAME}" "${TARBALL_URL}"
else
    echo "[+] Using cached Alpine ${ALPINE_VER} release tarball."
fi

# ------------------------------------------------------------------------------
# 3. Setup apk.static and Keys for Package Operations
# ------------------------------------------------------------------------------
APK_STATIC="${BIN_CACHE}/sbin/apk.static"
KEYS_DIR="${CACHE_DIR}/keys"

if [ ! -f "${APK_STATIC}" ]; then
    echo "[*] Downloading static apk-tools binary..."
    mkdir -p "${BIN_CACHE}"
    curl -fLs "${MIRROR_URL}/${ALPINE_BRANCH}/main/x86_64/apk-tools-static-3.0.8-r0.apk" \
        | tar -xz -C "${BIN_CACHE}" sbin/apk.static 2>/dev/null
    chmod +x "${APK_STATIC}"
fi

if [ ! -d "${KEYS_DIR}" ] || [ -z "$(ls -A "${KEYS_DIR}" 2>/dev/null)" ]; then
    echo "[*] Extracting official Alpine developer signing keys..."
    mkdir -p "${KEYS_DIR}"
    tar -Oxz --wildcards -f "${CACHE_DIR}/${TARBALL_NAME}" './apks/aarch64/alpine-keys-*.apk' \
        | tar -xz -C "${CACHE_DIR}" usr/share/apk/keys 2>/dev/null
    cp "${CACHE_DIR}/usr/share/apk/keys"/*.rsa.pub "${KEYS_DIR}/"
    rm -rf "${CACHE_DIR}/usr"
fi

# ------------------------------------------------------------------------------
# 4. Prepare Staging Root (FAT32 Boot Partition Layout)
# ------------------------------------------------------------------------------
echo "[*] Unpacking Alpine base system to staging directory..."
rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}"

tar -xzf "${CACHE_DIR}/${TARBALL_NAME}" -C "${STAGING_DIR}"

# Remove default apks folder from release tarball (we will generate full multi-repo structure)
rm -rf "${STAGING_DIR}/apks"

# Patch initramfs with hardware LED state machine (Red 100ms blink -> Green solid)
if [ -f "${STAGING_DIR}/boot/initramfs-rpi" ]; then
    echo "[*] Injecting hardware LED boot sequence into initramfs-rpi..."
    python3 "${SCRIPT_DIR}/scripts/patch_initramfs.py" "${STAGING_DIR}/boot/initramfs-rpi"
fi

# ------------------------------------------------------------------------------
# 5. Build Offline APK Repositories (Main & Community)
# ------------------------------------------------------------------------------
echo "[*] Fetching and caching full package dependencies (mpv, mesa, eudev, alsa)..."
PKG_CACHE="${CACHE_DIR}/packages"
mkdir -p "${PKG_CACHE}"

# Fetch official repository indices
MAIN_INDEX_DIR="${STAGING_DIR}/apks/main/${ARCH}"
COMM_INDEX_DIR="${STAGING_DIR}/apks/community/${ARCH}"
mkdir -p "${MAIN_INDEX_DIR}" "${COMM_INDEX_DIR}"
touch "${STAGING_DIR}/apks/main/.boot_repository"
touch "${STAGING_DIR}/apks/community/.boot_repository"

if [ ! -f "${CACHE_DIR}/APKINDEX-main.tar.gz" ]; then
    curl -fLs "${MIRROR_URL}/${ALPINE_BRANCH}/main/${ARCH}/APKINDEX.tar.gz" -o "${CACHE_DIR}/APKINDEX-main.tar.gz"
fi
if [ ! -f "${CACHE_DIR}/APKINDEX-community.tar.gz" ]; then
    curl -fLs "${MIRROR_URL}/${ALPINE_BRANCH}/community/${ARCH}/APKINDEX.tar.gz" -o "${CACHE_DIR}/APKINDEX-community.tar.gz"
fi

cp "${CACHE_DIR}/APKINDEX-main.tar.gz" "${MAIN_INDEX_DIR}/APKINDEX.tar.gz"
cp "${CACHE_DIR}/APKINDEX-community.tar.gz" "${COMM_INDEX_DIR}/APKINDEX.tar.gz"

# Generate main package membership list for sorting
tar -Oxz -f "${CACHE_DIR}/APKINDEX-main.tar.gz" APKINDEX \
    | grep -E '^P:' | cut -c3- | sort -u > "${BUILD_DIR}/main.list"

# Core kiosk package world: alpine-base eudev mesa-dri-gallium mpv
REQUIRED_PKGS=(alpine-base eudev mesa-dri-gallium mpv)

echo "[*] Resolving and downloading packages with apk.static..."
"${APK_STATIC}" fetch \
    --keys-dir "${KEYS_DIR}" \
    --arch "${ARCH}" \
    -X "${MIRROR_URL}/${ALPINE_BRANCH}/main" \
    -X "${MIRROR_URL}/${ALPINE_BRANCH}/community" \
    -o "${PKG_CACHE}" \
    -R "${REQUIRED_PKGS[@]}"

# Distribute packages into main and community directories
echo "[*] Organizing packages into official signed offline repositories..."
for apk_file in "${PKG_CACHE}"/*.apk; do
    [ -e "$apk_file" ] || continue
    pkg_basename="$(basename "$apk_file")"
    pkg_name="$(echo "$pkg_basename" | sed -E 's/-[0-9].*//')"

    if grep -qx "$pkg_name" "${BUILD_DIR}/main.list"; then
        cp -u "$apk_file" "${MAIN_INDEX_DIR}/"
    else
        cp -u "$apk_file" "${COMM_INDEX_DIR}/"
    fi
done

echo "    -> Main repo packages:      $(ls "${MAIN_INDEX_DIR}"/*.apk | wc -l)"
echo "    -> Community repo packages: $(ls "${COMM_INDEX_DIR}"/*.apk | wc -l)"

# ------------------------------------------------------------------------------
# 6. Apply Firmware & Kernel Configurations
# ------------------------------------------------------------------------------
echo "[*] Injecting hardware configurations (config.txt, cmdline.txt)..."
cp "${SCRIPT_DIR}/configs/config.txt" "${STAGING_DIR}/config.txt"
cp "${SCRIPT_DIR}/configs/cmdline.txt" "${STAGING_DIR}/cmdline.txt"

# ------------------------------------------------------------------------------
# 7. Generate Alpine Local Backup Overlay (rpi3-kiosk.apkovl.tar.gz)
# ------------------------------------------------------------------------------
echo "[*] Building appliance overlay archive (rpi3-kiosk.apkovl.tar.gz)..."
APKOVL_FILE="${STAGING_DIR}/rpi3-kiosk.apkovl.tar.gz"

# Compile freestanding fbdraw utility for overlay
if [ -f "${SCRIPT_DIR}/scripts/fbdraw.c" ]; then
    echo "[*] Compiling freestanding fbdraw utility for appliance overlay..."
    clang -target aarch64-linux-gnu -fuse-ld=lld -static -nostdlib -fno-stack-protector -O2 \
        "${SCRIPT_DIR}/scripts/fbdraw.c" -o "${SCRIPT_DIR}/overlay/usr/bin/fbdraw"
    llvm-strip "${SCRIPT_DIR}/overlay/usr/bin/fbdraw" 2>/dev/null || true
    chmod 755 "${SCRIPT_DIR}/overlay/usr/bin/fbdraw"
fi

mkdir -p "${SCRIPT_DIR}/overlay/usr/share/videokiosk"
if [ -f "${ROOT_DIR}/assets/no-media.png" ]; then
    cp "${ROOT_DIR}/assets/no-media.png" "${SCRIPT_DIR}/overlay/usr/share/videokiosk/no-media.png"
fi
if [ -f "${ROOT_DIR}/assets/booting.png" ]; then
    cp "${ROOT_DIR}/assets/booting.png" "${SCRIPT_DIR}/overlay/usr/share/videokiosk/booting.png"
    python3 -c "
from PIL import Image
im = Image.open('${ROOT_DIR}/assets/booting.png').convert('RGB')
im.save('${SCRIPT_DIR}/overlay/usr/share/videokiosk/booting.ppm', format='PPM')
" 2>/dev/null || true
fi

# Create apkovl tar.gz preserving root ownership
tar -czf "${APKOVL_FILE}" \
    --owner=0 --group=0 --numeric-owner \
    -C "${SCRIPT_DIR}/overlay" .

# Also copy as localhost.apkovl.tar.gz for maximum compatibility
cp "${APKOVL_FILE}" "${STAGING_DIR}/localhost.apkovl.tar.gz"

# ------------------------------------------------------------------------------
# 8. Setup Videos Directory, Orientation Config, and Splash Image
# ------------------------------------------------------------------------------
echo "[*] Setting up /videos directory, orientation.txt, and splash.png for user media..."
mkdir -p "${STAGING_DIR}/videos"
cat << 'EOF' > "${STAGING_DIR}/orientation.txt"
# Video Kiosk Display Orientation
# Options: 0 (Landscape / Normal), 90 (Portrait), 180 (Inverted Landscape), 270 (Inverted Portrait)
0
EOF

if [ -f "${ROOT_DIR}/assets/booting.png" ]; then
    cp "${ROOT_DIR}/assets/booting.png" "${STAGING_DIR}/splash.png"
fi


# ------------------------------------------------------------------------------
# 9. Output Format A: SD Card Extraction Archive (.tar.gz)
# ------------------------------------------------------------------------------
SDCARD_ARCHIVE="${OUTPUT_DIR}/alpine-kiosk-sdcard.tar.gz"
echo "[*] Generating direct-to-FAT32 archive: ${SDCARD_ARCHIVE}..."
tar -czf "${SDCARD_ARCHIVE}" -C "${STAGING_DIR}" .

# ------------------------------------------------------------------------------
# 10. Output Format B: Bootable Disk Image (.img.xz)
# ------------------------------------------------------------------------------
RAW_IMG="${BUILD_DIR}/alpine-kiosk.img"
FINAL_XZ="${OUTPUT_DIR}/alpine-kiosk.img.xz"

echo "[*] Generating single-partition FAT32 disk image..."
# Calculate required size: staging size + 128MB safety margin
STAGING_MB=$(du -sm "${STAGING_DIR}" | awk '{print $1}')
IMG_MB=$((STAGING_MB + 128))
# Round up to nearest 64MB boundary
IMG_MB=$(( ((IMG_MB + 63) / 64) * 64 ))

echo "    Staging payload: ${STAGING_MB} MB -> Creating disk image: ${IMG_MB} MB"
rm -f "${RAW_IMG}"
truncate -s "${IMG_MB}M" "${RAW_IMG}"

# Partition: MBR, 1 primary FAT32 partition starting at sector 2048 (1MiB offset), bootable
parted -s "${RAW_IMG}" mklabel msdos mkpart primary fat32 2048s 100% set 1 boot on

# Format partition as FAT32 labeled VIDEOKIOSK
mkfs.vfat -F 32 -n "VIDEOKIOSK" --offset 2048 "${RAW_IMG}" >/dev/null

# Copy staging contents into partition using mcopy (1048576 bytes offset = sector 2048 * 512)
echo "[*] Populating FAT32 filesystem with mcopy (rootless)..."
mcopy -s -i "${RAW_IMG}@@1048576" "${STAGING_DIR}"/* ::

# Compress with xz
echo "[*] Compressing disk image with xz (multi-threaded)..."
rm -f "${FINAL_XZ}"
xz -T0 -3 "${RAW_IMG}" -c > "${FINAL_XZ}"
rm -f "${RAW_IMG}"

# ------------------------------------------------------------------------------
# 11. Completion & Verification
# ------------------------------------------------------------------------------
echo ""
echo "============================================================"
echo " BUILD SUCCESSFUL!"
echo "============================================================"
echo "Generated Artifacts:"
ls -lh "${SDCARD_ARCHIVE}" "${FINAL_XZ}"
echo ""
echo "SHA256 Checksums:"
sha256sum "${SDCARD_ARCHIVE}" "${FINAL_XZ}"
echo "============================================================"
echo "Flashing Instructions:"
echo "  Option A (Existing FAT32 SD card):"
echo "    sudo tar -xzf ${SDCARD_ARCHIVE} -C /media/your-sdcard/"
echo ""
echo "  Option B (Raw flash with dd):"
echo "    xzcat ${FINAL_XZ} | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync"
echo "============================================================"
