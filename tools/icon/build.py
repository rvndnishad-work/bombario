"""Builds the app's launcher icons from the vector art in this folder.

    python3 tools/icon/build.py

Sources, each a 108x108 canvas (Android's adaptive-icon grid):

  background.svg   the warm burst behind the bomb
  foreground.svg   the glossy bomb, art inside the central 66x66 safe zone
  monochrome.svg   one-colour shape for Android 13+ themed icons

Needs Google Chrome or Chromium: renders them at every size headless. It
looks in the usual places on Windows, macOS and Linux and on PATH; set
CHROME to the browser's path otherwise. Writes:

  Android  res/mipmap-*/ic_launcher.png             legacy square icons
           res/mipmap-*/ic_launcher_background.png  adaptive layers
           res/mipmap-*/ic_launcher_foreground.png
           res/mipmap-*/ic_launcher_monochrome.png
           res/mipmap-anydpi-v26/ic_launcher.xml     adaptive icon
  iOS      Runner/Assets.xcassets/AppIcon.appiconset/*.png (no alpha)

Legacy and iOS icons show the middle 88x88 of the canvas, so the art has
room inside rounded corners. Otherwise pure standard library.
"""
import json
import os
import shutil
import struct
import subprocess
import tempfile
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))
RES = os.path.join(ROOT, 'apps/mobile/android/app/src/main/res')
IOS_SET = os.path.join(
    ROOT, 'apps/mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset')

# Android densities: legacy icon is 48dp, adaptive layers are 108dp.
DENSITIES = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}

# The part of the 108 canvas a legacy or iOS icon shows.
VISIBLE = 88

CHROME_PATHS = [
    r'C:\Program Files\Google\Chrome\Application\chrome.exe',
    r'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe',
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/usr/bin/google-chrome',
    '/usr/bin/chromium',
    '/usr/bin/chromium-browser',
]


def find_chrome():
    for path in [os.environ.get('CHROME')] + CHROME_PATHS:
        if path and os.path.exists(path):
            return path
    found = (shutil.which('google-chrome') or shutil.which('chromium')
             or shutil.which('chromium-browser') or shutil.which('chrome'))
    if not found:
        raise SystemExit('Chrome not found; set CHROME to its path.')
    return found


class Renderer:
    def __init__(self):
        self.chrome = find_chrome()
        self.tmp = tempfile.mkdtemp(prefix='bombario-icon-')
        for name in ('background.svg', 'foreground.svg', 'monochrome.svg'):
            shutil.copy(os.path.join(HERE, name), self.tmp)

    def render(self, path, size, layers, visible=108):
        """Draws [layers] (SVG names, bottom first) at [size] px square,
        showing the middle [visible] units of the 108 canvas."""
        side = size * 108 / visible
        offset = (size - side) / 2
        imgs = ''.join(
            f'<img src="{name}" style="position:absolute;left:{offset}px;'
            f'top:{offset}px;width:{side}px;height:{side}px">'
            for name in layers)
        page = os.path.join(self.tmp, 'page.html')
        open(page, 'w').write(
            '<!doctype html><html><body style="margin:0;background:transparent;'
            f'overflow:hidden;width:{size}px;height:{size}px;position:relative">'
            f'{imgs}</body></html>')
        shot = os.path.join(self.tmp, 'shot.png')
        subprocess.run([
            self.chrome, '--headless=new', '--disable-gpu', '--hide-scrollbars',
            f'--user-data-dir={os.path.join(self.tmp, "profile")}',
            '--default-background-color=00000000',
            f'--window-size={size},{size}', f'--screenshot={shot}',
            'file:///' + page.replace(os.sep, '/').lstrip('/'),
        ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        shutil.move(shot, path)

    def close(self):
        shutil.rmtree(self.tmp, ignore_errors=True)


def strip_alpha(path):
    """Rewrites an 8-bit RGBA PNG as RGB: App Store icons can't have alpha."""
    data = open(path, 'rb').read()
    width, height, depth, colour = struct.unpack('>IIBB', data[16:26])
    if (depth, colour) != (8, 6):
        return
    idat, pos = b'', 8
    while pos < len(data):
        length, kind = struct.unpack('>I4s', data[pos:pos + 8])
        if kind == b'IDAT':
            idat += data[pos + 8:pos + 8 + length]
        pos += 12 + length
    raw, bpp, stride = zlib.decompress(idat), 4, width * 4
    rows, prev = [], bytearray(stride)
    for y in range(height):
        start = y * (stride + 1)
        kind, line = raw[start], bytearray(raw[start + 1:start + 1 + stride])
        for i in range(stride):
            a = line[i - bpp] if i >= bpp else 0
            b, c = prev[i], prev[i - bpp] if i >= bpp else 0
            if kind == 1:
                line[i] = (line[i] + a) & 255
            elif kind == 2:
                line[i] = (line[i] + b) & 255
            elif kind == 3:
                line[i] = (line[i] + (a + b) // 2) & 255
            elif kind == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if pa <= pb and pa <= pc else b if pb <= pc else c
                line[i] = (line[i] + pred) & 255
        rows.append(line)
        prev = line
    rgb = b''.join(b'\x00' + bytes(r[i] for i in range(stride) if i % 4 != 3)
                   for r in rows)

    def chunk(kind, body):
        return (struct.pack('>I', len(body)) + kind + body
                + struct.pack('>I', zlib.crc32(kind + body)))

    open(path, 'wb').write(
        b'\x89PNG\r\n\x1a\n'
        + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
        + chunk(b'IDAT', zlib.compress(rgb, 9)) + chunk(b'IEND', b''))


def android(r):
    for name, k in DENSITIES.items():
        folder = os.path.join(RES, f'mipmap-{name}')
        r.render(os.path.join(folder, 'ic_launcher.png'), round(48 * k),
                 ['background.svg', 'foreground.svg'], VISIBLE)
        layer = round(108 * k)
        for part in ('background', 'foreground', 'monochrome'):
            r.render(os.path.join(folder, f'ic_launcher_{part}.png'), layer,
                     [f'{part}.svg'])
    anydpi = os.path.join(RES, 'mipmap-anydpi-v26')
    os.makedirs(anydpi, exist_ok=True)
    open(os.path.join(anydpi, 'ic_launcher.xml'), 'w', newline='\n').write(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<!-- GENERATED by tools/icon/build.py. Do not edit by hand. -->\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@mipmap/ic_launcher_background" />\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
        '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />\n'
        '</adaptive-icon>\n')


def ios(r):
    images = json.load(open(os.path.join(IOS_SET, 'Contents.json')))['images']
    for name in sorted({e['filename'] for e in images}):
        entry = next(e for e in images if e['filename'] == name)
        points = float(entry['size'].split('x')[0])
        size = round(points * int(entry['scale'][0]))
        path = os.path.join(IOS_SET, name)
        r.render(path, size, ['background.svg', 'foreground.svg'], VISIBLE)
        strip_alpha(path)


def main():
    r = Renderer()
    try:
        android(r)
        ios(r)
    finally:
        r.close()
    print('icons -> android mipmaps, adaptive icon, iOS AppIcon set')


if __name__ == '__main__':
    main()
