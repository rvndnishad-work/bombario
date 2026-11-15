"""Draws the power-up tokens and rewrites the power-ups section of crew.txt.

    python3 tools/sprites/crew_tokens.py && python3 tools/sprites/build.py

Each power-up is a round token coloured by family with a bold white glyph and
an automatic dark outline. Glyphs are 10x10 character maps below: '#' white,
'o' dark ink, 'y' 'r' 'c' 'p' accents. Each glyph is also written on its own
as icon-<name> for the HUD.
"""
import os
# Token colours per family: (light rim, body, shade)
FAM = {
    'power':   ('#ffb08a', '#ff5a3c', '#b8321e'),   # bombs, fire, speed: grow stronger
    'ability': ('#a8d4ff', '#3a86ff', '#1f4fbf'),   # passes, kick, remote: new moves
    'special': ('#d9c2ff', '#8e5bd9', '#5a3399'),   # one-shot and team items
    'life':    ('#fff1a0', '#f2b630', '#a86a10'),
}
INK = '#1a1420'
WHITE = '#ffffff'
ACCENT = {'y': '#ffd23f', 'r': '#ff5a3c', 'c': '#9fe6ff', 'p': '#ff6a9a'}

G = {}
G['bomb'] = ('power', """
.......y.y
........y.
.......#..
...####...
..######..
.###.####.
.##.#####.
.########.
..######..
...####...""")
G['fire'] = ('power', """
....#.....
....##....
...###..#.
...####.#.
..#######.
..##yy###.
.##yyyy##.
.##yyyy##.
.###yy###.
..######..""")
G['speed'] = ('power', """
..........
##...##...
.##...##..
..##...##.
...##...##
...##...##
..##...##.
.##...##..
##...##...
..........""")
G['wall'] = ('ability', """
...####...
..######..
.########.
.##o##o##.
.##o##o##.
.########.
.########.
.########.
.##.##.##.
.#..#..#..""")
G['remote'] = ('ability', """
..........
...####...
..#rrrr#..
.#rrrrrr#.
.#rrrrrr#.
..######..
.########.
##########
##########
..........""")
G['bombpass'] = ('ability', """
.....y....
....#.....
..####....
.#....##..
#......##.
##########
#......##.
.#....##..
..####....
..........""")
G['flamepass'] = ('ability', """
.########.
.###yy###.
.##yyyy##.
.##yrry##.
.##yrry##.
.##yyyy##.
..##yy##..
..######..
...####...
....##....""")
G['kick'] = ('ability', """
.....####.
.....####.
.....###..
.....###..
.....###..
..######..
.#######..
.########.
.########.
..........""")
G['mystery'] = ('special', """
..######..
.###..###.
.##....##.
.......##.
.....###..
....###...
....##....
..........
....##....
....##....""")
G['heart'] = ('special', """
..........
.###..###.
#####.####
##########
##########
.########.
..######..
...####...
....##....
..........""")
G['sonar'] = ('special', """
..######..
.#......#.
#..####..#
#.#....#.#
#.#.##.#.#
#.#.##.#.#
#.#....#.#
#..####..#
.#......#.
..######..""")
G['teamboost'] = ('special', """
....##....
...####...
..######..
.###..###.
....##....
...####...
..######..
.###..###.
....##....
....##....""")
G['tether'] = ('special', """
..##rr##..
.###rr###.
##......##
##......##
rr......rr
rr......rr
##......##
##......##
.###rr###.
..##rr##..""")
G['frost'] = ('special', """
....##....
.#..##..#.
..#.##.#..
...####...
##########
##########
...####...
..#.##.#..
.#..##..#.
....##....""")
G['life'] = ('life', """
..........
..........
#.#.#.###.
#.#.#.#.#.
#.#.#.###.
#.#.#.#...
#.#.#.#...
#..#..#...
..........
..........""")


def token(fam):
    light, body, shade = FAM[fam]
    rows = [
        "...oooooooooo...",
        "..oHHHHHHHHHHo..",
        ".oHHccccccccccdo"[:16],
    ]
    shape = []
    for y in range(16):
        r = []
        for x in range(16):
            # rounded square: corners cut by a radius-3 arc
            cx = min(x, 15 - x); cy = min(y, 15 - y)
            if cx + cy < 3:
                r.append(None)
            elif cx == 0 or cy == 0 or cx + cy == 3:
                r.append(INK)
            elif cy == 1 and y < 8 or cx + cy == 4 and y < 8:
                r.append(light)
            elif cy == 1 and y > 8 or cx + cy == 4 and y > 8:
                r.append(shade)
            else:
                r.append(body)
        shape.append(r)
    return shape


def glyph_px(name):
    fam, art = G[name]
    rows = art.strip('\n').split('\n')
    assert len(rows) == 10 and all(len(r) == 10 for r in rows), (name, [len(r) for r in rows])
    px = {}
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch == '#':
                px[(x + 3, y + 3)] = WHITE
            elif ch == 'o':
                px[(x + 3, y + 3)] = INK
            elif ch in ACCENT:
                px[(x + 3, y + 3)] = ACCENT[ch]
    # dark outline around the glyph (4-neighbours)
    out = {}
    for (x, y) in px:
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            q = (x + dx, y + dy)
            if q not in px and 0 <= q[0] < 16 and 0 <= q[1] < 16:
                out[q] = INK
    return fam, px, out


def emit(name, grid, palette):
    lines = []
    for r in grid:
        line = ''
        for c in r:
            line += '.' if c is None else palette[c]
        lines.append(line)
    return f"sprite {name}\n" + "\n".join(lines) + "\n"


colours = {}
def key(c):
    if c not in colours:
        colours[c] = "ABCDEFGHIJLMNOPQRSTUVXYZabdefghijkmnqstuvwxz0123456789"[len(colours)]
    return colours[c]

blocks = []
for name in G:
    fam, px, out = glyph_px(name)
    tok = token(fam)
    grid = [row[:] for row in tok]
    for (x, y), c in out.items():
        grid[y][x] = c
    for (x, y), c in px.items():
        grid[y][x] = c
    icon = [[None] * 16 for _ in range(16)]
    for (x, y), c in out.items():
        icon[y][x] = c
    for (x, y), c in px.items():
        icon[y][x] = c
    for g in (grid, icon):
        for r in g:
            for c in r:
                if c: key(c)
    blocks.append(('pu-' + name, grid))
    blocks.append(('icon-' + name, icon))

pal = "palette\n" + "\n".join(f"{k} {c}" for c, k in colours.items()) + "\n"
txt = pal + "\n" + "\n".join(emit(n, g, colours) for n, g in blocks)
CREW = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'crew.txt')
MARK = '# --------------------------------------------------------------- power-ups\n'
head = open(CREW).read().split(MARK)[0]
open(CREW, 'w').write(head + MARK + txt)
print(len(blocks), 'power-up sprites -> crew.txt')
