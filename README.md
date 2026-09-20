# Raspberry Pi 3 Video Kiosk

[![Version](https://img.shields.io/badge/version-0.9-34D399.svg)](https://github.com/Segilmez06/rpi3-videokiosk/releases)
[![Target](https://img.shields.io/badge/target-Raspberry%20Pi%203%20Model%20B-c51a4a.svg?logo=raspberry-pi)](https://www.raspberrypi.com/products/raspberry-pi-3-model-b/)
[![Architecture](https://img.shields.io/badge/arch-aarch64-blue.svg)](https://en.wikipedia.org/wiki/AArch64)
[![OS](https://img.shields.io/badge/base-Alpine%20Linux%203.24.2-0d597f.svg?logo=alpinelinux)](https://alpinelinux.org/)
[![Display](https://img.shields.io/badge/display-DRM%20KMS%20%2B%20VC4%20Gallium-orange.svg)](https://dri.freedesktop.org/)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

A commercial-grade, plug-and-play digital signage appliance for the **Raspberry Pi 3 Model B (`aarch64`)**. Engineered for exhibitions, retail installations, museums, and continuous display environments where power cuts are frequent, physical tampering must be prevented, and setup friction must be zero.

The system runs **100% in-RAM (`tmpfs`)** using a diskless Alpine Linux architecture. The SD card is unmounted during playback—enabling safe live physical hot-ejection—and filesystem corruption on abrupt power cuts is mathematically impossible.

---

## System Architecture

```
                       +---------------------------------------+
                       |      Power On / Hardware Reset        |
                       +---------------------------------------+
                                           |
                                           v
                       +---------------------------------------+
                       |  BCM2837 Firmware (config.txt)        |
                       |  - initial_turbo=20, arm_freq=1000   |
                       |  - Wi-Fi & Bluetooth hardware-off    |
                       +---------------------------------------+
                                           |
                                           v
                       +---------------------------------------+
                       |  Alpine initramfs (Linux 6.18)        |
                       |  - Green ACT LED blinking 100ms       |
                       |  - Early splash: "Booting up..."      |
                       |    via freestanding C blitter (fb0)   |
                       +---------------------------------------+
                                           |
                                           v
                       +---------------------------------------+
                       |  OpenRC Init & switch_root to RAM     |
                       |  - Entire rootfs unpacked to tmpfs    |
                       |  - vc4 / v3d DRM KMS initialized     |
                       |  - Splash: "Searching media..."       |
                       +---------------------------------------+
                                           |
                     +---------------------+---------------------+
                     |                                           |
                     v                                           v
      +-----------------------------+             +-----------------------------+
      | Video Payload <= 450 MB     |             | Video Payload > 450 MB      |
      | - Copied to /run/kiosk-videos|             | - Stream directly from SD   |
      | - SD card safely UNMOUNTED  |             | - Read-only VFS mount       |
      | - Safe for live hot-eject!  |             +-----------------------------+
      +-----------------------------+                            |
                     |                                           |
                     +---------------------+---------------------+
                                           |
                                           v
                       +---------------------------------------+
                       |  MPV Playback Engine (DRM KMS)        |
                       |  - Gapless loop (--prefetch-playlist) |
                       |  - V4L2 M2M hardware video decode     |
                       |  - STEALTH MODE: All board LEDs OFF   |
                       |  - Orientation: 0°, 90°, 180°, 270°   |
                       +---------------------------------------+
                                           |
                                           v
                       +---------------------------------------+
                       |  Background Replug Watcher            |
                       |  - Polling sysfs MMC host rescan      |
                       |  - SD re-inserted or USB drive added? |
                       |    -> "Rebooting..." + clean reset    |
                       +---------------------------------------+
```

---

## Why This Architecture?

| Criterion | Standard Raspberry Pi OS / DietPi | Video Kiosk (Alpine Run-from-RAM) |
| :--- | :--- | :--- |
| **Filesystem Safety** | Ext4 journal easily corrupts on sudden power cuts | **100% immune**; root filesystem exists only in volatile RAM |
| **SD Card Life** | Continuous disk writes degrade flash memory cells | **Zero write wear**; storage is mounted read-only, then unmounted |
| **Cold Boot Time** | ~35 – 55 seconds (systemd, udev, network, dbus) | **~6 – 8 seconds** (direct BusyBox + OpenRC into DRM KMS) |
| **Display Pipeline** | Overhead of X11/Wayland window server (~120MB RAM) | **Direct DRM KMS CRTC modesetting** via VideoCore IV Gallium |
| **Media Management** | SSH, Samba, or ext4 partitions hidden on Windows | **Single FAT32 partition** visible on Windows, macOS, and Linux |
| **Physical Hot-Swap** | Removing SD during playback causes kernel panic | **SD can be physically removed** while videos loop from RAM |
| **Console on HDMI** | Kernel logs, login prompt, blinking cursor on screen | **Completely silent HDMI**; console isolated to GPIO 14/15 UART |

---

## Operational State Indicators

The kiosk provides clear visual feedback on both the HDMI display and the physical board LEDs across every phase of its lifecycle:

### 1. HDMI Screen State Machine

All graphics render in 1080p using official Inter typography on a pure black background, featuring a subtle emerald green (`#34D399`) version watermark and white author credits on the bottom-left corner:

| State | Headline Title | Action Subtitle | Description |
| :--- | :--- | :--- | :--- |
| **Boot** | `Booting up...` | *Hang tight!* | Blitted to framebuffer (`/dev/fb0`) in early initramfs by `fbdraw`. |
| **Scan** | `Searching media...` | *Hang tight!* | Rendered via DRM KMS during media discovery and in-RAM VFS copying. |
| **No Media** | `No media found!` | *Please put content into media partition.* | Displayed statically when no valid video files exist on storage. |
| **Reboot** | `Rebooting...` | *This might take a few seconds.* | Triggered immediately when an SD card or USB drive is inserted. |

### 2. Hardware LED State Machine

| Operational Phase | Green (ACT) LED | Red (PWR) LED | Meaning |
| :--- | :--- | :--- | :--- |
| **Boot / RAM Copy** | **Blinking (100ms)** | **OFF** | Active unpacking or copying video files into RAM |
| **Video Playback** | **OFF** | **OFF** | **Stealth Mode:** No LED distraction in dark venue/exhibition |
| **No Media Alert** | **OFF** | **Blinking (100ms)** | Attention required: no video files found on media partition |
| **Replug / Reboot** | **Rapid Flash (50ms)** | **OFF** | New media detected; clean reboot initiated |

---

## Quick Start

### 1. Flashing the SD Card

Download the latest release artifact from the [Releases](https://github.com/Segilmez06/rpi3-videokiosk/releases) page:

#### Option A: Flash with `dd` (Recommended for fresh cards)
```bash
xzcat alpine-kiosk.img.xz | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
```
*(Replace `/dev/sdX` with your target SD card device).*

#### Option B: Direct FAT32 Extract (No disk formatting required)
If you have an existing SD card formatted as FAT32, simply extract the tarball onto the card root:
```bash
sudo tar -xzf alpine-kiosk-sdcard.tar.gz -C /media/your-sdcard/
```

### 2. Adding Videos

1. Insert the flashed SD card into your PC (Windows, macOS, or Linux).
2. Open the **`videos/`** directory.
3. Drop your video files into the folder. Files will play in alphabetical order.
4. Safely eject the card, insert it into the Raspberry Pi 3, and connect power.

> **Supported Formats:** `.mp4`, `.mkv`, `.avi`, `.mov`, `.webm`, `.ts` (H.264 / MPEG-4 AVC recommended).  
> **Filenames with Spaces:** Fully supported (e.g. `01 Welcome Video.mp4`).  
> **USB Drives:** You can also drop videos into a `videos/` folder on any standard USB thumb drive and plug it in.

### 3. Screen Rotation (`orientation.txt`)

To rotate the display for portrait totems or inverted ceiling mounts, edit `orientation.txt` on the SD card root:

| Value | Orientation | Notes |
| :--- | :--- | :--- |
| `0` | **Landscape (Standard)** | Default (0° rotation) |
| `90` | **Portrait (Clockwise)** | Vertical screens, totems (90° right) |
| `180` | **Inverted Landscape** | Ceiling or flipped mounts (180°) |
| `270` | **Inverted Portrait** | Vertical screens (90° left) |

Orientation can also be changed at runtime via serial console:
```bash
kiosk-orientation 90
```

---

## Hardware Configuration & Diagnostics

### 1. Dedicated PL011 Serial UART Console (GPIO 14/15)

For maintenance, debugging, or headless inspection without disturbing the HDMI signage display, connect a 3.3V USB-to-UART adapter to the Raspberry Pi GPIO header:

```
Raspberry Pi 3 Header:
  Pin  6  (GND) ---------> USB UART GND
  Pin  8  (GPIO 14 / TX) -> USB UART RX
  Pin 10  (GPIO 15 / RX) -> USB UART TX
```

- **Baud Rate:** `115200 8N1`
- **Shell:** Direct unprompted root autologin with `xterm-256color`.
- **Management Commands:**
  ```bash
  kiosk-player status     # View playback state, active playlist, and memory usage
  kiosk-player restart    # Reload media and restart MPV
  led status              # Inspect current trigger and brightness of ACT and PWR LEDs
  led red blink           # Manually test error blinking
  led stealth             # Turn off all onboard LEDs
  ```

### 2. Thermal & Power Mitigations

- **Clock Cap (`arm_freq=1000`):** Fixed at 1000 MHz to prevent voltage sags on budget 5V power adapters and maintain low operating temperatures without noisy fans.
- **Initial Turbo (`initial_turbo=20`):** Runs the CPU at full burst clock for the first 20 seconds to unpack system and copy media to RAM at maximum speed, then settles to 1000 MHz for sustained playback.
- **Disabled Radios:** Onboard Wi-Fi and Bluetooth are disabled in firmware (`dtoverlay=disable-wifi`, `dtoverlay=disable-bt`) to eliminate RF interference and save power.

---

## Technical Documentation (`docs/`)

For in-depth engineering breakdowns, refer to the technical guides in `docs/`:

- [**System Architecture & Diskless Design**](docs/architecture.md) — Pure RAM execution, Alpine `apkovl` overlay system, and the boot sequence.
- [**Display Pipeline & `fbdraw` Renderer**](docs/display-and-graphics.md) — Zero-libc freestanding AArch64 C renderer, DRM KMS handoff, and typography.
- [**Hardware, Power & UART Backend**](docs/hardware-and-power.md) — BCM2837 clock caps, brownout prevention, and serial terminal autologin.
- [**Media Caching & Playlist Engine**](docs/media-and-storage.md) — In-RAM tmpfs VFS, safe hot-ejection, and playlist prefetching.
- [**Hotplug Watcher & MMC Bus Polling**](docs/hotplug-and-reboot.md) — Detecting SD insertion without a Card Detect pin and automated reboot flow.
- [**Hardware LED State Machine**](docs/led-state-machine.md) — LED operational matrix and Linux kernel `ledtrig-timer` sysfs quirks.
- [**Build System & Offline Tooling**](docs/build-system.md) — Reproducible offline rootless image generation with `apk.static` and `mtools`.

---

## Building from Source

The entire appliance is built rootlessly on any modern Linux host (Arch Linux, CachyOS, Debian, Ubuntu):

### Host Dependencies
```bash
# Arch Linux / CachyOS:
sudo pacman -S mtools dosfstools tar curl xz clang lld llvm python python-pillow
```

### Build Command
```bash
./alpine-kiosk/build.sh
```

The build script will:
1. Fetch and verify official Alpine Linux 3.24.2 tarballs and developer signing keys.
2. Compile the freestanding `fbdraw` binary (`clang -target aarch64-linux-gnu -nostdlib -static`).
3. Patch `initramfs-rpi` with early splash blitting, DRM pruning, and LED triggers.
4. Download and cache required APK packages (`mpv`, `mesa-dri-gallium`, `eudev`, `alsa-utils`).
5. Build the appliance overlay archive (`rpi3-kiosk.apkovl.tar.gz`).
6. Generate both `output/alpine-kiosk.img.xz` and `output/alpine-kiosk-sdcard.tar.gz`.

---

## Credits & License

- **Author:** Sarp Eren EGILMEZ ([@Segilmez06](https://github.com/Segilmez06))
- **Typography:** [Inter font family](https://rsms.me/inter/) by Rasmus Andersson (SIL Open Font License).
- **License:** GNU General Public License v3.0 (GPLv3). See [LICENSE](LICENSE) for details.
