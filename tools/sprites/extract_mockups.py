"""One-off import of the 16x16 sprites drawn in the UI mockups.

The mockup boards (see the project's mockups folder) define every sprite as
an SVG <symbol> made of <rect> runs. This script rasterises those symbols
back into editable character maps in sprites.txt, the file build.py reads.
Run it again only if the mockups change; hand edits live in sprites.txt.

    python3 tools/sprites/extract_mockups.py <mockups dir> > tools/sprites/mockup.txt
"""
import glob
import os
import re
import sys

# Characters handed out to colours in order of first use. '.' is transparent.
POOL = ('KkFEWBbYyONScfGgLMDmRrQTtUPpZAaXVvJHhIiCq'
        'dejlnosuwxz0123456789@$%&*+=-:;<>^~!?/|' '"' "'" '`,_()[]{}')
SYM = re.compile(r'<symbol id="([^"]+)" viewBox="0 0 16 16">(.*?)</symbol>', re.S)
TAG = re.compile(r'<(/?)(g|rect|use)\b([^>]*?)/?>')
ATTR = re.compile(r'([\w:-]+)="([^"]*)"')
ROTATE = re.compile(r'rotate\((-?\d+)')

# Prefer the style guide, then the in-game boards; UI icons come last.
ORDER = ['Sprites', 'Versus', 'Coop', 'Lobby', 'Results', 'Home', 'Main']


def render(sid, symbols, cache):
    """Paints one symbol into a 16x16 grid of '#rrggbb' strings (or None)."""
    if sid in cache:
        return cache[sid]
    grid = [[None] * 16 for _ in range(16)]
    fills = [None]
    for close, tag, attrs in TAG.findall(symbols[sid]):
        a = dict(ATTR.findall(attrs))
        if tag == 'g':
            if close:
                fills.pop()
            elif float(a.get('opacity', 1)) < 1:
                fills.append('skip')  # soft shadows don't survive at 16 px
            else:
                fills.append(a.get('fill', fills[-1]))
            if not close and attrs.rstrip().endswith('/'):
                fills.pop()
            continue
        if tag == 'rect':
            colour = a.get('fill', fills[-1])
            if colour in (None, 'none', 'skip') or float(a.get('opacity', 1)) < 1:
                continue
            x, y = int(a.get('x', 0)), int(a.get('y', 0))
            for yy in range(y, y + int(a['height'])):
                for xx in range(x, x + int(a['width'])):
                    grid[yy][xx] = colour.lower()
            continue
        # <use href="#other" transform="rotate(deg 8 8)">
        src = render(a['href'].lstrip('#'), symbols, cache)
        transform = a.get('transform', '')
        rot = ROTATE.search(transform)
        turns = (int(rot.group(1)) // 90) % 4 if rot else 0
        mirror = transform.startswith('matrix(-1 0 0 1 16 0)')
        for yy in range(16):
            for xx in range(16):
                sx, sy = (15 - xx if mirror else xx), yy
                for _ in range(turns):  # undo a clockwise turn per step
                    sx, sy = sy, 15 - sx
                if src[sy][sx]:
                    grid[yy][xx] = src[sy][sx]
    cache[sid] = grid
    return grid


def main(folder):
    symbols = {}
    for name in ORDER:
        path = os.path.join(folder, f'{name}.dc.html')
        if not os.path.exists(path):
            continue
        for sid, body in SYM.findall(open(path).read()):
            symbols.setdefault(sid, body)
    palette, out, cache = {}, [], {}
    for sid in sorted(symbols):
        grid = render(sid, symbols, cache)
        out.append(f'sprite {sid}')
        for row in grid:
            line = ''
            for colour in row:
                if colour is None:
                    line += '.'
                    continue
                if colour not in palette:
                    palette[colour] = POOL[len(palette)]
                line += palette[colour]
            out.append(line)
        out.append('')
    print('# Imported from the UI mockups by extract_mockups.py.')
    print('palette')
    for colour, ch in palette.items():
        print(f'{ch} {colour}')
    print()
    print('\n'.join(out))


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else '.')
