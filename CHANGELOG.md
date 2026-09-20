# Changelog

All notable changes to the Raspberry Pi 3 Video Kiosk appliance are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [v0.9] - 2026-09-20
### Commit: `HEAD`
### Added
- **Unified 4-State UI Screen Suite**:
  - `Booting up...` (`assets/booting.png`): early initramfs boot splash with subtitle *"Hang tight!"*.
  - `Searching media...` (`assets/searching.png`): userspace DRM KMS splash bridging the initramfs-to-video handoff with subtitle *"Hang tight!"*.
  - `No media found!` (`assets/no-media.png`): persistent fallback alert with actionable subtitle *"Please put content into media partition."*.
  - `Rebooting...` (`assets/rebooting.png`): instant visual notification on SD/USB replug with subtitle *"This might take a few seconds."*.
- **DRM KMS Reboot Screen Renderer**: Dispatched via hardware DRM KMS MPV upon media replug with fallback framebuffer blit (`fbdraw` on `/dev/fb0`).
- **Dynamic Version Watermark**: Single source of truth in `VERSION` dynamically rendered into screen assets via `alpine-kiosk/scripts/generate-screens.py`.
- **Active MMC Bus Polling**: Background sysfs polling (`/sys/class/mmc_host/*/rescan`) combined with 512-byte sector read validation to reliably detect SD card removal and insertion without a physical Card Detect pin.

---

## [v0.8] - 2026-09-20
### Commit: `e280dad`
### Added
- **Real-Time Media Hotplug Watcher**: Automated detection of USB flash drives and SD card re-insertion.
- **Automated Clean Reboot Engine**: Triggers a rapid 50ms Green ACT flash and 2-second countdown before rebooting into new media.
- **Udev Event Integration**: Block device rule `99-kiosk-replug.rules` triggering `/usr/bin/kiosk-replug-handler.sh`.

---

## [v0.7] - 2026-09-20
### Commit: `d03fbaa`
### Added
- **Freestanding Framebuffer Renderer (`fbdraw`)**: Standalone AArch64 C program with zero libc dependencies and raw Linux syscalls (`openat`, `ioctl`, `mmap`, `read`), compiled to a 4.8 KB binary for instant splash rendering.
- **Inter Typography Engine**: Integrated official `assets/fonts/Inter-Variable.ttf` for variable font weight rendering across all kiosk screens.
- **Branding & Credits Watermark**: Emerald green (`#34D399`) version line and pure white (`#FFFFFF`) author credit (`by Sarp Eren EGILMEZ`) on bottom-left screen corner.

---

## [v0.6] - 2026-09-20
### Commit: `956b1ec`
### Added
- **Dynamic Display Orientation Engine**: Supports 4 screen angles:
  - `0`: Landscape / Normal
  - `90`: Portrait / Clockwise
  - `180`: Inverted Landscape / Upside-down
  - `270`: Inverted Portrait / Counter-clockwise
- **SD Card Boot Config**: Detects orientation from `orientation.txt` on the SD card root partition.
- **Runtime Orientation Persistence**: Caches orientation state to `/run/kiosk-orientation`.

---

## [v0.5] - 2026-09-20
### Commit: `4c60cf3`
### Added
- **Hardware LED Operational State Machine**:
  - Booting / In-RAM Copying: Green ACT blinking 100ms timer; Red PWR off.
  - Playback Mode: Full stealth mode (all LEDs off) for clean exhibition and signage use.
  - Missing Media Alert: Red PWR blinking 100ms; Green ACT off.
  - Media Detected / Reboot: Green ACT pulsing rapidly (50ms).
- **Command-Line LED Utility**: Bundled `/usr/bin/led` utility for manual testing (`led status`, `led stealth`, `led act blink`).

---

## [v0.4] - 2026-09-20
### Commit: `831fbcb`
### Added
- **Smart In-RAM VFS Media Caching**: Automatically copies video payloads up to 450 MB into `/run/kiosk-videos` (`tmpfs`).
- **Live Physical SD Hot-Ejection**: Safely unmounts the SD card once media is in RAM, allowing users to physically eject the SD card while videos play indefinitely.
- **Gapless Multi-Video Playlist Loop**: Infinite playlist loop with prefetching (`--prefetch-playlist=yes`) and space-safe filename parsing for MP4, MKV, AVI, MOV, WEBM, and TS containers.

---

## [v0.3] - 2026-09-20
### Commit: `1f24cbc`
### Added
- **Pure Run-from-RAM Diskless Architecture**: Complete migration to Alpine Linux 3.24.2 with diskless `tmpfs` rootfs.
- **Power-Cut Immune Design**: 100% immune to filesystem corruption on sudden unplug/brownout.
- **Rootless Build Pipeline**: Offline build tooling using static `apk.static` and `mcopy`, generating dual distribution artifacts (`.img.xz` disk image and `.tar.gz` direct FAT32 extract).

---

## [v0.2] - 2026-09-19
### Commit: `50a569b`
### Added
- **Dedicated PL011 Hardware UART Backend**: Serial console enabled on GPIO 14/15 (`ttyAMA0`, Pins 8/10/6) at 115200 baud.
- **Instant Root Autologin**: Frictionless debugging shell with `xterm-256color` terminal definition.
- **Silent HDMI Signage Display**: Completely stripped console output, login prompts, and blinking text cursors from HDMI.

---

## [v0.1] - 2026-09-19
### Commit: `204fdef`
### Added
- **Headless Video Kiosk Appliance**: Initial automated image build system targeting Raspberry Pi 3 Model B (`aarch64`).
- **Hardware Power & Thermal Mitigations**: CPU capped at 1000 MHz, initial turbo burst clock for fast boot, undervolt prevention.
- **Core Playback Engine**: MPV media player with DRM KMS and V4L2 M2M hardware video decoding on VideoCore IV Gallium GPU.
- **RF Radio Disable**: Onboard Wi-Fi and Bluetooth disabled in firmware for zero interference and power savings.

---

## Git Tagging Reference

To tag all historical milestones and push them to GitHub:

```bash
git tag -a v0.1 204fdef -m "Release v0.1: Initial Headless Video Kiosk Appliance & Build System"
git tag -a v0.2 50a569b -m "Release v0.2: Dedicated PL011 Hardware UART Backend & Silent HDMI Signage"
git tag -a v0.3 1f24cbc -m "Release v0.3: Pure Run-from-RAM Diskless Alpine Linux Architecture"
git tag -a v0.4 831fbcb -m "Release v0.4: Smart In-RAM VFS Media Caching & Gapless Multi-Video Playlist Loop"
git tag -a v0.5 4c60cf3 -m "Release v0.5: Hardware LED Operational State Machine & Stealth Mode"
git tag -a v0.6 956b1ec -m "Release v0.6: Dynamic Display Orientation Engine"
git tag -a v0.7 d03fbaa -m "Release v0.7: Freestanding Framebuffer Renderer (fbdraw) & Custom Typography"
git tag -a v0.8 e280dad -m "Release v0.8: Real-Time Media Hotplug Watcher & Automated Reboot Handler"
git tag -a v0.9 HEAD    -m "Release v0.9: Unified 4-State UI Pipeline & Framebuffer-to-DRM KMS Handoff"

# Push all tags to remote:
git push origin --tags
```
