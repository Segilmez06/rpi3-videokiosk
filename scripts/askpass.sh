#!/usr/bin/env bash
export DISPLAY="${DISPLAY:-:0}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/1000}"
exec /usr/bin/kdialog --password "${1:-Please enter your sudo password for Video Kiosk Build:}"
