# Terminal settings for physical serial console
export TERM=xterm-256color

# Uncap 80-column restriction and autodetect terminal size
if [ -t 0 ]; then
    stty rows 40 cols 120 2>/dev/null || true
    # Try dynamic query if supported
    resize 2>/dev/null || true
fi

# Video Kiosk Serial Banner
echo ""
echo "============================================================"
echo "    Raspberry Pi 3 Video Kiosk Appliance (Alpine Linux)"
echo "    Architecture: aarch64 (Diskless / Run-from-RAM)"
echo "============================================================"
echo "  * Rootfs:      tmpfs (RAM) - 100% immune to sudden power cuts"
echo "  * Storage:     /media/mmcblk0p1/videos (FAT32)"
echo "  * Output:      DRM KMS + V4L2 M2M hardware video decode"
echo "  * Console:     /dev/ttyAMA0 @ 115200 8N1"
echo "============================================================"
echo "  Management commands:"
echo "    kiosk-player restart  - Restart MPV playback loop"
echo "    kiosk-player status   - Show kiosk player status & PID"
echo "    kiosk-led status      - Inspect current LED state"
echo "    kiosk-led green on    - Turn Green ACT LED on (or off/blink/heartbeat)"
echo "    kiosk-led red on      - Turn Red PWR LED on (or off/heartbeat)"
echo "    poweroff / reboot     - Safe system shutdown / reboot"
echo "============================================================"
echo ""
