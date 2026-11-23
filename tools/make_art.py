#!/usr/bin/env python3
"""Leo's art generator. Writes the SVG files in art/. The SVGs are the source of truth once generated:
edit them by hand or with any vector editor. This script only keeps the style consistent while drawing.
Style: warm paper, ink outlines, soot-grey and brown buildings, a little fire orange. 64x64 canvas."""
import math, os

ROOT = os.path.join(os.path.dirname(__file__), "..", "art")
INK = "#2a2622"; SOOT = "#3c3c3f"; BROWN = "#5b4636"; PAPER = "#efe6d2"; PAPER_D = "#e2d6ba"; PAPER_DD = "#cfc1a1"
FIRE = "#e08a2e"; FIRE_Y = "#f2c14e"; RUST = "#8c3b2a"; RUST_D = "#5a2519"; COAL = "#2b2b2b"; COAL_L = "#7a7a7a"
STONE = "#bdb7a6"; COPPER = "#b8692f"; COPPER_L = "#dd9a5c"; PATINA = "#5f9c8a"; STEEL = "#5f7480"; STEEL_L = "#9fb0ba"


def svg(body):
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64" '
            'stroke-linejoin="round" stroke-linecap="round">%s</svg>\n' % body)

def pts(p): return " ".join("%.1f,%.1f" % (x, y) for x, y in p)
def rect(x, y, w, h, fill, sw=2, rx=0, stroke=INK):
    return '<rect x="%g" y="%g" width="%g" height="%g" rx="%g" fill="%s" stroke="%s" stroke-width="%g"/>' % (x, y, w, h, rx, fill, stroke, sw)
def poly(p, fill, sw=2, stroke=INK):
    return '<polygon points="%s" fill="%s" stroke="%s" stroke-width="%g"/>' % (pts(p), fill, stroke, sw)
def circ(cx, cy, r, fill, sw=2, stroke=INK):
    return '<circle cx="%g" cy="%g" r="%g" fill="%s" stroke="%s" stroke-width="%g"/>' % (cx, cy, r, fill, stroke, sw)
def line(x1, y1, x2, y2, sw=2, stroke=INK):
    return '<line x1="%g" y1="%g" x2="%g" y2="%g" stroke="%s" stroke-width="%g"/>' % (x1, y1, x2, y2, stroke, sw)
def path(d, fill="none", sw=2, stroke=INK):
    return '<path d="%s" fill="%s" stroke="%s" stroke-width="%g"/>' % (d, fill, stroke, sw)

def gear(cx, cy, r_out, r_in, teeth, fill, hub=None):
    p = []
    for i in range(teeth):
        a = 2 * math.pi * i / teeth
        w = math.pi / teeth * 0.55
        for ang, r in ((a - w, r_in), (a - w * 0.6, r_out), (a + w * 0.6, r_out), (a + w, r_in)):
            p.append((cx + r * math.cos(ang), cy + r * math.sin(ang)))
    s = poly(p, fill, 2)
    s += circ(cx, cy, r_in * 0.42, hub or PAPER, 2)
    return s

def ground(): return line(2, 58, 62, 58, 2.5)
def smoke(x, y, d=1): return circ(x, y, 3.2, PAPER, 1.6) + circ(x + 5 * d, y - 4, 2.6, PAPER, 1.6) + circ(x + 9 * d, y - 7, 2.0, PAPER, 1.4)

def save(kind, name, body):
    d = os.path.join(ROOT, kind)
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, name + ".svg"), "w") as f:
        f.write(svg(body))


