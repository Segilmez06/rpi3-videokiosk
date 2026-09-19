#!/usr/bin/env bash
#
# kiosk-player.sh - Continuous, seamless headless video player for Raspberry Pi 3
# Plays all videos in /media/videos in alphabetical order in an endless loop.
#

MEDIA_DIR="/media/videos"
CONFIG_DIR="/etc/mpv"

# Ensure cursor is hidden and screen is blanked
setterm -cursor off > /dev/tty1 2>/dev/null || true
clear > /dev/tty1 2>/dev/null || true

# Wait for media directory to be available
while [ ! -d "$MEDIA_DIR" ]; do
    sleep 2
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

    # If no videos found, wait silently without consuming CPU
    if [ ${#VIDEOS[@]} -eq 0 ]; then
        # Keep screen blank
        setterm -cursor off > /dev/tty1 2>/dev/null || true
        clear > /dev/tty1 2>/dev/null || true
        sleep 4
        continue
    fi

    # Launch mpv with Direct Rendering Manager (DRM/KMS) hardware output
    # All display configuration is loaded from /etc/mpv/mpv.conf
    mpv \
        --config-dir="$CONFIG_DIR" \
        --vo=gpu \
        --gpu-context=drm \
        --hwdec=auto-safe \
        --no-audio \
        --loop-playlist=inf \
        --no-terminal \
        --cursor-autohide=always \
        --term-playing-msg="" \
        --msg-level=all=no \
        "${VIDEOS[@]}" >/dev/null 2>&1

    # Brief delay if mpv exits before restarting the scan loop
    sleep 1
done
