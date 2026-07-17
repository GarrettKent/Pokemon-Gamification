# Title: generateTallGrass
# Created By: Garrett Kent - 06/20/2026
# Purpose: Generate a CSP-safe animated GIF of swaying Pokemon-style tall grass for the biomeExplorer
#          grass patches. Pixel-art tufts on a meadow ground that rustle/sway in a seamless loop.
#          Output -> force-app/main/default/staticresources/tallGrassSway.gif
import math
from PIL import Image, ImageDraw

WIDTH = 96
HEIGHT = 72
FRAMES = 14
SCALE = 1

GROUND_TOP = (171, 214, 94)     # #ABD65E meadow
GROUND_BOTTOM = (138, 188, 74)  # #8ABC4A darker band at base
BLADE_DARK = (58, 110, 40)      # #3A6E28
BLADE_MID = (74, 138, 50)       # #4A8A32
BLADE_LIGHT = (122, 199, 76)    # #7AC74C highlight

# Each tuft: base x, base y, height, lean phase offset, blade colors
def build_tufts():
    tufts = []
    bases = [8, 18, 28, 38, 48, 58, 68, 78, 88]
    for i, bx in enumerate(bases):
        by = HEIGHT - 5 - (i % 2) * 2
        height = 36 + (i % 3) * 7
        tufts.append({
            'bx': bx,
            'by': by,
            'h': height,
            'phase': i * 0.7,
            'spread': 5 + (i % 2) * 2
        })
    return tufts

def draw_blade(draw, bx, by, h, sway, color, width):
    # Polyline from base up to tip, horizontal offset grows toward the tip (top bends most).
    points = []
    steps = 10
    for s in range(steps + 1):
        frac = s / steps
        y = by - h * frac
        x = bx + sway * (frac ** 1.6)
        points.append((x, y))
    draw.line(points, fill=color, width=width, joint='curve')

def render_frame(frame_index, tufts):
    img = Image.new('RGBA', (WIDTH, HEIGHT), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Ground bands (rounded look comes from the component CSS; keep the asset square + tileable)
    draw.rectangle([0, 0, WIDTH, HEIGHT], fill=GROUND_TOP + (255,))
    draw.rectangle([0, HEIGHT - 14, WIDTH, HEIGHT], fill=GROUND_BOTTOM + (255,))

    phase = 2 * math.pi * frame_index / FRAMES
    for tuft in tufts:
        amp = tuft['spread'] + 1.5 * math.sin(phase * 0.5 + tuft['phase'])
        sway = amp * math.sin(phase + tuft['phase'])
        bx, by, h = tuft['bx'], tuft['by'], tuft['h']
        # dense tuft: several dark back blades fanning out, mid-green body, light highlight
        draw_blade(draw, bx - 7, by, h - 10, sway * 0.7, BLADE_DARK, 4)
        draw_blade(draw, bx + 7, by, h - 8, sway * 0.85, BLADE_DARK, 4)
        draw_blade(draw, bx - 3, by, h - 3, sway * 0.92, BLADE_MID, 4)
        draw_blade(draw, bx + 3, by, h - 4, sway * 0.98, BLADE_MID, 4)
        draw_blade(draw, bx, by, h, sway, BLADE_MID, 5)
        draw_blade(draw, bx - 1, by, h - 2, sway * 1.05, BLADE_LIGHT, 2)
        draw_blade(draw, bx + 4, by, h - 7, sway * 1.05, BLADE_LIGHT, 2)
    return img

def main():
    tufts = build_tufts()
    frames = [render_frame(i, tufts) for i in range(FRAMES)]
    out = '/Users/garrettkent/Code/Pokemon-Gamification/force-app/main/default/staticresources/tallGrassSway.gif'
    # GIF needs palette; composite onto opaque ground (no transparency needed — it fills the tile)
    rgb_frames = [f.convert('RGB').convert('P', palette=Image.ADAPTIVE, colors=32) for f in frames]
    rgb_frames[0].save(
        out,
        save_all=True,
        append_images=rgb_frames[1:],
        duration=90,
        loop=0,
        optimize=True
    )
    print(f'Wrote {out} ({len(frames)} frames, {WIDTH}x{HEIGHT})')

if __name__ == '__main__':
    main()