# ---------------- buildings ----------------
def mine(heap, house_roof):
    cx = 33
    b = ground()
    b += poly([(41, 58), (51, 40), (62, 58)], heap, 2.2)                       # spoil heap
    b += line(46, 52, 50, 46, 1.4, "#9a9a9a")
    b += rect(3, 40, 18, 18, BROWN, 2.2)                                         # winding house
    b += poly([(2, 40), (12, 32), (22, 40)], house_roof, 2.2)
    b += rect(9, 47, 6, 11, PAPER_D, 1.6)
    b += line(cx - 9, 58, cx, 16, 3) + line(cx + 9, 58, cx, 16, 3)               # headframe legs
    b += line(cx - 5.1, 40, cx + 5.1, 40, 2.2) + line(cx - 2.6, 28, cx + 2.6, 28, 2)
    b += line(cx - 5, 18, 17, 36, 1.4)                                            # rope to the house
    b += circ(cx, 14, 6.5, PAPER, 2.2) + line(cx - 6.5, 14, cx + 6.5, 14, 1.4) + line(cx, 7.5, cx, 20.5, 1.4)
    return b

save("buildings", "coal_mine", mine(COAL, SOOT))
save("buildings", "iron_mine", mine(RUST, BROWN))
save("buildings", "copper_mine", mine(COPPER, "#4f7f72"))

q = ground()
q += poly([(4, 58), (4, 18), (18, 18), (18, 28), (30, 28), (30, 38), (42, 38), (42, 48), (60, 48), (60, 58)], STONE, 2.4)
for (x1, y1, x2, y2) in [(6, 22, 12, 20), (7, 26, 15, 22), (20, 32, 26, 30), (21, 36, 28, 32), (32, 42, 38, 40), (33, 46, 40, 42), (46, 53, 52, 51), (47, 57, 56, 52)]:
    q += line(x1, y1, x2, y2, 1.2, "#8f897a")
q += line(53, 48, 53, 22, 3) + line(53, 24, 35, 32, 2.4) + line(35, 32, 35, 40, 1.4) + rect(32, 40, 6, 5, PAPER_D, 1.6)
q += line(53, 22, 45, 28, 1.6)
q += rect(46, 40, 6, 6, PAPER_D, 1.6)
save("buildings", "limestone_quarry", q)

c = ground()
c += rect(29, 18, 7, 24, SOOT, 2.2) + rect(27, 15, 11, 5, SOOT, 2)
for x0 in (3, 24, 45):
    c += path("M%g 58 V42 A8 8 0 0 1 %g 42 V58 Z" % (x0, x0 + 16), BROWN, 2.4)
    c += path("M%g 58 V50 A3 3 0 0 1 %g 50 V58 Z" % (x0 + 5, x0 + 11), FIRE, 1.8)
c += smoke(33, 9)
save("buildings", "coke_oven", c)

bf = ground()
bf += rect(4, 26, 12, 32, STEEL_L, 2.2, 5) + rect(47, 34, 12, 24, STEEL_L, 2.2, 5)       # hot-blast stoves
bf += line(16, 38, 25, 38, 2.4) + line(47, 44, 39, 44, 2.4)
bf += poly([(21, 58), (26, 16), (38, 16), (43, 58)], SOOT, 2.6)
bf += line(23, 44, 41, 44, 2) + line(24.5, 30, 39.5, 30, 2)
bf += rect(24, 11, 16, 6, SOOT, 2.2)
bf += path("M32 1 C27 7 28 11 32 11 C36 11 37 7 32 1 Z", FIRE, 1.8) + path("M32 6 C30 9 31 11 32 11 C33 11 34 9 32 6 Z", FIRE_Y, 1)
bf += rect(29, 50, 6, 8, FIRE, 1.8)
save("buildings", "blast_furnace", bf)

sw = ground()
sw += rect(54, 14, 7, 44, SOOT, 2.2) + rect(52, 12, 11, 4, SOOT, 2)
sw += rect(4, 34, 48, 24, BROWN, 2.4)
sw += poly([(4, 34), (4, 22), (20, 34), (20, 22), (36, 34), (36, 22), (52, 34)], SOOT, 2.4)
sw += rect(24, 44, 11, 14, FIRE, 2) + line(29.5, 44, 29.5, 58, 1.2)
for x in (8, 38, 44):
    sw += rect(x, 40, 5, 5, PAPER, 1.5)
sw += smoke(56, 8, -1)
save("buildings", "steelworks", sw)

