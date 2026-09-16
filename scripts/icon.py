#!/opt/homebrew/bin/python3
import os
import subprocess
import sys
import tempfile

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
src = Image.open(os.path.expanduser(sys.argv[1]) if len(sys.argv) > 1 else os.path.join(ROOT, "emblems", "root.png")).convert("RGBA")
size = 1024

tile = Image.new("RGBA", (size, size), (0, 0, 0, 0))
bb = src.getbbox() or (0, 0, src.width, src.height)
badge = src.crop(bb)
scale = size * 0.98 / max(badge.size)
badge = badge.resize((int(badge.width * scale), int(badge.height * scale)), Image.LANCZOS)
tile.paste(badge, ((size - badge.width) // 2, (size - badge.height) // 2), badge)

with tempfile.TemporaryDirectory() as tmp:
    iconset = os.path.join(tmp, "AppIcon.iconset")
    os.mkdir(iconset)
    for n in (16, 32, 128, 256, 512):
        tile.resize((n, n), Image.LANCZOS).save(os.path.join(iconset, "icon_%dx%d.png" % (n, n)))
        tile.resize((n * 2, n * 2), Image.LANCZOS).save(os.path.join(iconset, "icon_%dx%d@2x.png" % (n, n)))
    os.makedirs(os.path.join(ROOT, "Resources"), exist_ok=True)
    subprocess.run(["iconutil", "-c", "icns", iconset, "-o", os.path.join(ROOT, "Resources", "AppIcon.icns")], check=True)
print("Resources/AppIcon.icns")
