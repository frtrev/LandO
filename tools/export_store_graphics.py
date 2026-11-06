#!/usr/bin/env python3
"""Deterministic store-size exports from LandO's existing logo; no new AI art."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

root = Path(__file__).resolve().parents[1]
out = root/'store/graphics'
out.mkdir(parents=True, exist_ok=True)
logo = Image.open(root/'LandO Property Parcel Icon.png').convert('RGB')
logo.resize((512, 512), Image.Resampling.LANCZOS).convert('RGBA').save(out/'app-icon-512.png', optimize=True)
canvas = Image.new('RGB', (1024, 500), '#09251b')
draw = ImageDraw.Draw(canvas)
font_dir = Path('/System/Library/Fonts/Supplemental')
def font(size, bold=False):
    path = font_dir/('Arial Bold.ttf' if bold else 'Arial.ttf')
    if not path.exists(): raise SystemExit('Set the script font paths to locally licensed Arial or equivalent fonts.')
    return ImageFont.truetype(str(path), size)
# Decorative parcel linework; this is a feature graphic, not an app screenshot.
draw.line([(570,30),(1000,110),(930,470),(540,400),(570,30)], fill='#174b37', width=2)
for x,y in [(570,30),(1000,110),(930,470),(540,400)]: draw.ellipse((x-6,y-6,x+6,y+6), fill='#296d4c')
draw.text((60,52), 'LandO', font=font(30,True), fill='#c4f78f')
draw.text((60,125), 'Your land.', font=font(50,True), fill='#ffffff')
draw.text((60,187), 'Your perspective.', font=font(50,True), fill='#ffffff')
draw.text((60,285), 'Map boundaries. Save areas.', font=font(23), fill='#daeadf')
draw.text((60,320), 'Measure distance. Plan ahead.', font=font(23), fill='#daeadf')
draw.text((60,420), 'Map-derived planning estimates', font=font(16), fill='#a4c0ac')
canvas.paste(logo.resize((326,326), Image.Resampling.LANCZOS), (640,87))
canvas.save(out/'feature-graphic-1024x500.png', optimize=True)
assert Image.open(out/'app-icon-512.png').size == (512,512)
assert Image.open(out/'feature-graphic-1024x500.png').size == (1024,500)
assert (out/'app-icon-512.png').stat().st_size < 1024*1024
print('Exported 512 px RGBA icon and 1024×500 RGB feature graphic from the existing brand asset.')
