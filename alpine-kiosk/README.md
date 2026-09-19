# Raspberry Pi 3 Video Kiosk (Alpine Linux 3.24.2)

Ultra-fast, commercial-grade, power-cut-resilient video kiosk appliance for the **Raspberry Pi 3 Model B (Rev 1.2, aarch64)**.

---

## 🚀 Key Advantages & Architecture

| Feature | DietPi Baseline | Alpine Linux Kiosk |
| :--- | :--- | :--- |
| **Boot Mode** | Traditional `rw` root filesystem | **Pure Diskless (`run-from-RAM`)** |
| **Power-Cut Safety** | Vulnerable to inode/extent corruption | **100% physically immune to power cuts** |
| **SD Partitions** | 2 partitions (FAT32 boot + ext4 root) | **1 single FAT32 partition** |
| **Video Management** | SSH/SFTP or Linux ext4 mounting | **Drag-and-drop on Windows, Mac, Linux** |
| **Cold Boot Time** | ~40 – 50 seconds | **~6 – 8 seconds** |
| **Background Services**| systemd, journald, dbus, cron, network | **None (Pure BusyBox + OpenRC)** |
| **Display Architecture**| MPV DRM KMS | **MPV DRM KMS + VC4 Gallium + V4L2 M2M** |
| **Console Output** | HDMI text scrolling | **Silent HDMI / Exclusive UART ttyAMA0** |

---

## 📦 Output Artifacts

Artifacts are placed in `output/`:

1. **`output/alpine-kiosk.img.xz`**:
   - Ready-to-flash bootable disk image.
   - Flashed with `dd` or Raspberry Pi Imager.
2. **`output/alpine-kiosk-sdcard.tar.gz`**:
   - Tarball containing the exact boot partition contents.
   - Can be extracted directly onto any existing FAT32-formatted SD card (no disk imaging required).

---

## 💾 Flashing & Quick Start

### Option A: Flash with `dd` (Recommended for fresh cards)
```bash
xzcat output/alpine-kiosk.img.xz | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
```
*(Replace `/dev/sdX` with your target SD card device).*

### Option B: Copy to an Existing FAT32 SD Card
If you already have an SD card formatted as FAT32:
```bash
sudo tar -xzf output/alpine-kiosk-sdcard.tar.gz -C /media/your-sdcard/
```

---

## 🎬 Video Management

The SD card is a single standard **FAT32** partition labeled `VIDEOKIOSK`:
1. Insert the SD card into any PC (Windows, macOS, or Linux).
2. Open the **`videos/`** folder.
3. Drop your `.mp4`, `.mkv`, `.mov`, `.webm`, or `.avi` files into the folder.
4. Eject safely and insert into the Raspberry Pi 3.
5. Power on: videos loop continuously in alphabetical order.

*Note: If no user videos are provided, the kiosk automatically plays the bundled high-definition 1080p sample video.*

---

## 🔌 Hardware Setup & Features

### 1. Hardware UART Serial Console (Pins 8, 10, 6)
- **Baud Rate:** `115200 8N1`
- **Device:** `/dev/ttyAMA0` (PL011)
- **Autologin:** Instant root shell without password prompt.
- **Terminal:** Full `xterm-256color` without 80-column line-wrap constraints.
- **CLI Management:**
  ```bash
  kiosk-player status    # Check active player process & mounted storage
  kiosk-player restart   # Restart MPV playback loop
  kiosk-player stop      # Stop video playback
  ```

### 2. Stealth LED Management
- Both the **Red PWR LED** and **Green ACT LED** are hardware-disabled in `config.txt` and turned off during early boot.
- Eliminates visual distraction in dark exhibition rooms or retail installations.

### 3. Hardware Clock & Brownout Prevention
- Fixed clock cap at **1000 MHz** (`arm_freq=1000`) prevents voltage sag / brownouts on marginal USB power supplies.

---

## 🛠️ Building From Source

To rebuild the Alpine kiosk appliance from scratch:
```bash
./alpine-kiosk/build.sh
```
All dependencies, official Alpine 3.24.2 release tarballs, and apk package caches are stored locally in `cache/` and processed rootlessly with `mtools`.
