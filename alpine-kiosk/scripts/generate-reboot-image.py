#!/usr/bin/env python3
"""
generate-reboot-image.py - Generates the "Rebooting - This might take a few seconds." screen.
1080p pure black background with clean Inter typography and bottom-left credits.
"""
import os
import sys
import subprocess
from PIL import Image, ImageDraw, ImageFont

WIDTH, HEIGHT = 1920, 1080

def get_inter_font(size, weight=500):
    script_dir = os.path.dirname(os.path.abspath(__file__))
    root_dir = os.path.dirname(os.path.dirname(script_dir))
    bundled_font = os.path.join(root_dir, "assets", "fonts", "Inter-Variable.ttf")

    candidates = [
        bundled_font,
        os.path.expanduser("~/.fonts/i/Inter_VariableFont_opsz,wght.ttf"),
        "/usr/share/fonts/inter/Inter-VariableFont_opsz,wght.ttf",
        "/usr/share/fonts/TTF/Inter-VariableFont_opsz,wght.ttf",
    ]
    for c in candidates:
        if os.path.isfile(c):
            f = ImageFont.truetype(c, size=size)
            try:
                opsz = size if 14 <= size <= 32 else (14 if size < 14 else 32)
                f.set_variation_by_axes([opsz, weight])
                return f
            except Exception:
                return f

    weight_str = "medium" if weight == 500 else ("bold" if weight >= 700 else "regular")
    for pattern in [f"Inter:weight={weight_str}", f"sans:weight={weight_str}", "sans"]:
        try:
            fpath = subprocess.check_output(["fc-match", "-f", "%{file}\n", pattern], text=True).strip()
            if os.path.isfile(fpath):
                return ImageFont.truetype(fpath, size=size)
        except Exception:
            pass
    return ImageFont.load_default()

def get_version_text():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    try:
        git_hash = subprocess.check_output(
            ["git", "rev-parse", "--short", "HEAD"],
            cwd=script_dir,
            text=True
        ).strip()
        if git_hash:
            return f"Video Kiosk 0.1 ({git_hash})"
    except Exception:
        pass
    return "Video Kiosk 0.1"

def render_credits(img):
    draw = ImageDraw.Draw(img)
    # Weight 500 (Inter Medium - increased +100 from default 400)
    brand_font = get_inter_font(22, weight=500)
    credit_font = get_inter_font(17, weight=500)

    margin_x = 70
    margin_bottom = 55
    line_spacing = 6

    # Line 1: 'Video Kiosk 0.1 (git_hash)' in smooth emerald green
    brand_text = get_version_text()
    b_bbox = draw.textbbox((0, 0), brand_text, font=brand_font)
    b_h = b_bbox[3] - b_bbox[1]

    # Line 2: 'by Sarp Eren EGILMEZ' in clean white (gradients removed)
    credit_text = "by Sarp Eren EGILMEZ"
    c_bbox = draw.textbbox((0, 0), credit_text, font=credit_font)
    c_h = c_bbox[3] - c_bbox[1]

    line2_y = img.height - margin_bottom - c_h
    line1_y = line2_y - line_spacing - b_h

    # Line 1 (smooth beautiful green: #34D399)
    green_color = (52, 211, 153)
    draw.text((margin_x, line1_y), brand_text, font=brand_font, fill=green_color)

    # Line 2 (pure white: #ffffff)
    draw.text((margin_x, line2_y), credit_text, font=credit_font, fill=(255, 255, 255))

def main():
    root_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    output_path = os.path.join(root_dir, "..", "assets", "rebooting.png")
    output_path = os.path.abspath(output_path)

    img = Image.new("RGB", (WIDTH, HEIGHT), color=(0, 0, 0))
    draw = ImageDraw.Draw(img)

    title_font = get_inter_font(60, weight=700)
    desc_font = get_inter_font(30, weight=400)

    title_text = "Rebooting"
    desc_text = "This might take a few seconds."

    # Measure headline
    t_bbox = draw.textbbox((0, 0), title_text, font=title_font)
    t_w, t_h = t_bbox[2] - t_bbox[0], t_bbox[3] - t_bbox[1]

    # Measure description
    d_bbox = draw.textbbox((0, 0), desc_text, font=desc_font)
    d_w, d_h = d_bbox[2] - d_bbox[0], d_bbox[3] - d_bbox[1]

    spacing = 26
    total_text_h = t_h + spacing + d_h
    start_y = (HEIGHT - total_text_h) // 2

    # Draw headline (pure white #ffffff)
    t_x = (WIDTH - t_w) // 2
    draw.text((t_x, start_y), title_text, font=title_font, fill=(255, 255, 255))

    # Draw description (lighter gray #a0a0a0)
    d_x = (WIDTH - d_w) // 2
    draw.text((d_x, start_y + t_h + spacing), desc_text, font=desc_font, fill=(160, 160, 160))

    # Render bottom-left credits
    render_credits(img)

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    img.save(output_path, "PNG", optimize=True)
    print(f"Generated rebooting splash image: {output_path} ({os.path.getsize(output_path)} bytes)")

if __name__ == "__main__":
    main()
