#!/bin/sh
# Raspberry Pi 3 Video Kiosk Playback Engine
# Seamless Multi-Video Playlist Support with Smart In-RAM VFS Caching
# Hardware Acceleration: DRM KMS + V4L2 M2M Video Decode (VC4 Gallium)
# Visual Feedback: 1080p No-Media Graphic & Diagnostic Blink when empty

export HOME=/root
export XDG_RUNTIME_DIR=/run/user/0
mkdir -p "$XDG_RUNTIME_DIR" 2>/dev/null
chmod 700 "$XDG_RUNTIME_DIR" 2>/dev/null

RAM_VIDEOS_DIR="/run/kiosk-videos"
PLAYLIST_FILE="/run/kiosk-playlist.txt"
NO_MEDIA_IMG="/usr/share/videokiosk/no-media.png"
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

# Locate the active media directory containing video files
locate_source_dir() {
    # 1. Check standard SD card path
    if [ -d "/media/mmcblk0p1/videos" ]; then
        if [ -n "$(find /media/mmcblk0p1/videos -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.webm" -o -iname "*.ts" \) 2>/dev/null)" ]; then
            echo "/media/mmcblk0p1/videos"
            return 0
        fi
    fi

    # 2. Check root videos path if mounted
    if [ -d "/videos" ]; then
        if [ -n "$(find /videos -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.webm" -o -iname "*.ts" \) 2>/dev/null)" ]; then
            echo "/videos"
            return 0
        fi
    fi

    # 3. Check any USB drives mounted under /media
    for dir in /media/*; do
        if [ -d "$dir/videos" ] && [ "$dir" != "/media/mmcblk0p1" ]; then
            if [ -n "$(find "$dir/videos" -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.webm" -o -iname "*.ts" \) 2>/dev/null)" ]; then
                echo "$dir/videos"
                return 0
            fi
        fi
    done

    # 4. Fallback: check if demo sample exists in /usr/share/videokiosk
    if [ -f "/usr/share/videokiosk/sample.mp4" ]; then
        echo "/usr/share/videokiosk"
        return 0
    fi

    return 1
}

# Generate playlist and handle RAM caching for multiple video files
prepare_playlist() {
    # 1. If RAM cache already exists and has videos, use it directly
    if [ -d "$RAM_VIDEOS_DIR" ] && [ -n "$(find "$RAM_VIDEOS_DIR" -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.webm" -o -iname "*.ts" \) 2>/dev/null)" ]; then
        find "$RAM_VIDEOS_DIR" -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.webm" -o -iname "*.ts" \) | sort > "$PLAYLIST_FILE"
        return 0
    fi

    # 2. Locate source folder
    SRC_DIR=$(locate_source_dir)
    if [ -z "$SRC_DIR" ]; then
        rm -f "$PLAYLIST_FILE"
        return 1
    fi

    # Count total video files in source directory
    VIDEO_COUNT=$(find "$SRC_DIR" -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.webm" -o -iname "*.ts" \) 2>/dev/null | wc -l)
    echo "[kiosk-player] Discovered $VIDEO_COUNT video file(s) in $SRC_DIR" >&2

    # 3. Calculate total size of all videos in the source directory
    TOTAL_KB=$(du -sk "$SRC_DIR" 2>/dev/null | awk '{print $1}')
    TOTAL_KB=${TOTAL_KB:-999999}
    TOTAL_MB=$((TOTAL_KB / 1024))

    # 4. If small enough and not internal fallback, copy all files to RAM
    if [ "$TOTAL_KB" -le "$MAX_RAM_CACHE_KB" ] && [ "$SRC_DIR" != "/usr/share/videokiosk" ]; then
        echo "[kiosk-player] Total video payload (${TOTAL_MB} MB, ${VIDEO_COUNT} files) fits in RAM. Copying to tmpfs RAM..." >&2
        mkdir -p "$RAM_VIDEOS_DIR"

        # Copy each video file safely preserving full filenames with spaces
        find "$SRC_DIR" -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.webm" -o -iname "*.ts" \) -exec cp -p {} "$RAM_VIDEOS_DIR/" \;

        # Unmount SD card to allow physical hot-ejection
        if [ "$SRC_DIR" = "/media/mmcblk0p1/videos" ]; then
            echo "[kiosk-player] In-RAM cache complete. Unmounting SD card (safe for physical hot-eject)..." >&2
            sync
            umount /media/mmcblk0p1 2>/dev/null || true
        fi

        find "$RAM_VIDEOS_DIR" -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.webm" -o -iname "*.ts" \) | sort > "$PLAYLIST_FILE"
    else
        echo "[kiosk-player] Video payload (${TOTAL_MB} MB) exceeds RAM limit (450 MB) or is bundled demo. Streaming from disk." >&2
        find "$SRC_DIR" -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.webm" -o -iname "*.ts" \) | sort > "$PLAYLIST_FILE"
    fi

    [ -s "$PLAYLIST_FILE" ]
}

# Main infinite playback supervisor loop
while true; do
    if prepare_playlist; then
        VIDEO_COUNT=$(wc -l < "$PLAYLIST_FILE")
        echo "[kiosk-player] Starting MPV with $VIDEO_COUNT video(s) in seamless playlist loop..." >&2

        # Video playback starting -> Turn Green ACT LED completely OFF (stealth playback)
        for act in /sys/class/leds/ACT /sys/class/leds/led0 /sys/class/leds/*act*; do
            if [ -d "$act" ]; then
                echo none > "$act/trigger" 2>/dev/null || true
                echo 0 > "$act/brightness" 2>/dev/null || true
            fi
        done

        # Launch MPV with seamless playlist looping and prefetching
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
            --playlist="$PLAYLIST_FILE"
        
        echo "[kiosk-player] MPV exited with code $?, restarting playlist in 1s..." >&2
        # Restore Green LED ON while recovering/reloading
        for act in /sys/class/leds/ACT /sys/class/leds/led0 /sys/class/leds/*act*; do
            [ -d "$act" ] && echo 1 > "$act/brightness" 2>/dev/null || true
        done
    else
        echo "[kiosk-player] No video files found. Displaying no-media screen & blinking LED..." >&2
        # Diagnostic alert: blink Green ACT LED fast (250ms) to indicate waiting for media
        for act in /sys/class/leds/ACT /sys/class/leds/led0 /sys/class/leds/*act*; do
            if [ -d "$act" ]; then
                echo timer > "$act/trigger" 2>/dev/null || true
                echo 250 > "$act/delay_on" 2>/dev/null || true
                echo 250 > "$act/delay_off" 2>/dev/null || true
            fi
        done

        # Display full-screen 1080p No-Media graphic for 3 seconds, then re-check
        if [ -f "$NO_MEDIA_IMG" ]; then
            /usr/bin/mpv \
                --config-dir=/etc/mpv \
                --vo=gpu \
                --gpu-context=drm \
                --drm-connector=HDMI-A-1 \
                --image-display-duration=3 \
                --loop-file=1 \
                --really-quiet \
                --terminal=no \
                "$NO_MEDIA_IMG" 2>/dev/null || sleep 2
        else
            sleep 2
        fi
    fi

    sleep 1
done
