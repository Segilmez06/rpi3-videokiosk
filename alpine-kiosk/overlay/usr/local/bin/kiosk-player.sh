#!/bin/sh
# Raspberry Pi 3 Video Kiosk Playback Engine
# Runs MPV with DRM KMS direct output and V4L2 M2M hardware acceleration

export HOME=/root
export XDG_RUNTIME_DIR=/run/user/0
mkdir -p "$XDG_RUNTIME_DIR" 2>/dev/null
chmod 700 "$XDG_RUNTIME_DIR" 2>/dev/null

# Ensure Red PWR LED is completely disabled
for pwr in /sys/class/leds/PWR /sys/class/leds/led1 /sys/class/leds/*pwr*; do
    if [ -d "$pwr" ]; then
        echo none > "$pwr/trigger" 2>/dev/null || true
        echo 0 > "$pwr/brightness" 2>/dev/null || true
    fi
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

        # Video starting -> Turn Green ACT LED completely OFF (stealth playback)
        for act in /sys/class/leds/ACT /sys/class/leds/led0 /sys/class/leds/*act*; do
            if [ -d "$act" ]; then
                echo none > "$act/trigger" 2>/dev/null || true
                echo 0 > "$act/brightness" 2>/dev/null || true
            fi
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
        # Restore Green LED ON while recovering/reloading
        for act in /sys/class/leds/ACT /sys/class/leds/led0 /sys/class/leds/*act*; do
            [ -d "$act" ] && echo 1 > "$act/brightness" 2>/dev/null || true
        done
    else
        echo "[kiosk-player] No video files found. Checking again in 3s..." >&2
        # Diagnostic alert: blink Green ACT LED fast to indicate waiting for media
        for act in /sys/class/leds/ACT /sys/class/leds/led0 /sys/class/leds/*act*; do
            if [ -d "$act" ]; then
                echo timer > "$act/trigger" 2>/dev/null || true
                echo 250 > "$act/delay_on" 2>/dev/null || true
                echo 250 > "$act/delay_off" 2>/dev/null || true
            fi
        done
    fi

    sleep 1
done
