#!/usr/bin/env python3
"""
generate-fallback-image.py - Generates the "No media found!" fallback screen.
Pure black background with centered white Inter font headline and a lighter gray subtitle.
"""

import os
import sys
from PIL import Image, ImageDraw, ImageFont

WIDTH, HEIGHT = 1920, 1080

def find_inter_font():
    # Common search paths for Inter font
    candidates = [
        os.path.expanduser("~/.fonts/i/Inter_VariableFont_opsz,wght.ttf"),
        "/usr/share/fonts/TTF/Inter-Regular.ttf",
        "/usr/share/fonts/inter/Inter-Regular.ttf",
        "/usr/share/fonts/truetype/inter/Inter-Regular.ttf",
    ]
    for c in candidates:
        if os.path.isfile(c):
            return c
    # Fallback to fc-match
    import subprocess
    try:
        out = subprocess.check_output(["fc-match", "-f", "%{file}\n", "Inter"], text=True).strip()
        if os.path.isfile(out):
            return out
    except Exception:
        pass
    return None

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    output_path = os.path.join(script_dir, "..", "assets", "no-media.png")

    img = Image.new("RGB", (WIDTH, HEIGHT), color=(0, 0, 0))
    draw = ImageDraw.Draw(img)

    font_path = find_inter_font()
    if font_path:
        title_font = ImageFont.truetype(font_path, size=64)
        desc_font = ImageFont.truetype(font_path, size=32)
    else:
        print("Warning: Inter font not found, falling back to default PIL font.")
        title_font = ImageFont.load_default()
        desc_font = ImageFont.load_default()

    title_text = "No media found!"
    desc_text = "Please put content into media partition."

    # Measure headline
    t_bbox = draw.textbbox((0, 0), title_text, font=title_font)
    t_w, t_h = t_bbox[2] - t_bbox[0], t_bbox[3] - t_bbox[1]

    # Measure description
    d_bbox = draw.textbbox((0, 0), desc_text, font=desc_font)
    d_w, d_h = d_bbox[2] - d_bbox[0], d_bbox[3] - d_bbox[1]

    spacing = 28
    total_h = t_h + spacing + d_h
    start_y = (HEIGHT - total_h) // 2

    # Draw headline (pure white)
    t_x = (WIDTH - t_w) // 2
    draw.text((t_x, start_y), title_text, font=title_font, fill=(255, 255, 255))

    # Draw description (lighter gray, #a0a0a0)
    d_x = (WIDTH - d_w) // 2
    draw.text((d_x, start_y + t_h + spacing), desc_text, font=desc_font, fill=(160, 160, 160))

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    img.save(output_path, "PNG")
    print(f"Generated fallback image: {output_path}")

if __name__ == "__main__":
    main()
