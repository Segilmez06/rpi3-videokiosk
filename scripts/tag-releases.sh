#!/usr/bin/env bash
# tag-releases.sh - Automatically tag all historical and current milestones
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> Tagging Video Kiosk Milestones..."

tag_if_missing() {
    local tag="$1"
    local commit="$2"
    local msg="$3"

    if git rev-parse "$tag" >/dev/null 2>&1; then
        echo "  [-] Tag $tag already exists, skipping."
    else
        echo "  [+] Creating annotated tag $tag -> $commit"
        git tag -a "$tag" "$commit" -m "$msg"
    fi
}

tag_if_missing "v0.1" "204fdef" "Release v0.1: Initial Headless Video Kiosk Appliance & Build System"
tag_if_missing "v0.2" "50a569b" "Release v0.2: Dedicated PL011 Hardware UART Backend & Silent HDMI Signage"
tag_if_missing "v0.3" "1f24cbc" "Release v0.3: Pure Run-from-RAM Diskless Alpine Linux Architecture"
tag_if_missing "v0.4" "831fbcb" "Release v0.4: Smart In-RAM VFS Media Caching & Gapless Multi-Video Playlist Loop"
tag_if_missing "v0.5" "4c60cf3" "Release v0.5: Hardware LED Operational State Machine & Stealth Mode"
tag_if_missing "v0.6" "956b1ec" "Release v0.6: Dynamic Display Orientation Engine"
tag_if_missing "v0.7" "d03fbaa" "Release v0.7: Freestanding Framebuffer Renderer (fbdraw) & Custom Typography"
tag_if_missing "v0.8" "e280dad" "Release v0.8: Real-Time Media Hotplug Watcher & Automated Reboot Handler"

# For v0.9, tag current HEAD once committed or current HEAD
tag_if_missing "v0.9" "HEAD" "Release v0.9: Unified 4-State UI Pipeline & Framebuffer-to-DRM KMS Handoff"

echo ""
echo "==> Done! All tags created."
echo "To push all tags to GitHub, run:"
echo "    git push origin --tags"
