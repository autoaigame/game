# The face and flat beard textures of the 3D character, drawn texel by texel.
#
#   python3 art/character/faces.py <repo root>
#
# A face is 24x16 texels: the face zone of the head's texture (art/character/body.py, FACE_RECT), about
# one texel per screen pixel at the front of the head. A texel is not a colour but an index (see
# docs/character-parts.md): red = zone * 64, green = (shade + 2) * 50, alpha 255; transparent texels leave
# the skin as it is. Zones: 0 the skin (the body's colour), 1 the part's own colour (brows on a face, the
# beard on a beard), 2 the eyes (a fixed ramp). The shader draws ramp[band + shade] of the zone's ramp, so
# one face works for every skin and hair colour and stays in the palette. Shade -2 is always the darkest
# colour of the ramp and +2 always the lightest, whatever the light.
# Writes assets/character/faces/<id>.png. Plain Python: no library needed.
import os, struct, sys, zlib

ROOT = sys.argv[1] if len(sys.argv) > 1 else "."
W, H = 24, 16
KEYS = {  # char -> (zone, shade)
    "e": (2, -2),  # eye
    "w": (2, 2),  # eye white
    "b": (1, 0),  # brows, moustache: the part's colour
    "B": (1, -1),  # the same, darker
    "g": (1, 1),  # the same, lighter (old brows)
    "z": (1, -1),  # stubble
    "s": (0, -1),  # skin in shade (folds, nose, freckles)
    "S": (0, -2),  # skin in deep shade (mouth)
    "l": (0, 1),  # skin lighter (a scar)
}


def png(path, w, h, rgba):
    """A PNG with only IHDR, IDAT and IEND: no text, time or colour chunks."""
    raw = b"".join(b"\x00" + bytes(rgba[y * w * 4:(y + 1) * w * 4]) for y in range(h))

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


class Face:
    def __init__(self):
        self.px = {}

    def dot(self, x, y, c):
        assert 0 <= x < W and 0 <= y < H, (x, y)
        if c == ".":
            self.px.pop((x, y), None)
        else:
            self.px[(x, y)] = c
        return self

    def run(self, y, x0, x1, c):
        for x in range(x0, x1 + 1):
            self.dot(x, y, c)
        return self

    def sym(self, y, x0, x1, c):
        """A run on the left half and its mirror (column x <-> 23 - x)."""
        self.run(y, x0, x1, c)
        self.run(y, W - 1 - x1, W - 1 - x0, c)
        return self

    def save(self, path):
        rgba = [0] * (W * H * 4)
        for (x, y), c in self.px.items():
            zone, shade = KEYS[c]
            rgba[(y * W + x) * 4:(y * W + x) * 4 + 4] = [zone * 64, (shade + 2) * 50, 0, 255]
        png(path, W, H, rgba)


def base():
    # Eyes 2x2 at columns 7-8 and 15-16 (eyes one texel wide drop out on screen at some angles), brows
    # above with an empty row between, a nose shadow, a mouth.
    return Face().sym(1, 6, 8, "b").sym(3, 7, 8, "e").sym(4, 7, 8, "e").run(7, 11, 12, "s").run(9, 10, 13, "S")


def faces():
    f = {}
    f["face_young"] = base()
    a = Face().sym(1, 5, 8, "B").sym(3, 7, 8, "e").sym(4, 7, 8, "e")
    a.run(6, 11, 12, "s").run(7, 11, 12, "S").run(9, 9, 14, "S").sym(8, 4, 4, "s").sym(9, 4, 4, "s")
    f["face_adult"] = a
    o = Face().run(0, 8, 15, "s").sym(2, 5, 8, "g").sym(3, 6, 8, "s").sym(4, 7, 8, "e").sym(5, 6, 8, "s")
    o.run(7, 11, 12, "S").sym(8, 8, 8, "s").sym(9, 8, 8, "s").run(10, 9, 14, "S")
    f["face_old"] = o
    c = Face().sym(1, 5, 8, "B").sym(3, 7, 8, "e").sym(4, 7, 8, "e").run(6, 11, 12, "s").run(7, 11, 12, "S")
    c.run(9, 9, 14, "S")
    # A scar across the right brow and down the cheek: lighter skin edged with shade, the brow cut.
    for x, y in [(15, 0), (16, 1), (16, 2), (17, 5), (17, 6), (18, 7)]:
        c.dot(x, y, "l")
    for x, y in [(14, 0), (18, 6)]:
        c.dot(x, y, "s")
    f["face_scar"] = c
    t = Face().sym(2, 6, 8, "b").sym(3, 5, 5, "b").sym(4, 7, 8, "e").sym(5, 6, 8, "S").sym(6, 7, 7, "s")
    t.run(7, 11, 12, "s").run(10, 10, 13, "S")
    f["face_tired"] = t
    s = Face().sym(2, 5, 7, "B").sym(3, 8, 8, "B").sym(4, 7, 8, "e").sym(5, 7, 8, "e").run(7, 11, 12, "S")
    s.run(10, 10, 13, "S").sym(11, 9, 9, "S").sym(6, 9, 9, "s")
    f["face_stern"] = s
    r = Face().sym(1, 6, 8, "b").sym(3, 6, 8, "e").sym(4, 7, 8, "e").sym(3, 8, 8, "w").run(7, 11, 12, "s")
    r.run(9, 11, 12, "S").run(10, 11, 12, "s")
    f["face_round_eyes"] = r
    k = base()
    for x, y in [(5, 6), (7, 6), (6, 7), (4, 7)]:
        k.dot(x, y, "s").dot(W - 1 - x, y, "s")
    f["face_freckles"] = k
    return f


def beards():
    b = {}
    st = Face()
    for y in range(11, 16):
        st.run(y, 4 if y < 14 else 6, 19 if y < 14 else 17, "z")
    st.run(8, 9, 14, "z").sym(9, 8, 8, "z").sym(10, 8, 9, "z").run(10, 10, 13, ".")
    b["beard_stubble"] = st
    m = Face().run(8, 8, 15, "b").sym(9, 7, 8, "b").sym(10, 7, 7, "B").run(8, 11, 12, "B")
    b["beard_moustache"] = m
    return b


def main():
    out = os.path.join(ROOT, "assets/character/faces")
    os.makedirs(out, exist_ok=True)
    for name, f in list(faces().items()) + list(beards().items()):
        f.save(os.path.join(out, name + ".png"))
    print("faces:", list(faces()), "beards:", list(beards()))


main()
