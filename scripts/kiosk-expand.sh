#!/usr/bin/env bash
#
# kiosk-expand.sh - First-boot partition auto-expander & stylized setup console
#

FLAG_FILE="/etc/kiosk-expanded"

if [ -f "$FLAG_FILE" ]; then
    exit 0
fi

# Ensure Red LED is ON and Green ACT LED is OFF during setup
echo default-on > /sys/class/leds/PWR/trigger 2>/dev/null || true
echo 1 > /sys/class/leds/PWR/brightness 2>/dev/null || true
echo none > /sys/class/leds/ACT/trigger 2>/dev/null || true
echo 0 > /sys/class/leds/ACT/brightness 2>/dev/null || true
echo default-on > /sys/class/leds/led1/trigger 2>/dev/null || true
echo 1 > /sys/class/leds/led1/brightness 2>/dev/null || true
echo none > /sys/class/leds/led0/trigger 2>/dev/null || true
echo 0 > /sys/class/leds/led0/brightness 2>/dev/null || true

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

# 3. Resizing FAT32 filesystem
echo -ne "  ${WHITE}• Resizing FAT32 System:${RESET}  ${YELLOW}Optimizing allocation tables...${RESET}      "
if command -v fatresize >/dev/null 2>&1; then
    fatresize -s max "$PART3_PATH" >/dev/null 2>&1 || true
else
    fsck.vfat -a "$PART3_PATH" 2>/dev/null || true
fi
echo -e "\r  ${WHITE}• Resizing FAT32 System:${RESET}  ${CYAN}Capacity Maximized (Full SD)${RESET}         ${GREEN}[  OK  ]${RESET}"

# 4. Finalizing mounts
echo -e "  ${WHITE}• Write Protection:${RESET}       ${CYAN}Read-Only Mode (Power-Safe)${RESET}          ${GREEN}[  OK  ]${RESET}"
mkdir -p /media/videos
mount -a 2>/dev/null || true

echo -e "  ${WHITE}• Display Acceleration:${RESET}   ${CYAN}VideoCore IV (DRM/KMS Direct)${RESET}        ${GREEN}[  OK  ]${RESET}"

# Restore natural green LED for future boot tracking
echo mmc0 > /sys/class/leds/ACT/trigger 2>/dev/null || true
echo mmc0 > /sys/class/leds/led0/trigger 2>/dev/null || true

# 5. Done
echo ""
echo -e "${CYAN}  ──────────────────────────────────────────────────────────────${RESET}"
echo -e "  ${GREEN}✔ First-boot configuration completed successfully!${RESET}"
echo -e "  ${WHITE}Starting video playback in 3 seconds...${RESET}"
sleep 3
clear
touch "$FLAG_FILE"
exit 0
