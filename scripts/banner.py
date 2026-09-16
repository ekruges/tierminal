#!/opt/homebrew/bin/python3
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
E = os.path.join(ROOT, "emblems")
W, H = 1600, 760
BG = (20, 20, 22)
TIERS = [("iron-3", "Iron", "0"), ("bronze-3", "Bronze", "1k"), ("silver-3", "Silver", "3k"), ("gold-3", "Gold", "8k"),
         ("platinum-3", "Platinum", "20k"), ("diamond-3", "Diamond", "50k"), ("ascendant-3", "Ascendant", "120k"),
         ("immortal-3", "Immortal", "300k"), ("radiant-3", "Radiant", "750k"), ("root", "Root", "1M")]
COLORS = [(142, 142, 147), (181, 101, 45), (154, 163, 173), (224, 165, 42), (47, 182, 171), (79, 123, 232),
          (47, 180, 85), (217, 49, 95), (242, 242, 242), (217, 4, 41)]

def font(size, bold=True):
    for f in ("/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Arial.ttf",
              "/System/Library/Fonts/Helvetica.ttc"):
        try:
            return ImageFont.truetype(f, size)
        except OSError:
            continue
    return ImageFont.load_default()

im = Image.new("RGBA", (W, H), BG + (255,))
d = ImageDraw.Draw(im)
logo = Image.open(os.path.join(E, "logo.png")).convert("RGBA")
logo = logo.resize((300, 300), Image.LANCZOS)
im.paste(logo, (90, 70), logo)
wm = Image.open(os.path.join(E, "wordmark.png")).convert("RGBA")
wm = wm.resize((780, int(wm.height * 780 / wm.width)), Image.LANCZOS)
im.paste(wm, (440, 100), wm)
d.text((448, 100 + wm.height + 26), "Every command you and your AI agents run, ranked.", font=font(34, False), fill=(255, 255, 255, 170))
d.text((448, 100 + wm.height + 78), "Menu bar app for macOS", font=font(24, False), fill=(255, 255, 255, 100))

d.line([(90, 420), (W - 90, 420)], fill=(255, 255, 255, 26), width=2)
n = len(TIERS)
slot = (W - 180) / n
size = 118
for i, (fn, name, xp) in enumerate(TIERS):
    x = int(90 + slot * i + (slot - size) / 2)
    y = 452
    badge = Image.open(os.path.join(E, fn + ".png")).convert("RGBA").resize((size, size), Image.LANCZOS)
    im.paste(badge, (x, y), badge)
    f = font(21)
    tw = d.textlength(name, font=f)
    d.text((x + size / 2 - tw / 2, y + size + 14), name, font=f, fill=COLORS[i] + (255,))
    f2 = font(18, False)
    tw = d.textlength(xp + " XP", font=f2)
    d.text((x + size / 2 - tw / 2, y + size + 44), xp + " XP", font=f2, fill=(255, 255, 255, 110))
d.rectangle((0, 0, W - 1, H - 1), outline=(255, 255, 255, 20), width=2)
im.convert("RGB").save(os.path.join(ROOT, "banner.png"), optimize=True)
print("banner.png", im.size)
