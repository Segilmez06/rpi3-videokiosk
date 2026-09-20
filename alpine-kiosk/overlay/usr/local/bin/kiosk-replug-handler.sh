#!/bin/sh
# Kiosk Media Replug Handler
# Automatically triggers a clean reboot when an SD card or USB drive is inserted with new media

# 1. Guard against boot storm: only act after kiosk is fully initialized
[ -f /run/kiosk-ready ] || exit 0

# 2. Guard against initial boot: system uptime must be >= 15 seconds
UPTIME=$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo 0)
[ "$UPTIME" -ge 15 ] || exit 0

# 3. Guard against debounce / multiple contact bounce events
[ -f /run/kiosk-rebooting ] && exit 0
touch /run/kiosk-rebooting

# 4. Immediate visual acknowledgment: Flash Green ACT LED rapidly (50ms)
echo timer > /sys/class/leds/ACT/trigger 2>/dev/null || true
echo 50 > /sys/class/leds/ACT/delay_on 2>/dev/null || true
echo 50 > /sys/class/leds/ACT/delay_off 2>/dev/null || true
echo none > /sys/class/leds/PWR/trigger 2>/dev/null || true
echo 0 > /sys/class/leds/PWR/brightness 2>/dev/null || true

echo "[kiosk-replug] Media device '$1' connected. Clean rebooting in 2s to load new content..." > /dev/kmsg 2>/dev/null
echo "[kiosk-replug] Media device '$1' connected. Rebooting in 2s..." >&2

# 5. Display reboot screen immediately
killall -9 mpv 2>/dev/null || true
if [ -x /usr/bin/fbdraw ] && [ -f /usr/share/videokiosk/rebooting.ppm ] && [ -e /dev/fb0 ]; then
    /usr/bin/fbdraw /usr/share/videokiosk/rebooting.ppm /dev/fb0 2>/dev/null || true
fi

sleep 2
sync
reboot
