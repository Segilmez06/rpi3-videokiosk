#!/usr/bin/env bash
#
# kiosk-player.sh - Continuous, seamless headless video player for Raspberry Pi 3
# Plays all videos in /media/videos in alphabetical order in an endless loop.
#

MEDIA_DIR="/media/videos"
CONFIG_DIR="/etc/mpv"
FALLBACK_IMG="/usr/local/share/kiosk/no-media.png"

# Ensure cursor is hidden and screen is blanked
setterm -cursor off > /dev/tty1 2>/dev/null || true
clear > /dev/tty1 2>/dev/null || true

# Ensure all LEDs are OFF during presentation — no status indicators
for dir in /sys/class/leds/*; do
    if [ -d "$dir" ]; then
        [ -w "$dir/trigger" ] && echo none > "$dir/trigger" 2>/dev/null || true
        [ -w "$dir/brightness" ] && echo 0 > "$dir/brightness" 2>/dev/null || true
    fi
done

# Wait for media directory to be available
while [ ! -d "$MEDIA_DIR" ]; do
    sleep 0.1
done

while true; do
    # Find all supported video files in alphabetical order (natural sort)
    mapfile -t VIDEOS < <(find "$MEDIA_DIR" -maxdepth 1 -type f \( \
        -iname "*.mp4" -o \
        -iname "*.m4v" -o \
        -iname "*.mkv" -o \
        -iname "*.avi" -o \
        -iname "*.mov" -o \
        -iname "*.webm" -o \
        -iname "*.ts" \
    \) 2>/dev/null | sort -V)

    # If no videos found, display the fallback image
    if [ ${#VIDEOS[@]} -eq 0 ]; then
        if [ -f "$FALLBACK_IMG" ]; then
            mpv \
                --config-dir="$CONFIG_DIR" \
                --vo=gpu \
                --gpu-context=drm \
                --no-audio \
                --image-display-duration=4 \
                --no-terminal \
                --cursor-autohide=always \
                --term-playing-msg="" \
                --msg-level=all=no \
                "$FALLBACK_IMG" >/dev/null 2>&1
        else
            setterm -cursor off > /dev/tty1 2>/dev/null || true
            clear > /dev/tty1 2>/dev/null || true
            sleep 4
        fi
        continue
    fi

    # Launch mpv — all tuning (hwdec, cache, sync) comes from /etc/mpv/mpv.conf
    mpv \
        --config-dir="$CONFIG_DIR" \
        --no-terminal \
        "${VIDEOS[@]}" >/dev/null 2>&1

    # Brief delay if mpv exits before restarting the scan loop
    sleep 1
done