sm = ground()
sm += rect(44, 22, 9, 36, SOOT, 2.2) + rect(42, 19, 13, 4, SOOT, 2)
sm += rect(6, 40, 34, 18, BROWN, 2.4) + poly([(4, 40), (23, 28), (42, 40)], SOOT, 2.4)
sm += circ(23, 50, 4.5, FIRE, 1.8) + circ(23, 50, 2, FIRE_Y, 0)
sm += poly([(46, 58), (48, 52), (58, 52), (61, 58)], COPPER, 2) + poly([(49, 52), (51, 47), (57, 47), (58, 52)], COPPER_L, 2)
sm += smoke(46, 12)
save("buildings", "copper_smelter", sm)

rm = ground()
rm += rect(4, 34, 56, 24, BROWN, 2.4) + poly([(2, 34), (6, 26), (58, 26), (62, 34)], SOOT, 2.4)
rm += circ(20, 47, 8, STEEL_L, 2.2) + circ(44, 47, 8, STEEL_L, 2.2)
rm += circ(20, 47, 3, PAPER, 1.6) + circ(44, 47, 3, PAPER, 1.6) + line(28, 47, 36, 47, 3.5) + line(28, 47, 36, 47, 1.2, STEEL_L)
rm += rect(10, 30, 5, 3, PAPER, 1.2) + rect(48, 30, 5, 3, PAPER, 1.2)
save("buildings", "rolling_mill", rm)

wk = ground()
wk += rect(6, 34, 40, 24, BROWN, 2.4) + poly([(3, 34), (26, 17), (49, 34)], SOOT, 2.4)
wk += rect(20, 44, 12, 14, PAPER_D, 2) + rect(10, 40, 7, 7, PAPER, 1.8) + rect(35, 40, 7, 7, PAPER, 1.8)
wk += poly([(48, 58), (50, 54), (54, 54), (54, 51), (63, 51), (63, 55), (58, 55), (58, 58)], INK, 1.4)
save("buildings", "workshop", wk)

ms = ground()
ms += rect(4, 30, 46, 28, BROWN, 2.4) + poly([(2, 30), (7, 20), (47, 20), (52, 30)], SOOT, 2.4)
ms += rect(9, 36, 10, 8, PAPER, 1.8) + rect(9, 48, 10, 10, PAPER_D, 1.8)
ms += gear(42, 42, 15, 11.5, 9, STEEL_L)
ms += line(10, 14, 52, 14, 2.4) + line(10, 14, 10, 20, 1.6) + line(52, 14, 52, 20, 1.6)
save("buildings", "machine_shop", ms)

wh = ground()
wh += rect(5, 30, 54, 28, BROWN, 2.4) + poly([(3, 30), (32, 17), (61, 30)], SOOT, 2.4)
wh += rect(21, 40, 22, 18, PAPER_D, 2) + line(32, 40, 32, 58, 1.4) + line(21, 40, 43, 58, 1.2) + line(43, 40, 21, 58, 1.2)
wh += rect(46, 48, 9, 10, PAPER_DD, 1.8) + rect(8, 48, 9, 10, PAPER_DD, 1.8)
save("buildings", "warehouse", wh)


# ---------------- deposits (seen from above) ----------------
CHUNKS = [
    [(12, 40), (18, 31), (29, 33), (31, 43), (21, 49)],
    [(32, 40), (37, 30), (48, 32), (52, 42), (45, 50), (34, 48)],
    [(20, 19), (28, 12), (38, 16), (40, 26), (30, 30), (22, 27)],
    [(41, 16), (49, 14), (55, 22), (49, 28), (43, 24)],
    [(9, 24), (16, 20), (19, 27), (13, 32)],
    [(25, 49), (34, 50), (36, 57), (28, 59), (21, 55)],
    [(44, 47), (51, 46), (55, 53), (48, 57)],
]

def deposit(fill, hi, extra=""):
    b = '<ellipse cx="32" cy="36" rx="29" ry="25" fill="%s" stroke="%s" stroke-width="1.6" stroke-dasharray="3 3"/>' % (PAPER_D, INK_SOFT)
    for p in CHUNKS:
        b += poly(p, fill, 1.9)
        x0, y0 = p[0]; x1, y1 = p[1]
        b += line(x0 + 1.5, y0 - 2, x1 - 1, y1 + 2, 1.5, hi)
    return b + extra

