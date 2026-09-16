#!/opt/homebrew/bin/python3
"""Cut generated badge art into the app's emblem files. Needs Pillow (Homebrew python3).

  emblems.py row <tier> <image>     3:1 row of divisions I, II, III -> <tier>-1.png, <tier>-2.png, <tier>-3.png
  emblems.py single <name> <image>  one badge -> <name>.png (root.png for Root)

Backgrounds are keyed out by flood fill from the edges, each badge is centred on its solid body and scaled so the
body fills 84% of a 1024 px square. Files go to the app's emblems folder and to emblems/ in this repo.
"""
import os
import sys

from PIL import Image, ImageChops, ImageDraw

OUT = [os.path.expanduser("~/Library/Application Support/Tierminal/emblems"),
       os.path.join(os.path.dirname(os.path.abspath(__file__)), "emblems")]
FILL = 0.84

def keyout(im, thresh=60):
    im = im.convert("RGBA")
    w, h = im.size
    for pt in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1), (w // 2, 0), (w // 2, h - 1), (0, h // 2), (w - 1, h // 2)]:
        if im.getpixel(pt)[3] != 0:
            ImageDraw.floodfill(im, pt, (0, 0, 0, 0), thresh=thresh)
    return im

def solid_bbox(im):
    bg = im.convert("RGB").getpixel((0, 0))
    diff = ImageChops.difference(im.convert("RGB"), Image.new("RGB", im.size, bg)).convert("L")
    mask = ImageChops.multiply(diff.point(lambda v: 255 if v > 90 else 0),
                               im.getchannel("A").point(lambda v: 255 if v > 0 else 0))
    return mask.getbbox()

def splits(im):
    w, h = im.size
    px = im.getchannel("A").load()
    prof = [sum(1 for y in range(0, h, 2) if px[x, y] > 0) for x in range(w)]
    cuts = [min(range(lo, hi), key=lambda x: (prof[x], abs(x - (lo + hi) // 2)))
            for lo, hi in ((w // 4, w // 2), (w // 2, 3 * w // 4))]
    return [(0, cuts[0]), (cuts[0], cuts[1]), (cuts[1], w)]

def finish(im, size=1024):
    bb = solid_bbox(im) or im.getbbox()
    cx, cy = (bb[0] + bb[2]) / 2, (bb[1] + bb[3]) / 2
    side = max(bb[2] - bb[0], bb[3] - bb[1]) / FILL
    box = tuple(int(round(v)) for v in (cx - side / 2, cy - side / 2, cx + side / 2, cy + side / 2))
    canvas = Image.new("RGBA", (box[2] - box[0], box[3] - box[1]), (0, 0, 0, 0))
    canvas.paste(im.crop(box), (0, 0))
    return canvas.resize((size, size), Image.LANCZOS)

def save(img, name):
    for d in OUT:
        os.makedirs(d, exist_ok=True)
        img.save(os.path.join(d, name + ".png"))
    print("wrote", name + ".png")

def main(argv):
    if len(argv) != 4 or argv[1] not in ("row", "single"):
        sys.exit(__doc__)
    src = Image.open(os.path.expanduser(argv[3]))
    if argv[1] == "single":
        keyed = keyout(src.crop(src.getbbox() or (0, 0) + src.size)) if src.mode == "RGBA" else keyout(src)
        save(finish(keyed), argv[2])
        return
    row = keyout(src)
    for i, (x0, x1) in enumerate(splits(row)):
        save(finish(row.crop((x0, 0, x1, row.height))), "%s-%d" % (argv[2], i + 1))

if __name__ == "__main__":
    main(sys.argv)
