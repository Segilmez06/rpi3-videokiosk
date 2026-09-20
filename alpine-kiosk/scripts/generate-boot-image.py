#!/usr/bin/env python3
"""
generate-boot-image.py - Generates the "Starting Video Kiosk..." boot splash screen.
1080p pure black background with clean Inter font typography.
"""
import os
import sys
from PIL import Image, ImageDraw, ImageFont

WIDTH, HEIGHT = 1920, 1080

def find_font():
    candidates = [
        os.path.expanduser("~/.fonts/i/Inter_VariableFont_opsz,wght.ttf"),
        "/usr/share/fonts/TTF/Inter-Regular.ttf",
        "/usr/share/fonts/inter/Inter-Regular.ttf",
        "/usr/share/fonts/truetype/inter/Inter-Regular.ttf",
    ]
    for c in candidates:
        if os.path.isfile(c):
            return c
    import subprocess
    try:
        out = subprocess.check_output(["fc-match", "-f", "%{file}\n", "sans-serif"], text=True).strip()
        if os.path.isfile(out):
            return out
    except Exception:
        pass
    return None

def main():
    root_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    output_path = os.path.join(root_dir, "..", "assets", "booting.png")
    output_path = os.path.abspath(output_path)

    img = Image.new("RGB", (WIDTH, HEIGHT), color=(0, 0, 0))
    draw = ImageDraw.Draw(img)

    font_path = find_font()
    if font_path:
        title_font = ImageFont.truetype(font_path, size=56)
        desc_font = ImageFont.truetype(font_path, size=28)
    else:
        title_font = ImageFont.load_default()
        desc_font = ImageFont.load_default()

    title_text = "Hang tight!"
    desc_text = "Copying data to RAM."

    # Draw a minimalist, elegant loading dot accent above text
    center_x = WIDTH // 2
    accent_y = (HEIGHT // 2) - 80
    dot_radius = 4
    dot_spacing = 20
    num_dots = 3
    start_dot_x = center_x - ((num_dots - 1) * dot_spacing) // 2
    for i in range(num_dots):
        x = start_dot_x + (i * dot_spacing)
        alpha = 140 if i != 1 else 255
        draw.ellipse([x - dot_radius, accent_y - dot_radius, x + dot_radius, accent_y + dot_radius], fill=(alpha, alpha, alpha))

    # Measure headline
    t_bbox = draw.textbbox((0, 0), title_text, font=title_font)
    t_w, t_h = t_bbox[2] - t_bbox[0], t_bbox[3] - t_bbox[1]

    # Measure description
    d_bbox = draw.textbbox((0, 0), desc_text, font=desc_font)
    d_w, d_h = d_bbox[2] - d_bbox[0], d_bbox[3] - d_bbox[1]

    spacing = 24
    start_y = (HEIGHT // 2) - 20

    # Draw headline (pure white #ffffff)
    t_x = (WIDTH - t_w) // 2
    draw.text((t_x, start_y), title_text, font=title_font, fill=(255, 255, 255))

    # Draw description (lighter gray #a0a0a0)
    d_x = (WIDTH - d_w) // 2
    draw.text((d_x, start_y + t_h + spacing), desc_text, font=desc_font, fill=(160, 160, 160))

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    img.save(output_path, "PNG", optimize=True)
    print(f"Generated boot splash image: {output_path} ({os.path.getsize(output_path)} bytes)")

if __name__ == "__main__":
    main()
