"""Builds the game's sprite atlas from the character maps in this folder.

    python3 tools/sprites/build.py

Reads mockup.txt (sprites imported from the UI mockups) and then extra.txt
(sprites drawn for the game that the mockups don't cover), and writes:

  apps/mobile/assets/images/sprites.png    16x16 cells, 16 per row
  apps/mobile/lib/game/sprite_atlas.g.dart cell index for every sprite name

File format: a `palette` block maps one character to a #rrggbb colour (each
file has its own palette; '.' is transparent), then `sprite <name>` blocks of
16 rows of 16 characters (`sprite <name> mirror` takes 16 rows of the left
8 characters and mirrors them, for symmetric sprites). Derived sprites:

  compose <name> = <a> + <b> [+ ...]      later layers draw over earlier ones
  recolor <name> = <src> #from:#to ...    swaps exact colours
  flipx <name> = <src>                    mirrors left to right
  rotate <name> = <src> <90|180|270>      turns clockwise
  stamp <name> = <src> <patch>            patch over src; #ff00ff erases

Pure standard library so it runs anywhere Python 3 does.
"""
import os
import re
import struct
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))
PNG_OUT = os.path.join(ROOT, 'apps/mobile/assets/images/sprites.png')
DART_OUT = os.path.join(ROOT, 'apps/mobile/lib/game/sprite_atlas.g.dart')
COLUMNS = 16
CELL = 16

Pixel = tuple  # (r, g, b, a)
CLEAR = (0, 0, 0, 0)
ERASE = (255, 0, 255, 255)  # in stamp patches: clears the pixel


def hex_rgba(h):
    h = h.lstrip('#')
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), 255)


def parse(path, sprites, order):
    palette = {'.': CLEAR}
    lines = open(path).read().split('\n')
    i = 0

    def fail(msg):
        sys.exit(f'{os.path.basename(path)}:{i + 1}: {msg}')

    while i < len(lines):
        line = lines[i].rstrip()
        if not line or line.startswith('#') and not re.match(r'^#[0-9a-fA-F]{6}', line):
            i += 1
            continue
        if line == 'palette':
            i += 1
            while i < len(lines) and lines[i].strip():
                ch, colour = lines[i].split()
                if len(ch) != 1:
                    fail(f'palette key must be one character: {ch!r}')
                palette[ch] = hex_rgba(colour)
                i += 1
            continue
        words = line.split()
        if words[0] == 'sprite':
            name = words[1]
            mirror = 'mirror' in words[2:]
            rows = lines[i + 1:i + 1 + CELL]
            if len(rows) != CELL:
                fail(f'{name}: needs {CELL} rows')
            if mirror:
                rows = [row + row[::-1] for row in rows]
            grid = []
            for r, row in enumerate(rows):
                if len(row) != CELL:
                    i += r + 1
                    fail(f'{name}: row has {len(row)} cells, want {CELL}')
                try:
                    grid.append([palette[c] for c in row])
                except KeyError as e:
                    i += r + 1
                    fail(f'{name}: colour {e} is not in this file\'s palette')
            add(sprites, order, name, grid)
            i += 1 + CELL
            continue
        if words[0] in ('compose', 'recolor', 'flipx', 'rotate', 'stamp'):
            name, eq = words[1], words[2]
            if eq != '=':
                fail('expected "="')
            args = words[3:]
            if words[0] == 'stamp':
                grid = [row[:] for row in need(sprites, args[0], fail)]
                patch = need(sprites, args[1], fail)
                for y in range(CELL):
                    for x in range(CELL):
                        if patch[y][x] == ERASE:
                            grid[y][x] = CLEAR
                        elif patch[y][x][3]:
                            grid[y][x] = patch[y][x]
            elif words[0] == 'compose':
                layers = [a for a in args if a != '+']
                grid = [row[:] for row in need(sprites, layers[0], fail)]
                for layer in layers[1:]:
                    top = need(sprites, layer, fail)
                    for y in range(CELL):
                        for x in range(CELL):
                            if top[y][x][3]:
                                grid[y][x] = top[y][x]
            elif words[0] == 'recolor':
                swap = {}
                for pair in args[1:]:
                    a, b = pair.split(':')
                    swap[hex_rgba(a)] = hex_rgba(b)
                grid = [[swap.get(p, p) for p in row]
                        for row in need(sprites, args[0], fail)]
            elif words[0] == 'rotate':
                grid = need(sprites, args[0], fail)
                for _ in range(int(args[1]) // 90 % 4):  # clockwise
                    grid = [[grid[CELL - 1 - x][y] for x in range(CELL)]
                            for y in range(CELL)]
            else:
                grid = [row[::-1] for row in need(sprites, args[0], fail)]
            add(sprites, order, name, grid)
            i += 1
            continue
        fail(f'unexpected line: {line}')


def need(sprites, name, fail):
    if name not in sprites:
        fail(f'unknown sprite {name}')
    return sprites[name]


def add(sprites, order, name, grid):
    if name not in sprites:
        order.append(name)
    sprites[name] = grid


def write_png(path, width, height, pixels):
    raw = b''.join(
        b'\x00' + b''.join(struct.pack('4B', *pixels[y][x]) for x in range(width))
        for y in range(height))

    def chunk(kind, data):
        body = kind + data
        return struct.pack('>I', len(data)) + body + struct.pack('>I', zlib.crc32(body))

    png = (b'\x89PNG\r\n\x1a\n'
           + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))
           + chunk(b'IDAT', zlib.compress(raw, 9))
           + chunk(b'IEND', b''))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, 'wb').write(png)


def main():
    sprites, order = {}, []
    for name in ('mockup.txt', 'extra.txt'):
        parse(os.path.join(HERE, name), sprites, order)
    rows = (len(order) + COLUMNS - 1) // COLUMNS
    width, height = COLUMNS * CELL, rows * CELL
    pixels = [[CLEAR] * width for _ in range(height)]
    for n, name in enumerate(order):
        ox, oy = (n % COLUMNS) * CELL, (n // COLUMNS) * CELL
        for y in range(CELL):
            for x in range(CELL):
                pixels[oy + y][ox + x] = sprites[name][y][x]
    write_png(PNG_OUT, width, height, pixels)

    entries = '\n'.join(f"  '{name}': {n}," for n, name in enumerate(order))
    open(DART_OUT, 'w').write(f'''// GENERATED by tools/sprites/build.py. Do not edit by hand.

/// Cell size of the sprite atlas, in source pixels.
const int spriteCell = {CELL};

/// Cells per row in `assets/images/sprites.png`.
const int spriteColumns = {COLUMNS};

/// Atlas cell for every sprite name.
const Map<String, int> spriteIndex = {{
{entries}
}};
''')
    print(f'{len(order)} sprites -> {os.path.relpath(PNG_OUT, ROOT)} ({width}x{height})')


if __name__ == '__main__':
    main()
