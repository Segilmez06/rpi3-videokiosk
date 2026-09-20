# Display Pipeline & Graphics Subsystem

The Raspberry Pi 3 Video Kiosk implements a seamless, silent graphics pipeline designed to eliminate blinking cursors, boot log spam, visual tearing, and black screens across all device states.

---

## 1. Unified 4-State Visual Lifecycle Pipeline

The display engine guides the user through four distinct operational states, each paired with synchronized typography and consistent visual cues:

```
[ Power On ]
      |
      v
+-----------------------------------------------------------------------------+
| State 1: "Booting up..." (early initramfs)                                  |
| Renderer: fbdraw (direct /dev/fb0 memory map)                               |
| Subtitle: "Hang tight!"                                                     |
| Purpose:  Immediate visual feedback (< 1.2s from cold power).               |
+-----------------------------------------------------------------------------+
      |
      v
+-----------------------------------------------------------------------------+
| State 2: "Searching media..." (userspace start)                             |
| Renderer: MPV on DRM KMS (--vo=gpu --gpu-context=drm)                       |
| Subtitle: "Hang tight!"                                                     |
| Purpose:  Covers MMC mount, directory discovery, and in-RAM VFS copying.    |
+-----------------------------------------------------------------------------+
      |
      +---------------------------------+
      | Media Found                     | No Media Found
      v                                 v
+------------------------------------+  +-------------------------------------+
| State: Video Playback Loop         |  | State 3: "No media found!"          |
| Renderer: MPV (VC4 Gallium DRM)    |  | Renderer: MPV on DRM KMS (static)   |
| Audio: Silent / disabled           |  | Subtitle: "Please put content into  |
| LEDs: Stealth mode (all off)       |  |            media partition."        |
+------------------------------------+  | LEDs: Red PWR blinking (100ms)      |
      |                                 +-------------------------------------+
      | Media Replug / New Card Added                      |
      +----------------------------------------------------+
      |
      v
+-----------------------------------------------------------------------------+
| State 4: "Rebooting..." (hotplug event)                                     |
| Renderer: MPV DRM KMS + fbdraw fb0 fallback                                 |
| Subtitle: "This might take a few seconds."                                  |
| Purpose:  Instant acknowledgment of card insertion before clean reboot.     |
+-----------------------------------------------------------------------------+
```

### Visual State Specification

