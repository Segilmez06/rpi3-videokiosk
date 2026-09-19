#!/bin/sh
# Raspberry Pi 3 Video Kiosk Playback Engine
# Runs MPV with DRM KMS direct output and V4L2 M2M hardware acceleration

export HOME=/root
export XDG_RUNTIME_DIR=/run/user/0
mkdir -p "$XDG_RUNTIME_DIR" 2>/dev/null
chmod 700 "$XDG_RUNTIME_DIR" 2>/dev/null

# Turn off all on-board LEDs (stealth mode)
for led in /sys/class/leds/*; do
    [ -e "$led/brightness" ] && echo 0 > "$led/brightness" 2>/dev/null || true
done

# Wait for DRM KMS device node (/dev/dri/card0)
count=0
while [ ! -e /dev/dri/card0 ] && [ $count -lt 50 ]; do
    sleep 0.1
    count=$((count + 1))
done

# Function to find video files
find_videos() {
    # Check standard SD card path
    if [ -d "/media/mmcblk0p1/videos" ]; then
        videos=$(find /media/mmcblk0p1/videos -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.webm" -o -iname "*.ts" \) | sort)
        if [ -n "$videos" ]; then
            echo "$videos"
            return 0
        fi
    fi

    # Check root videos path if mounted
    if [ -d "/videos" ]; then
        videos=$(find /videos -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.webm" -o -iname "*.ts" \) | sort)
        if [ -n "$videos" ]; then
            echo "$videos"
            return 0
        fi
    fi

    # Check any USB drives mounted under /media
    for dir in /media/*; do
        if [ -d "$dir/videos" ] && [ "$dir" != "/media/mmcblk0p1" ]; then
            videos=$(find "$dir/videos" -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.webm" -o -iname "*.ts" \) | sort)
            if [ -n "$videos" ]; then
                echo "$videos"
                return 0
            fi
        fi
    done

    # Fallback to bundled demo asset
    if [ -f "/usr/share/videokiosk/sample.mp4" ]; then
        echo "/usr/share/videokiosk/sample.mp4"
        return 0
    fi

    return 1
}

# Main infinite playback supervisor loop
while true; do
    VIDEOS=$(find_videos)

    if [ -n "$VIDEOS" ]; then
        echo "[kiosk-player] Starting MPV playback loop..." >&2
        # Turn off LEDs again in case kernel re-enabled them
        for led in /sys/class/leds/*; do
            [ -e "$led/brightness" ] && echo 0 > "$led/brightness" 2>/dev/null || true
        done

        # shellcheck disable=SC2086
        /usr/bin/mpv \
            --config-dir=/etc/mpv \
            --vo=gpu \
            --gpu-context=drm \
            --drm-connector=HDMI-A-1 \
            --hwdec=v4l2m2m-copy,auto-safe \
            --loop-playlist=inf \
            --no-audio \
            --really-quiet \
            --terminal=no \
            --cursor-autohide=always \
            --prefetch-playlist=yes \
            $VIDEOS
        
        echo "[kiosk-player] MPV exited with code $?, restarting in 1s..." >&2
    else
        echo "[kiosk-player] No video files found. Checking again in 3s..." >&2
    fi

    sleep 1
done