INK_SOFT = "#6e655a"
save("deposits", "coal", deposit(COAL, COAL_L))
save("deposits", "iron_ore", deposit(RUST, "#c4725c", "".join(line(a, b_, c, d, 1.2, RUST_D) for a, b_, c, d in [(16, 42, 25, 40), (36, 38, 46, 40), (26, 21, 34, 22)])))
save("deposits", "limestone", deposit(STONE, PAPER, "".join(line(a, b_, c, d, 1.1, "#8f897a") for a, b_, c, d in [(15, 39, 24, 36), (17, 43, 26, 40), (37, 36, 46, 34), (38, 41, 48, 38), (25, 20, 34, 18)])))
save("deposits", "copper_ore", deposit(COPPER, COPPER_L, "".join(circ(x, y, 1.8, PATINA, 0.8) for x, y in [(20, 42), (41, 36), (28, 22), (47, 24), (30, 53), (50, 51), (14, 28)])))


# ---------------- resource icons ----------------
ROCK = [(10, 40), (14, 22), (30, 11), (47, 15), (56, 32), (49, 50), (30, 55), (15, 52)]
def rock(fill, hi, extra=""):
    b = poly(ROCK, fill, 3)
    b += line(20, 24, 31, 17, 3.5, hi) + line(44, 24, 49, 32, 2.5, hi)
    return b + extra

def ingot(fill, top):
    return poly([(6, 48), (15, 28), (49, 28), (58, 48)], fill, 3) + poly([(15, 28), (49, 28), (44, 17), (20, 17)], top, 3) + line(14, 41, 50, 41, 2, top)

save("resources", "coal", rock(COAL, COAL_L))
save("resources", "iron_ore", rock(RUST, "#c4725c", line(22, 40, 36, 44, 2.5, RUST_D) + line(36, 30, 44, 38, 2.5, RUST_D)))
save("resources", "limestone", rock(STONE, PAPER, line(18, 38, 30, 34, 2, "#8f897a") + line(24, 46, 40, 42, 2, "#8f897a") + line(34, 24, 44, 22, 2, "#8f897a")))
save("resources", "copper_ore", rock(COPPER, COPPER_L, circ(24, 42, 3.2, PATINA, 1.2) + circ(38, 32, 3.2, PATINA, 1.2) + circ(40, 46, 2.6, PATINA, 1.2)))
save("resources", "coke", poly(ROCK, "#6d6d72", 3) + "".join(circ(x, y, r, COAL, 1.2) for x, y, r in [(22, 28, 3.4), (36, 22, 3), (42, 36, 3.6), (26, 42, 3.2), (36, 46, 2.6), (18, 40, 2.2)]))
save("resources", "pig_iron", ingot("#565660", "#8a8a96"))
save("resources", "copper_ingot", ingot(COPPER, COPPER_L))
save("resources", "steel", rect(8, 10, 48, 11, STEEL_L, 3) + rect(8, 43, 48, 11, STEEL_L, 3) + rect(27, 21, 10, 22, STEEL, 3) + line(12, 14, 50, 14, 2, PAPER))
save("resources", "tools",
     line(12, 52, 44, 20, 7, INK) + line(12, 52, 44, 20, 4, BROWN) + poly([(36, 8), (57, 20), (52, 29), (30, 17)], STEEL_L, 3)
     + line(52, 52, 20, 20, 7, INK) + line(52, 52, 20, 20, 4, STEEL) + circ(16, 16, 8, STEEL, 3) + circ(16, 16, 3, PAPER, 2))
save("resources", "rails", rect(6, 51, 52, 8, BROWN, 3) + rect(14, 9, 36, 9, STEEL_L, 3, 2) + rect(27, 18, 10, 22, STEEL, 3) + rect(15, 40, 34, 9, STEEL_L, 3, 2))
save("resources", "machinery", gear(32, 32, 27, 20, 10, STEEL_L, PAPER))
print("art written to", os.path.abspath(ROOT))
