"""Export platform icons from the selected, transparent Memoria artwork.

Run with Python 3 and Pillow: python3 tool/generate_brand_assets.py
Only padding, sizing and platform background/mask exports are applied.
"""

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageOps

ROOT = Path(__file__).resolve().parents[1]
BACKGROUND = '#121316'
SOURCE = ROOT / 'assets/icons/memoria-mark.png'


def save(image, relative):
    path = ROOT / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path)


def main():
    source = Image.open(SOURCE).convert('RGBA')
    bounds = source.getchannel('A').point(lambda value: 255 if value > 16 else 0).getbbox()
    if bounds is None:
        raise ValueError('Memoria artwork is empty')
    artwork = source.crop(bounds)

    def canvas(size, fraction=0.84, background=BACKGROUND):
        result = Image.new('RGBA', (size, size), background or (0, 0, 0, 0))
        extent = round(size * fraction)
        mark = ImageOps.contain(artwork, (extent, extent), Image.Resampling.LANCZOS)
        result.alpha_composite(mark, ((size - mark.width) // 2, (size - mark.height) // 2))
        return result

    # Standard asset catalogs use opaque, full-bleed icons; the logo stays RGBA.
    master = canvas(1024).convert('RGB')
    save(master, 'assets/icons/memoria-app-icon.png')
    ios = ROOT / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
    images = []
    for idiom, sizes in (
        ('iphone', [('20x20', 2), ('20x20', 3), ('29x29', 2), ('29x29', 3),
                    ('40x40', 2), ('40x40', 3), ('60x60', 2), ('60x60', 3)]),
        ('ipad', [('20x20', 1), ('20x20', 2), ('29x29', 1), ('29x29', 2),
                  ('40x40', 1), ('40x40', 2), ('76x76', 1), ('76x76', 2), ('83.5x83.5', 2)]),
        ('ios-marketing', [('1024x1024', 1)]),
    ):
        for size, scale in sizes:
            filename = f'Icon-App-{size}@{scale}x.png'
            pixels = round(float(size.split('x')[0]) * scale)
            master.resize((pixels, pixels), Image.Resampling.LANCZOS).save(ios / filename)
            images.append({'idiom': idiom, 'size': size, 'scale': f'{scale}x', 'filename': filename})
    (ios / 'Contents.json').write_text(json.dumps({'images': images, 'info': {'author': 'xcode', 'version': 1}}, indent=2) + '\n')

    for scale in (1, 2, 3):
        suffix = '' if scale == 1 else f'@{scale}x'
        save(source.resize((128 * scale, 128 * scale), Image.Resampling.LANCZOS),
             f'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage{suffix}.png')

    # Keep the entire rectangular mark inside the adaptive icon's safe circle.
    # For this aspect ratio, a 46%-width mark has a <66dp diagonal on 108dp.
    save(canvas(432, 0.46, None), 'android/app/src/main/res/drawable-nodpi/ic_launcher_foreground.png')
    for density, pixels in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
        launch_pixels = round(128 * pixels / 48)
        save(source.resize((launch_pixels, launch_pixels), Image.Resampling.LANCZOS),
             f'android/app/src/main/res/drawable-{density}/memoria_launch_mark.png')
        icon = canvas(pixels, 0.72)
        save(icon.convert('RGB'), f'android/app/src/main/res/mipmap-{density}/ic_launcher.png')
        mask = Image.new('L', (pixels, pixels))
        ImageDraw.Draw(mask).ellipse((0, 0, pixels - 1, pixels - 1), fill=255)
        icon.putalpha(mask)
        save(icon, f'android/app/src/main/res/mipmap-{density}/ic_launcher_round.png')

    for pixels in (192, 512):
        save(canvas(pixels).convert('RGB'), f'web/icons/Icon-{pixels}.png')
        save(canvas(pixels, 0.60).convert('RGB'), f'web/icons/Icon-maskable-{pixels}.png')
    save(canvas(48).convert('RGB'), 'web/favicon.png')
    canvas(256).save(ROOT / 'windows/runner/resources/app_icon.ico', sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    print('Exported Memoria iOS, Android, web, Windows and launch assets.')


if __name__ == '__main__':
    main()
