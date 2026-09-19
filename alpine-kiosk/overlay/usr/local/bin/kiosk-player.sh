#!/bin/sh
# Raspberry Pi 3 Video Kiosk Playback Engine
# Runs MPV with DRM KMS direct output and V4L2 M2M hardware acceleration
# Supports Smart In-RAM VFS caching (allows physically ejecting the SD card!)

export HOME=/root
export XDG_RUNTIME_DIR=/run/user/0
mkdir -p "$XDG_RUNTIME_DIR" 2>/dev/null
chmod 700 "$XDG_RUNTIME_DIR" 2>/dev/null

RAM_VIDEOS_DIR="/run/kiosk-videos"
MAX_RAM_CACHE_KB=460800  # 450 MB safe RAM threshold (leaves ~400MB free for MPV & kernel)

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

# Discover videos on physical storage (SD card, USB, or bundled fallback)
find_source_videos() {
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

# Smart In-RAM VFS caching: Copies videos to tmpfs RAM and unmounts SD card
setup_playback_media() {
    # 1. Check if already cached in RAM
    if [ -d "$RAM_VIDEOS_DIR" ]; then
        cached_videos=$(find "$RAM_VIDEOS_DIR" -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.webm" -o -iname "*.ts" \) | sort)
        if [ -n "$cached_videos" ]; then
            echo "$cached_videos"
            return 0
        fi
    fi

    # 2. Discover videos on physical storage
    SRC_VIDEOS=$(find_source_videos)
    [ -z "$SRC_VIDEOS" ] && return 1

    # 3. Calculate total payload size
    # shellcheck disable=SC2086
    total_kb=$(du -ck $SRC_VIDEOS 2>/dev/null | awk '/total$/ {print $1}')
    total_kb=${total_kb:-999999}
    total_mb=$((total_kb / 1024))

    # 4. If small enough, copy to RAM and unmount SD card
    if [ "$total_kb" -le "$MAX_RAM_CACHE_KB" ]; then
        echo "[kiosk-player] Videos size (${total_mb} MB) fits in RAM. Caching to tmpfs RAM..." >&2
        mkdir -p "$RAM_VIDEOS_DIR"
        # shellcheck disable=SC2086
        cp -u $SRC_VIDEOS "$RAM_VIDEOS_DIR/"

        echo "[kiosk-player] In-RAM cache complete. Unmounting SD card (safe for physical hot-eject)..." >&2
        sync
        umount /media/mmcblk0p1 2>/dev/null || true

        cached_videos=$(find "$RAM_VIDEOS_DIR" -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.webm" -o -iname "*.ts" \) | sort)
        echo "$cached_videos"
        return 0
    else
        echo "[kiosk-player] Videos size (${total_mb} MB) exceeds RAM limit (450 MB). Streaming directly from storage." >&2
        echo "$SRC_VIDEOS"
        return 0
    fi
}

# Main infinite playback supervisor loop
while true; do
    PLAY_VIDEOS=$(setup_playback_media)

    if [ -n "$PLAY_VIDEOS" ]; then
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
            $PLAY_VIDEOS
        
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
