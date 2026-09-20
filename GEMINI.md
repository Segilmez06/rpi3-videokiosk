# Workspace Memory & Rules: Raspberry Pi 3 Video Kiosk

## Project Overview
Commercial-grade, plug-and-play digital signage video kiosk for Raspberry Pi 3 Model B (`aarch64`) running Alpine Linux 3.24.2 in pure run-from-RAM diskless mode.

## Versioning Policy & Workflow Rules
- **Single Source of Truth:** The project version is stored in `VERSION` at the repository root.
- **Rule - Version Increment:**
  - **Major Features (0.x):** Whenever a new big feature or major architectural/functional update is added, increment the minor version (e.g. `v0.9`, `v0.10`).
  - **Hotfixes & Small Changes (0.x.y):** Incremental improvements, bug fixes, CI/CD tweaks, and minor enhancements use `.increment` format (e.g. `v0.9.1`).
- **Rule - Mandatory Asset Regeneration:** After any version increment, screen assets MUST be regenerated via `alpine-kiosk/scripts/generate-screens.py`, and the milestone recorded in `GEMINI.md`.
- **Rule - Branching & Verification:** Work is tracked and pushed to the remote `dev` branch. Pull requests into `main` must pass all pre-merge CI verification checks and be verified before merging.
- **Watermark Format:** All screen graphics display `"Video Kiosk <VERSION> (<short-hash>)"` in emerald green (`#34D399`) and `"by Sarp Eren EGILMEZ"` in pure white (`#FFFFFF`) on the bottom-left corner using Inter Medium font.

---

## Chronological Big Feature Milestones

1. **v0.1: Initial Headless Video Kiosk Appliance & Build System**
   - Headless image build framework targeting Raspberry Pi 3 Model B (`aarch64`).
   - Hardware-level safety mitigations: CPU clock capping at 1000 MHz, initial turbo burst clock for quick boot, undervolt/brownout prevention.
   - Core MPV playback engine using DRM KMS and V4L2 M2M video decoding on VC4 Gallium GPU.
   - Disabling onboard Wi-Fi and Bluetooth radios for zero RF interference and power optimization.

2. **v0.2: Dedicated PL011 Hardware UART Backend & Silent HDMI Signage**
   - Hardware serial UART console on GPIO 14/15 (`ttyAMA0`, Pins 8/10/6) at 115200 baud.
   - Instant root autologin with `xterm-256color` for zero-friction debugging and headless maintenance.
   - Completely silent HDMI display: stripped all kernel/init console output, login prompts, and blinking text cursors.

3. **v0.3: Pure Run-from-RAM Diskless Alpine Linux Architecture**
   - Architectural migration to Alpine Linux 3.24.2 with diskless run-from-RAM (`tmpfs`) rootfs.
   - 100% immune to SD card filesystem corruption on sudden power-cuts.
   - Clean, rootless offline image generation pipeline using static tools (`apk.static`, `mcopy`) with dual delivery formats (`.img.xz` disk image and `.tar.gz` direct FAT32 extract).

4. **v0.4: Smart In-RAM VFS Media Caching & Gapless Multi-Video Playlist Loop**
   - Media caching engine into `/run/kiosk-videos` tmpfs for payloads up to 450 MB.
   - Automatic SD card unmounting after in-RAM copying, enabling safe physical hot-ejection of the SD card while videos play.
   - Gapless multi-video playlist looping (`--prefetch-playlist=yes`, `--loop-playlist=inf`) with full space-safe filename support across all standard formats (MP4, MKV, AVI, MOV, WEBM, TS).

5. **v0.5: Hardware LED Operational State Machine & Stealth Mode**
   - Custom LED indicator state machine communicating kiosk state through physical board LEDs:
     - Boot / In-RAM Copying: Green ACT blinking with 100ms timer; Red PWR off.
     - Playback Mode: Full stealth mode (all LEDs off) for seamless presentation in retail/exhibition environments.
     - Missing Media Alert: Red PWR blinking 100ms; Green ACT off.
     - Media Detected / Reboot: Green ACT flashing rapidly (50ms).
   - Bundled `/usr/bin/led` command-line utility for manual LED debugging and inspection.

6. **v0.6: Dynamic Display Orientation Engine**
   - Support for multiple screen orientations: Landscape (0°), Portrait (90°), Inverted Landscape (180°), Inverted Portrait (270°).
   - Automated detection at boot from `orientation.txt` on the SD card root, with persistent runtime rotation state in `/run/kiosk-orientation`.

7. **v0.7: Freestanding Framebuffer Renderer (`fbdraw`) & Custom Typography**
   - Custom freestanding AArch64 C framebuffer blitter (`fbdraw`) with zero libc dependencies and direct Linux syscalls for early initramfs boot splash display.
   - Official Inter typography rendering (`assets/fonts/Inter-Variable.ttf`), with variable font weight and crisp 1080p graphics.
   - Integrated emerald green brand watermark and pure white author credits (`by Sarp Eren EGILMEZ`).

8. **v0.8: Real-Time Media Hotplug Watcher & Automated Reboot Handler**
   - Automated detection of media re-insertion and USB drive attachment using udev rules (`99-kiosk-replug.rules`) and background sysfs MMC rescan polling.
   - Clean automated reboot workflow on media change to dynamically refresh and play newly added video files.

9. **v0.9: Unified 4-State UI Pipeline & Seamless Framebuffer-to-DRM KMS Handoff**
   - Complete 4-stage UI lifecycle screen suite:
     1. `"Booting up..."` (early initramfs boot splash)
     2. `"Searching media..."` (userspace DRM KMS / media scan / RAM caching, bridging the gap to video playback)
     3. `"No media found!"` (persistent alert with instructions when no videos exist)
     4. `"Rebooting..."` (instant visible screen when SD/USB replug is detected)
   - Synchronized titles with progress ellipsis (`...`) and clear user-facing action subtitles (`"Hang tight!"`, `"This might take a few seconds."`, `"Please put content into media partition."`).

10. **v0.9.1: Hotfix, CI/CD Automation & Documentation Overhaul**
    - Integrated GitHub Actions automated build and release pipeline targeting `main` with native auto-generated release notes.
    - Replaced all static ASCII schematics across documentation with interactive GitHub-native Mermaid flowcharts and state diagrams.
    - Streamlined `README.md`, moving deep system architecture and benchmark tables into dedicated documentation in `docs/architecture.md`.
    - Standardized SD card flashing command to `bs=64k status=progress oflag=sync` across all documentation and build scripts.
    - Hardened UART security (SEC-01): Replaced unprompted root autologin with authenticated serial console, locked system accounts, and enabled optional SD card `password.txt` dynamic override.
