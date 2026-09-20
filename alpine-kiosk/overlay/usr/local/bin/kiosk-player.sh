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
BOOT_IMG="/usr/share/videokiosk/booting.png"
MAX_RAM_CACHE_KB=460800  # 450 MB safe RAM threshold (leaves ~400MB free for MPV & kernel)

# Read display orientation from configuration file (defaults to 0 / landscape)
read_orientation() {
    ROT=0
    # 1. Check if already cached in RAM
    if [ -f /run/kiosk-orientation ]; then
        ROT=$(cat /run/kiosk-orientation 2>/dev/null)
    fi

    # 2. Check storage locations for orientation.txt
    for f in /media/mmcblk0p1/orientation.txt /media/*/orientation.txt /videos/orientation.txt /orientation.txt /etc/videokiosk/orientation.txt; do
        if [ -f "$f" ]; then
            val=$(grep -v '^[[:space:]]*#' "$f" 2>/dev/null | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
            case "$val" in
                90|portrait|right)
                    ROT=90
                    ;;
                180|inverted|flip|upside-down)
                    ROT=180
                    ;;
                270|portrait-inverted|left)
                    ROT=270
                    ;;
                0|landscape|normal|*)
                    ROT=0
                    ;;
            esac
            echo "$ROT" > /run/kiosk-orientation 2>/dev/null
            break
        fi
    done

    ROT=${ROT:-0}
    echo "$ROT"
}

# Locate boot splash image (custom SD card splash takes precedence)
find_boot_splash() {
    for img in /media/mmcblk0p1/splash.png /media/mmcblk0p1/boot.png /videos/splash.png "$BOOT_IMG"; do
        [ -f "$img" ] && echo "$img" && return 0
    done
    return 1
}

# Display boot splash screen on HDMI persistently
present_boot_splash() {
    SPLASH=$(find_boot_splash)
    ROT=$(read_orientation)
    if [ -n "$SPLASH" ] && [ -e /dev/dri/card0 ]; then
        echo "[kiosk-player] Presenting boot splash for 4s ($SPLASH, rotate=$ROT deg)..." >&2
        /usr/bin/mpv \
            --no-config \
            --vo=gpu \
            --gpu-context=drm \
            --video-rotate="$ROT" \
            --image-display-duration=4 \
            "$SPLASH" > /run/kiosk-mpv.log 2>&1
    elif [ -x /usr/bin/fbdraw ] && [ -e /dev/fb0 ]; then
        for img in /media/mmcblk0p1/splash.ppm /usr/share/videokiosk/booting.ppm; do
            if [ -f "$img" ]; then
                /usr/bin/fbdraw "$img" /dev/fb0 2>/dev/null || true
                sleep 4
                break
            fi
        done
    fi
}

# Video Kiosk Initial State: Red PWR is OFF, Green ACT starts SOLID ON
for pwr in /sys/class/leds/PWR /sys/class/leds/led1 /sys/class/leds/*pwr*; do
    if [ -d "$pwr" ]; then
        echo none > "$pwr/trigger" 2>/dev/null || true
        echo 0 > "$pwr/brightness" 2>/dev/null || true
    fi
done
for act in /sys/class/leds/ACT /sys/class/leds/led0 /sys/class/leds/*act*; do
    if [ -d "$act" ]; then
        echo none > "$act/trigger" 2>/dev/null || true
        echo 1 > "$act/brightness" 2>/dev/null || true
    fi
done

# Wait for DRM KMS device node (/dev/dri/card0)
count=0
while [ ! -e /dev/dri/card0 ] && [ $count -lt 50 ]; do
    sleep 0.1
    count=$((count + 1))
done

# Present boot splash screen persistently so it is clearly readable on startup
present_boot_splash

# Background SD & USB replug watcher: detects card re-insertion or USB drive insertion and triggers reboot
start_replug_watcher() {
    (
        # Wait until kiosk has completed initial startup
        while [ ! -f /run/kiosk-ready ]; do
            sleep 1
        done
        sleep 5

        # Check whether SD card was present initially
        was_sd_present=0
        if grep -q "mmcblk0" /proc/partitions 2>/dev/null; then
            was_sd_present=1
        fi

        while true; do
            sleep 1

            # 1. Detect USB thumb drive insertion
            if grep -qE "sd[a-z][0-9]" /proc/partitions 2>/dev/null; then
                if [ ! -f /run/kiosk-rebooting ]; then
                    touch /run/kiosk-rebooting
                    echo "[kiosk-replug] USB media drive detected! Clean reboot in 2s to load new content..." >&2
                    echo timer > /sys/class/leds/ACT/trigger 2>/dev/null || true
                    echo 50 > /sys/class/leds/ACT/delay_on 2>/dev/null || true
                    echo 50 > /sys/class/leds/ACT/delay_off 2>/dev/null || true
                    echo none > /sys/class/leds/PWR/trigger 2>/dev/null || true
                    echo 0 > /sys/class/leds/PWR/brightness 2>/dev/null || true
                    sleep 2
                    sync
                    reboot
                fi
            fi

            # 2. Detect SD card re-insertion
            if grep -q "mmcblk0" /proc/partitions 2>/dev/null; then
                if [ "$was_sd_present" -eq 0 ]; then
                    if [ ! -f /run/kiosk-rebooting ]; then
                        touch /run/kiosk-rebooting
                        echo "[kiosk-replug] SD card re-inserted! Clean reboot in 2s to load new content..." >&2
                        echo timer > /sys/class/leds/ACT/trigger 2>/dev/null || true
                        echo 50 > /sys/class/leds/ACT/delay_on 2>/dev/null || true
                        echo 50 > /sys/class/leds/ACT/delay_off 2>/dev/null || true
                        echo none > /sys/class/leds/PWR/trigger 2>/dev/null || true
                        echo 0 > /sys/class/leds/PWR/brightness 2>/dev/null || true
                        sleep 2
                        sync
                        reboot
                    fi
                fi
                was_sd_present=1
            else
                # SD card physically removed
                was_sd_present=0
            fi
        done
    ) > /dev/null 2>&1 &
}
start_replug_watcher

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

    # 4. If small enough, copy all files to RAM
    if [ "$TOTAL_KB" -le "$MAX_RAM_CACHE_KB" ]; then
        echo "[kiosk-player] Total video payload (${TOTAL_MB} MB, ${VIDEO_COUNT} files) fits in RAM. Copying to tmpfs RAM..." >&2
        mkdir -p "$RAM_VIDEOS_DIR"

        # Green ACT blinking 100ms delay while copying media to RAM; Red PWR OFF
        for act in /sys/class/leds/ACT /sys/class/leds/led0 /sys/class/leds/*act*; do
            if [ -d "$act" ]; then
                echo timer > "$act/trigger" 2>/dev/null || true
                echo 100 > "$act/delay_on" 2>/dev/null || true
                echo 100 > "$act/delay_off" 2>/dev/null || true
            fi
        done
        for pwr in /sys/class/leds/PWR /sys/class/leds/led1 /sys/class/leds/*pwr*; do
            if [ -d "$pwr" ]; then
                echo none > "$pwr/trigger" 2>/dev/null || true
                echo 0 > "$pwr/brightness" 2>/dev/null || true
            fi
        done

        # Copy each video file safely preserving full filenames with spaces
        find "$SRC_DIR" -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.webm" -o -iname "*.ts" \) -exec cp -p {} "$RAM_VIDEOS_DIR/" \;

        # After copying done: Green returns to stable SOLID ON, Red remains OFF
        for act in /sys/class/leds/ACT /sys/class/leds/led0 /sys/class/leds/*act*; do
            if [ -d "$act" ]; then
                echo none > "$act/trigger" 2>/dev/null || true
                echo 1 > "$act/brightness" 2>/dev/null || true
            fi
        done

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


        # Signal that kiosk is fully ready for media replug events
        touch /run/kiosk-ready

        # Video playback starting -> CLOSE ALL LEDS (stealth digital signage playback)
        for led in /sys/class/leds/ACT /sys/class/leds/led0 /sys/class/leds/*act* /sys/class/leds/PWR /sys/class/leds/led1 /sys/class/leds/*pwr*; do
            if [ -d "$led" ]; then
                echo none > "$led/trigger" 2>/dev/null || true
                echo 0 > "$led/brightness" 2>/dev/null || true
            fi
        done

        # Read display orientation (0, 90, 180, 270)
        ROTATION=$(read_orientation)
        echo "[kiosk-player] Display orientation: ${ROTATION} deg" >&2

        # Launch MPV with seamless playlist looping and prefetching
        /usr/bin/mpv \
            --no-config \
            --vo=gpu \
            --gpu-context=drm \
            --video-rotate="$ROTATION" \
            --loop-playlist=inf \
            --no-audio \
            --cursor-autohide=always \
            --prefetch-playlist=yes \
            --playlist="$PLAYLIST_FILE" \
            > /run/kiosk-mpv.log 2>&1
        
        echo "[kiosk-player] MPV exited with code $?, restarting playlist in 1s..." >&2
        # Restore Green LED STABLE (SOLID ON) while recovering/reloading, Red OFF
        for act in /sys/class/leds/ACT /sys/class/leds/led0 /sys/class/leds/*act*; do
            [ -d "$act" ] && echo none > "$act/trigger" 2>/dev/null && echo 1 > "$act/brightness" 2>/dev/null || true
        done
        for pwr in /sys/class/leds/PWR /sys/class/leds/led1 /sys/class/leds/*pwr*; do
            [ -d "$pwr" ] && echo none > "$pwr/trigger" 2>/dev/null && echo 0 > "$pwr/brightness" 2>/dev/null || true
        done
    else
        echo "[kiosk-player] No video files found. Displaying no-media screen & blinking Red LED (100ms)..." >&2

        # Signal that kiosk is fully ready for media replug events
        touch /run/kiosk-ready

        # Attention / Error alert: Blink Red PWR LED 100ms, Green ACT is OFF
        for pwr in /sys/class/leds/PWR /sys/class/leds/led1 /sys/class/leds/*pwr*; do
            if [ -d "$pwr" ]; then
                echo timer > "$pwr/trigger" 2>/dev/null || true
                echo 100 > "$pwr/delay_on" 2>/dev/null || true
                echo 100 > "$pwr/delay_off" 2>/dev/null || true
            fi
        done
        for act in /sys/class/leds/ACT /sys/class/leds/led0 /sys/class/leds/*act*; do
            if [ -d "$act" ]; then
                echo none > "$act/trigger" 2>/dev/null || true
                echo 0 > "$act/brightness" 2>/dev/null || true
            fi
        done

        # Signal that kiosk is fully ready for media replug events
        touch /run/kiosk-ready

        # Display full-screen 1080p No-Media graphic SOLID (no flashing!) until media is discovered
        if [ -f "$NO_MEDIA_IMG" ]; then
            ROTATION=$(read_orientation)
            /usr/bin/mpv \
                --no-config \
                --vo=gpu \
                --gpu-context=drm \
                --video-rotate="$ROTATION" \
                --image-display-duration=inf \
                --loop-file=inf \
                "$NO_MEDIA_IMG" > /run/kiosk-mpv.log 2>&1 &
            NO_MEDIA_PID=$!

            # Stay on the static graphic until media files are found
            while [ -z "$(locate_source_dir)" ]; do
                sleep 2
            done

            # Media discovered! Cleanly terminate the static graphic
            if kill -0 "$NO_MEDIA_PID" 2>/dev/null; then
                kill -TERM "$NO_MEDIA_PID" 2>/dev/null || true
                for i in 1 2 3 4 5; do
                    kill -0 "$NO_MEDIA_PID" 2>/dev/null || break
                    usleep 50000 2>/dev/null || sleep 0.1
                done
                if kill -0 "$NO_MEDIA_PID" 2>/dev/null; then
                    kill -9 "$NO_MEDIA_PID" 2>/dev/null || true
                fi
                wait "$NO_MEDIA_PID" 2>/dev/null || true
            fi
        else
            while [ -z "$(locate_source_dir)" ]; do
                sleep 2
            done
        fi
    fi

    sleep 1
done
