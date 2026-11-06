#!/usr/bin/env python3
"""Prepare deterministic iOS launch sizes and opaque store screenshots.

Requires Pillow. Keeps original artwork and native screenshot contents.
"""
from pathlib import Path
import json
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
logo = Image.open(ROOT/'LandO Property Parcel Icon.png').convert('RGB')
for suffix, size in [('', 160), ('@2x', 320), ('@3x', 480)]:
    logo.resize((size, size), Image.Resampling.LANCZOS).save(
        ROOT/f'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage{suffix}.png')
icons = ROOT/'ios/Runner/Assets.xcassets/AppIcon.appiconset'
for slot in json.loads((icons/'Contents.json').read_text())['images']:
    path = icons/slot['filename']
    image = Image.open(path)
    size = round(float(slot['size'].split('x')[0])*float(slot['scale'].rstrip('x')))
    assert image.size == (size, size), f'Wrong size: {path.name}'
    if image.mode != 'RGB': image.convert('RGB').save(path)
for path in (ROOT/'store/apple/screenshots').rglob('*.png'):
    image = Image.open(path)
    allowed = {(1320, 2868), (1206, 2622), (2064, 2752), (2048, 2732)}
    assert image.size in allowed, f'Recheck App Store screenshot sizes: {path}'
    image.convert('RGB').save(path, optimize=True)
    print(f'{path.relative_to(ROOT)}: {image.size}, opaque RGB')
print('iOS icons, launch images and screenshot encoding checked.')
