# Raspberry Pi 3 Headless Video Kiosk

A reproducible, headless, silent video kiosk appliance for the Raspberry Pi 3 (ARM64) running DietPi, direct DRM/KMS `mpv`, and a dedicated auto-expanding FAT32 media partition.

## Key Features

- **Direct DRM/KMS Hardware Accelerated Playback**: Uses `mpv` rendering straight to the Linux Kernel Mode Setting / Direct Rendering Manager (`--vo=gpu --gpu-context=drm`). No X11 or Wayland overhead.
- **Zero UI / Completely Silent**:
  - Blinking console cursor disabled (`vt.global_cursor_default=0`).
  - Kernel and boot splash disabled (`quiet loglevel=3 logo.nologo disable_splash=1`).
  - `getty@tty1` disabled (no login prompts ever appear on screen).
  - `mpv` runs with all OSDs, progress bars, and terminal output silenced.
- **Dedicated FAT32 Video Partition**:
  - Fully accessible from Windows, macOS, and Linux when plugging the SD card into a computer.
  - End-users can drag and drop `.mp4`, `.mkv`, `.mov`, `.avi`, or `.webm` files directly into the `VIDEOS` drive.
  - Mounted **read-only (`ro`)** during playback to protect against corruption from sudden power cuts.
- **Automatic First-Boot Partition Expansion**:
  - Automatically resizes the media partition to claim **100% of all remaining space** on any SD card size (from 2GB up to 512GB+).
  - Preserves any files copied onto the partition prior to first boot.
- **2GB SD Card Ready**:
  - Base image is sized at ~1.8 GB, allowing it to be flashed even to legacy 2GB micro-SD cards.
- **SD Wear Mitigation & Power-Cut Resilience**:
  - `noatime,commit=60` on rootfs.
  - Full RAM logging via `dietpi-ramlog` (tmpfs).
  - Disk swap disabled.
  - ZRAM swap enabled (`zstd` compression).
- **Redundancy & Maintenance Access**:
  - OpenSSH server pre-installed and enabled.
  - Key-based access configured with authorized SSH public keys.

---

## Partition Layout

```
+-----------------------------------------------------------------------------------+
| SD Card (e.g. 2GB, 8GB, 16GB, 32GB, 64GB, 128GB+)                                 |
+-------------------+----------------------------+----------------------------------+
| Partition 1       | Partition 2                | Partition 3                      |
| /boot (FAT32)     | / (ext4 rootfs)            | /media/videos (FAT32)            |
| ~128 MB           | ~1.1 GB (~400MB free)      | Expands to fill 100% of remaining |
| Boot firmware     | DietPi + mpv + RAM log     | Mounts RO during video playback  |
| Visible to PC     | Hidden on Windows          | Visible & writable on PC/Mac     |
+-------------------+----------------------------+----------------------------------+
```

---

## How to Build the Image

### Prerequisites (Host Linux)
- Arch Linux / CachyOS / Debian / Ubuntu with:
  - `parted`, `losetup`, `kpartx`, `dosfstools`, `xz`, `curl`
  - `qemu-user-static` and `binfmt_misc` with `qemu-aarch64` registered

### Building
Run the automated builder as root (or via sudo):
```bash
sudo ./build.sh
```
The script will:
1. Cache the base DietPi Bookworm ARM64 image in `cache/`.
2. Configure the 3-partition geometry.
3. Chroot into the ARM64 rootfs via QEMU.
4. Pre-install `mpv`, `fatresize`, `openssh-server`, and `zram-tools`.
5. Install kiosk services, silent boot parameters, and authorized SSH keys.
6. Package the final image into `output/rpi3-videokiosk.img.xz` along with a SHA256 checksum.

---

## Flashing & User Instructions

1. **Flash**: Write `output/rpi3-videokiosk.img.xz` to an SD card using **Raspberry Pi Imager** or **BalenaEtcher**.
2. **Copy Videos**:
   - Re-insert the SD card into your PC.
   - You will see a drive named **`VIDEOS`**.
   - Copy your `.mp4` video files directly into this drive.
   - Videos will be played in **alphabetical order** in a continuous loop.
3. **Boot**:
   - Insert the SD card into the Raspberry Pi 3.
   - Connect HDMI to the display and connect power.
   - On first boot, the Pi will silently expand the `VIDEOS` partition to fill the SD card and start playing immediately.
