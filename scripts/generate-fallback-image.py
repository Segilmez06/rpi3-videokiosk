#!/usr/bin/env python3
"""
generate-fallback-image.py - Generates the "No media found!" fallback screen.
Pure black background with centered white Inter font headline, lighter gray subtitle,
and bottom-left credits.
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

def load_font(font_path, size, weight=500):
    if not font_path:
        return ImageFont.load_default()
    font = ImageFont.truetype(font_path, size=size)
    try:
        font.set_variation_by_axes([14, weight])
    except Exception:
        try:
            font.set_variation_by_name("Medium" if weight == 500 else "Regular")
        except Exception:
            pass
    return font

def render_credits(img, font_path):
    draw = ImageDraw.Draw(img)
    # Weight 500 (Medium - default 400 + 100)
    brand_font = load_font(font_path, size=22, weight=500)
    credit_font = load_font(font_path, size=17, weight=500)

    margin_x = 70
    margin_bottom = 55
    line_spacing = 6

    # Line 1: 'Video Kiosk' in smooth emerald green
    brand_text = "Video Kiosk"
    b_bbox = draw.textbbox((0, 0), brand_text, font=brand_font)
    b_w, b_h = b_bbox[2] - b_bbox[0], b_bbox[3] - b_bbox[1]

    # Line 2: 'Built by ' (white) + 'Sarp Eren EGILMEZ' (blue to purple gradient)
    prefix_text = "Built by "
    name_text = "Sarp Eren EGILMEZ"

    p_bbox = draw.textbbox((0, 0), prefix_text, font=credit_font)
    p_w, p_h = p_bbox[2] - p_bbox[0], p_bbox[3] - p_bbox[1]

    n_bbox = draw.textbbox((0, 0), name_text, font=credit_font)
    n_w, n_h = n_bbox[2] - n_bbox[0], n_bbox[3] - n_bbox[1]

    line2_h = max(p_h, n_h)
    line2_y = img.height - margin_bottom - line2_h
    line1_y = line2_y - line_spacing - b_h

    # Line 1 (smooth beautiful green: #34D399)
    green_color = (52, 211, 153)
    draw.text((margin_x, line1_y), brand_text, font=brand_font, fill=green_color)

    # Line 2 Prefix ('Built by ' in white)
    draw.text((margin_x, line2_y), prefix_text, font=credit_font, fill=(255, 255, 255))

    # Line 2 Name ('Sarp Eren EGILMEZ' with blue-to-purple gradient)
    name_x = margin_x + p_w
    grad_w = max(n_w + 4, 1)
    grad_h = max(n_h + 4, 1)

    grad_img = Image.new("RGB", (grad_w, grad_h))
    g_draw = ImageDraw.Draw(grad_img)

    # Gradient: Vibrant Sky Blue (96, 165, 250) -> Royal Purple (192, 132, 252)
    c_start = (96, 165, 250)
    c_end = (192, 132, 252)

    for x in range(grad_w):
        t = x / max(grad_w - 1, 1)
        r = int(c_start[0] + (c_end[0] - c_start[0]) * t)
        g = int(c_start[1] + (c_end[1] - c_start[1]) * t)
        b = int(c_start[2] + (c_end[2] - c_start[2]) * t)
        g_draw.line([(x, 0), (x, grad_h)], fill=(r, g, b))

    mask = Image.new("L", (grad_w, grad_h), 0)
    m_draw = ImageDraw.Draw(mask)
    m_draw.text((-n_bbox[0], -n_bbox[1]), name_text, font=credit_font, fill=255)

    img.paste(grad_img, (name_x + n_bbox[0], line2_y + n_bbox[1]), mask=mask)

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

    # Render bottom-left credits
    render_credits(img, font_path)

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    img.save(output_path, "PNG")
    print(f"Generated fallback image: {output_path}")

if __name__ == "__main__":
    main()
