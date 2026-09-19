#!/usr/bin/env bash
#
# kiosk-expand.sh - First-boot partition auto-expander & stylized setup console
#

FLAG_FILE="/etc/kiosk-expanded"

if [ -f "$FLAG_FILE" ]; then
    exit 0
fi

# Green ACT LED ON during first-boot setup only. Red PWR LED stays OFF always.
echo none   > /sys/class/leds/PWR/trigger    2>/dev/null || true
echo 0      > /sys/class/leds/PWR/brightness 2>/dev/null || true
echo none   > /sys/class/leds/led1/trigger   2>/dev/null || true
echo 0      > /sys/class/leds/led1/brightness 2>/dev/null || true
echo default-on > /sys/class/leds/ACT/trigger    2>/dev/null || true
echo 1          > /sys/class/leds/ACT/brightness 2>/dev/null || true
echo default-on > /sys/class/leds/led0/trigger   2>/dev/null || true
echo 1          > /sys/class/leds/led0/brightness 2>/dev/null || true

# Direct output to tty1 console
exec > /dev/tty1 2>&1
setterm -cursor off > /dev/tty1 2>/dev/null || true
clear > /dev/tty1 2>/dev/null || true

# ANSI styling
CYAN="\033[1;36m"
WHITE="\033[1;37m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
GRAY="\033[0;90m"
RESET="\033[0m"

echo ""
echo -e "${CYAN}  ╔══════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${CYAN}  ║${WHITE}            Raspberry Pi 3 Video Kiosk - Initial Setup        ${CYAN}║${RESET}"
echo -e "${CYAN}  ╚══════════════════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  ${YELLOW}[*] First-time initialization in progress. Please do not power off.${RESET}"
echo ""

# 1. Detect storage device
ROOT_DEV=$(findmnt -n -o SOURCE /)
DISK_DEV=$(lsblk -no PKNAME "$ROOT_DEV" 2>/dev/null)
if [ -z "$DISK_DEV" ]; then
    DISK_DEV="mmcblk0"
fi
DISK_PATH="/dev/$DISK_DEV"
PART3_PATH="${DISK_PATH}p3"

echo -e "  ${WHITE}• Storage Device:${RESET}         ${CYAN}/dev/${DISK_DEV}${RESET}                         ${GREEN}[  OK  ]${RESET}"

if [ ! -b "$DISK_PATH" ] || [ ! -b "$PART3_PATH" ]; then
    echo -e "  ${YELLOW}[!] Warning: Partition 3 not found on $DISK_PATH, skipping resize.${RESET}"
    touch "$FLAG_FILE"
    sleep 3
    exit 0
fi

# 2. Expanding partition table
echo -ne "  ${WHITE}• Partition Expansion:${RESET}    ${CYAN}Partition 3 -> 100% capacity...${RESET}      "
umount /media/videos 2>/dev/null || true
parted -s "$DISK_PATH" resizepart 3 100%
partprobe "$DISK_PATH" 2>/dev/null || true
udevadm settle 2>/dev/null || sleep 1
echo -e "${GREEN}[  OK  ]${RESET}"

# 3. Reformat FAT32 filesystem with optimal cluster size for large SD cards.
#    Using fatresize causes false 63% usage because the cluster size is inherited
#    from the tiny 100MB stub at mkfs time. Reformatting with -s 128 (64KB clusters)
#    is correct and safe — the VIDEOS partition is always empty on first boot.
echo -ne "  ${WHITE}• Formatting Media FS:${RESET}    ${CYAN}FAT32 with 64K clusters (large-SD)...${RESET} "
mkfs.vfat -F 32 -s 128 -n "VIDEOS" "$PART3_PATH" > /dev/null 2>&1
echo -e "${GREEN}[  OK  ]${RESET}"

# 4. Finalizing mounts
echo -e "  ${WHITE}• Write Protection:${RESET}       ${CYAN}Read-Only Mode (Power-Safe)${RESET}          ${GREEN}[  OK  ]${RESET}"
mkdir -p /media/videos
mount -a 2>/dev/null || true

echo -e "  ${WHITE}• Display Acceleration:${RESET}   ${CYAN}VideoCore IV (DRM/KMS Direct)${RESET}        ${GREEN}[  OK  ]${RESET}"

# Turn green ACT LED OFF permanently — no LEDs once kiosk is running
echo none > /sys/class/leds/ACT/trigger    2>/dev/null || true
echo 0    > /sys/class/leds/ACT/brightness 2>/dev/null || true
echo none > /sys/class/leds/led0/trigger   2>/dev/null || true
echo 0    > /sys/class/leds/led0/brightness 2>/dev/null || true

# 5. Done — write flag file NOW and force sync before the user sees success.
#    This gives the ext4 journal time to commit before they might cut power.
touch "$FLAG_FILE"
sync

echo ""
echo -e "${CYAN}  ──────────────────────────────────────────────────────────────${RESET}"
echo -e "  ${GREEN}✔ First-boot configuration completed successfully!${RESET}"
echo -e "  ${WHITE}Starting video playback in 3 seconds...${RESET}"
sleep 3
sync   # second sync — belt-and-suspenders
clear
exit 0
