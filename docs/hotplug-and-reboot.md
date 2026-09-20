# Media Hotplug & Automated Reboot Pipeline

## Overview

The Raspberry Pi 3 Video Kiosk is designed to operate without maintenance personnel needing a keyboard, mouse, network connection, or command-line interface. When content needs updating, a non-technical user simply removes the SD card, writes new files to the `videos/` folder on a PC or laptop, and re-inserts the card. Alternatively, a USB thumb drive containing a `videos/` folder can be plugged in directly.

The kiosk detects these events in real time, displays a user-facing `Rebooting...` splash screen, flashes the hardware LED indicator, and cleanly restarts to reload the media cache and playlist.

---

## 1. The Hardware Challenge: Lack of Card-Detect (CD) Pin

On standard full-sized SD slots and certain development boards, a mechanical card-detect switch grounds a dedicated GPIO pin when a card is inserted or removed. This raises a hardware interrupt in the kernel, triggering an instantaneous driver event.

However, the **Raspberry Pi 3 Model B (and 3B+) micro-SD slot has no mechanical card-detect switch connected to BCM2837 GPIOs**. 

### The Resulting Failure Mode Without Polling
1. At boot, the kernel detects the card during initial enumeration.
2. If the user unmounts the partition (as our in-RAM caching does to allow safe ejection), no further I/O occurs on the bus.
3. If the user removes the card, the kernel receives **no interrupt**.
4. The kernel retains `/dev/mmcblk0` and `/dev/mmcblk0p1` entries in `/proc/partitions` and `/sys/block/`.
5. When the card is re-inserted, the MMC controller is completely unaware that anything changed. No udev event is fired, and subsequent access attempts fail with timeouts or stale cache reads.

---

## 2. Dual-Layer Detection Strategy

To overcome the lack of hardware card detection while supporting USB flash drives, the kiosk implements a complementary two-tier strategy:

```
+-------------------------------------------------------------------------+
|                         Detection Layer                                 |
+------------------------------------+------------------------------------+
|            Tier 1: udev            |       Tier 2: Background Poller    |
|   (/etc/udev/rules.d/              |      (kiosk-player.sh subshell)    |
|    99-kiosk-replug.rules)          |                                    |
|                                    | - Probing read (dd bs=512 count=1) |
| - Instant USB insertion ('sd*1')   | - Kernel MMC bus rescan trigger    |
| - Kernel-notified MMC events       |   (/sys/class/mmc_host/*/rescan)   |
|                                    | - Detection of state transitions   |
+------------------------------------+------------------------------------+
                                     |
                                     v
                  +--------------------------------------+
                  |   Atomic Guard: /run/kiosk-rebooting |
                  |   - Prevents race conditions         |
                  |   - Suppresses loop restarts         |
                  +--------------------------------------+
                                     |
                                     v
                  +--------------------------------------+
                  |   Reboot Routine                     |
                  |   1. Flash Green ACT LED (50ms)      |
                  |   2. Terminate existing MPV          |
                  |   3. Show "Rebooting..." (DRM & FB)  |
                  |   4. sync && reboot                  |
                  +--------------------------------------+
```

---

## 3. Tier 1: Udev Block Device Rules

File: `/etc/udev/rules.d/99-kiosk-replug.rules`

```udev
ACTION=="add", SUBSYSTEM=="block", KERNEL=="mmcblk0p1", RUN+="/usr/bin/kiosk-replug-handler.sh mmcblk0p1"
ACTION=="add", SUBSYSTEM=="block", KERNEL=="sd[a-z]1", RUN+="/usr/bin/kiosk-replug-handler.sh %k"
```

- **USB Drives (`sd[a-z]1`)**: Handled instantly. When a USB stick is inserted, the USB PHY and SCSI subsystem immediately register the device and trigger the udev rule.
- **SD Card (`mmcblk0p1`)**: Handled when the kernel MMC layer recognizes the partition table after a bus rescan.

---

## 4. Tier 2: Background Polling & Bus Rescan

Because udev cannot fire if the MMC controller never scans the bus, a lightweight background loop runs in `kiosk-player.sh`:

```sh
start_replug_watcher() {
    (
        # Wait until kiosk is operational
        while [ ! -f /run/kiosk-ready ]; do
            sleep 1
        done
        sleep 3

        # Record initial SD presence via 512-byte test read
        was_sd_present=0
        if [ -b /dev/mmcblk0 ] && dd if=/dev/mmcblk0 of=/dev/null bs=512 count=1 >/dev/null 2>&1; then
            was_sd_present=1
        fi

        while true; do
            sleep 1
            [ -f /run/kiosk-rebooting ] && exit 0

            # 1. USB Storage Check
            if grep -qE "sd[a-z][0-9]" /proc/partitions 2>/dev/null; then
                trigger_reboot "USB media drive detected"
            fi

            # 2. SD Card Presence Check
            if [ "$was_sd_present" -eq 1 ]; then
                # Card was present: test if still readable
                if ! dd if=/dev/mmcblk0 of=/dev/null bs=512 count=1 >/dev/null 2>&1; then
                    echo "[kiosk-replug] SD card removal detected." >&2
                    was_sd_present=0
                fi
            else
                # Card is absent: trigger host controller rescan
                for rescan in /sys/class/mmc_host/*/rescan; do
                    [ -f "$rescan" ] && echo 1 > "$rescan" 2>/dev/null
                done
                # Check if card has returned
                if [ -b /dev/mmcblk0 ] && dd if=/dev/mmcblk0 of=/dev/null bs=512 count=1 >/dev/null 2>&1; then
                    trigger_reboot "SD card re-inserted"
                fi
            fi
        done
    ) > /dev/null 2>&1 &
}
```

### Why a 512-byte `dd` read?
Checking for device node existence (`[ -b /dev/mmcblk0 ]`) or checking `/proc/partitions` is insufficient because the kernel retains these nodes until an I/O request fails. Attempting to read sector 0 via `dd bs=512 count=1` forces an actual bus transaction:
- If the card is present: the read succeeds in `< 1ms`.
- If the card was removed: the MMC command times out, notifying the driver that the card is gone.

---

## 5. Clean Reboot Sequence

When either trigger detects a media event, `trigger_reboot` executes:

1. **Atomic Guard:** Tests and creates `/run/kiosk-rebooting`. Any concurrent event (e.g., udev handler firing at the same time as the poller) is immediately dropped.
2. **Visual Feedback (LED):** Switches Green ACT LED to 50ms pulse rate (`delay_on=50`, `delay_off=50`), signaling to the user that the insertion was recognized.
3. **Display Transition:**
   - Kills existing MPV player instance (`killall -9 mpv`).
   - Launches a fresh MPV instance on DRM KMS showing `rebooting.png`.
   - Concurrently writes `rebooting.ppm` to `/dev/fb0` using `fbdraw` for complete redundancy.
4. **Safety Delay:** Pauses for 3 seconds so the user clearly sees the `"Rebooting... This might take a few seconds."` screen.
5. **Reboot Execution:** Calls `sync` and `/sbin/reboot`.
