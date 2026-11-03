#!/usr/bin/env python3
"""Regenerate native launcher icons from the root PNG using macOS sips."""
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'LandO Property Parcel Icon.png'


def resize(destination: Path, pixels: int) -> None:
    subprocess.run(
        ['sips', '-z', str(pixels), str(pixels), str(SOURCE), '--out', str(destination)],
        check=True,
        stdout=subprocess.DEVNULL,
    )


def main() -> None:
    catalog = ROOT / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
    images = json.loads((catalog / 'Contents.json').read_text())['images']
    for image in images:
        pixels = round(float(image['size'].split('x')[0]) * float(image['scale'][:-1]))
        resize(catalog / image['filename'], pixels)
    resources = ROOT / 'android/app/src/main/res'
    for density, pixels in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
        resize(resources / f'mipmap-{density}/ic_launcher.png', pixels)
    print('Generated iPhone, iPad, App Store and Android launcher icons.')


if __name__ == '__main__':
    main()