| State | Graphic File | Headline (Pure White `#FFFFFF`) | Subtitle (Light Gray `#A0A0A0`) | Primary Rendering Engine |
| :--- | :--- | :--- | :--- | :--- |
| **1. Early Boot** | [`assets/booting.png`](file:///home/sarp/rpi3-videokiosk/assets/booting.png) | `Booting up...` | *Hang tight!* | [`fbdraw`](file:///home/sarp/rpi3-videokiosk/alpine-kiosk/scripts/fbdraw.c) blitting [`splash.ppm`](file:///home/sarp/rpi3-videokiosk/alpine-kiosk/scripts/patch_initramfs.py#L62) to `/dev/fb0` |
| **2. Scanning** | [`assets/searching.png`](file:///home/sarp/rpi3-videokiosk/assets/searching.png) | `Searching media...` | *Hang tight!* | `mpv --vo=gpu --gpu-context=drm` |
| **3. Empty Alert** | [`assets/no-media.png`](file:///home/sarp/rpi3-videokiosk/assets/no-media.png) | `No media found!` | *Please put content into media partition.* | `mpv --vo=gpu --gpu-context=drm` |
| **4. Replug Event**| [`assets/rebooting.png`](file:///home/sarp/rpi3-videokiosk/assets/rebooting.png) | `Rebooting...` | *This might take a few seconds.* | `mpv --vo=gpu --gpu-context=drm` (backed by `fbdraw`) |

---

## 2. Freestanding Framebuffer Renderer (`fbdraw`)

During early initramfs boot, dynamic shared libraries (`libc.so`, `libdrm.so`, `libpng.so`) are unavailable, and userspace display compositors cannot run. Traditional tools like `fbi` or `plymouth` pull in extensive dependency trees and shared objects, bloating the initramfs by 15–30 MB.

To solve this, the kiosk implements **`fbdraw`** ([`alpine-kiosk/scripts/fbdraw.c`](file:///home/sarp/rpi3-videokiosk/alpine-kiosk/scripts/fbdraw.c)), an ultra-lean freestanding AArch64 C program.

### Key Characteristics of `fbdraw`
- **Zero Libc Dependencies:** Compiled with `-static -nostdlib -fno-stack-protector -O2`. Entry point is [`_start`](file:///home/sarp/rpi3-videokiosk/alpine-kiosk/scripts/fbdraw.c#L174) with direct raw Linux assembly system calls (`svc #0`).
- **Binary Footprint:** Stripped executable size is under **4.9 KB**.
- **Execution Speed:** Maps the framebuffer and blits a full 1080p frame in under **15 milliseconds**.
- **No TTY / Console Allocation:** Operates directly on the character device node (`/dev/fb0` or `/dev/fb/0`), eliminating dependencies on virtual terminals (`/dev/tty1`), VT switches, or terminal cursors.

### Linux Syscalls Implemented via Inline Assembly

```c
static inline int64_t sys_openat(int dirfd, const char *path, int flags, int mode); // Syscall 56
static inline int64_t sys_read(int fd, void *buf, uint64_t count);                 // Syscall 63
static inline int64_t sys_close(int fd);                                            // Syscall 57
static inline int64_t sys_ioctl(int fd, uint64_t req, void *arg);                   // Syscall 29
static inline void *sys_mmap(void *addr, uint64_t len, int prot, int flags, ...);   // Syscall 222
static inline void sys_exit(int code);                                              // Syscall 94
```

### Netpbm PPM Parser and Universal Pixel Blitter

`fbdraw` accepts images in uncompressed binary Netpbm PPM format (Magic: `P6`). It queries screen geometry and bitfield layout using the Linux Framebuffer API:
- [`FBIOGET_VSCREENINFO`](file:///home/sarp/rpi3-videokiosk/alpine-kiosk/scripts/fbdraw.c#L19) (`0x4600`): returns `xres`, `yres`, `bits_per_pixel`, and color bitfield offsets (`red.offset`, `green.offset`, `blue.offset`, `transp.offset`).
- [`FBIOGET_FSCREENINFO`](file:///home/sarp/rpi3-videokiosk/alpine-kiosk/scripts/fbdraw.c#L20) (`0x4602`): returns physical line pitch (`line_length`) and memory size (`smem_len`).

It dynamically maps color channels for both 32bpp and 16bpp layouts:
```c
// Dynamic 32bpp bitfield packing (handles RGBA, ARGB, BGRA transparently)
uint32_t alpha = (var.transp.length > 0) ? (0xFF << var.transp.offset) : (0xFF << 24);
dst[x] = (r << var.red.offset) | (g << var.green.offset) | (b << var.blue.offset) | alpha;
```
If the image dimensions differ from the display resolution, `fbdraw` centers the raster buffer automatically:
$$\text{start\_x} = \frac{\text{xres} - \text{draw\_w}}{2}, \quad \text{start\_y} = \frac{\text{yres} - \text{draw\_h}}{2}$$

---

## 3. Framebuffer-to-DRM KMS Modesetting Handoff

A critical design challenge on embedded Linux is avoiding display flickering or black frames when transitioning from the early firmware boot splash to hardware-accelerated userspace video playback.

```
Firmware (start.elf)
      |  (Creates HDMI simplefb / bcm2708_fb at 1920x1080)
      v
Alpine initramfs
      |  [fbdraw blits splash.ppm to /dev/fb0]
      |  (DRM modules vc4/v3d are pruned/blacklisted in initramfs)
      v
switch_root into tmpfs
      |
      v
OpenRC / kiosk-player.sh
      |  [modprobe vc4 v3d] -> VideoCore IV KMS registers /dev/dri/card0
      v
MPV Launch
      |  (--vo=gpu --gpu-context=drm)
      v
Hardware-Accelerated DRM KMS CRTC Plane Active
```

### Why DRM Modules Are Pruned from initramfs
In [`alpine-kiosk/scripts/patch_initramfs.py`](file:///home/sarp/rpi3-videokiosk/alpine-kiosk/scripts/patch_initramfs.py#L67-L102), all DRM drivers (`vc4`, `v3d`, `simpledrm`) are stripped from `initramfs-rpi` and blacklisted in `/etc/modprobe.d/blacklist.conf`. 

If `vc4` or `simpledrm` loads inside the initramfs:
1. The kernel DRM subsystem immediately unbinds the firmware framebuffer (`simplefb`), destroying the active scanout buffer.
2. The HDMI monitor loses sync, displaying a blue or black "No Signal" banner for 2 to 4 seconds while the kernel completes rootfs mount.
3. By deferring `modprobe vc4 v3d` to [`alpine-kiosk/overlay/usr/bin/kiosk-player.sh`](file:///home/sarp/rpi3-videokiosk/alpine-kiosk/overlay/usr/bin/kiosk-player.sh#L109), the firmware framebuffer retains the `"Booting up..."` splash image continuously on screen until userspace MPV acquires the DRM master and presents `"Searching media..."`.

### Direct DRM KMS Execution in MPV
Video playback and userspace splash screens run through MPV using direct Kernel Modesetting:
```ini
vo=gpu
gpu-context=drm
hwdec=auto-safe
```
This bypasses all window servers (X11, Wayland), blitting directly to the primary hardware DRM CRTC plane via the Mesa VideoCore IV Gallium driver (`vc4_dri.so`).

---

## 4. Typography & Visual Identity

All system graphics are generated through [`alpine-kiosk/scripts/generate-screens.py`](file:///home/sarp/rpi3-videokiosk/alpine-kiosk/scripts/generate-screens.py) using the official variable font [`assets/fonts/Inter-Variable.ttf`](file:///home/sarp/rpi3-videokiosk/assets/fonts/Inter-Variable.ttf).

### Typography Hierarchy (1920 $\times$ 1080 Canvas)

| Element | Font Weight | Size | Color | Position |
| :--- | :--- | :--- | :--- | :--- |
| **Headline Title** | Inter Bold (`700`) | `60 pt` | Pure White (`#FFFFFF`) | Horizontally centered, vertically grouped with subtitle |
| **Action Subtitle** | Inter Regular (`400`) | `30 pt` | Slate Gray (`#A0A0A0`) | Centered below title with `26 px` padding |
| **Brand Version Watermark** | Inter Medium (`500`) | `22 pt` | Emerald Green (`#34D399`) | Bottom-left corner (`x=70px`, `y=HEIGHT-88px`) |
| **Author Credit** | Inter Medium (`500`) | `17 pt` | Pure White (`#FFFFFF`) | Bottom-left corner (`x=70px`, `y=HEIGHT-55px`) |

### Version Watermark Specification
The brand watermark format is strictly defined:
```
Video Kiosk <VERSION> (<short-hash>)
by Sarp Eren EGILMEZ
```
- `<VERSION>` is read dynamically from the repository root [`VERSION`](file:///home/sarp/rpi3-videokiosk/VERSION) file.
- `<short-hash>` is derived from `git rev-parse --short HEAD`.
- The green accent (`#34D399`, RGB `52, 211, 153`) establishes an identifiable brand mark while maintaining commercial elegance against the `#000000` deep black field.
