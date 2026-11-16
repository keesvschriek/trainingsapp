"""App-icoon K: witte K op bijna zwart, in Inter Display (zelfde letter als op de Kobo).
Draai: python3 scripts/make-icons.py  (maakt android-assets/res/* en public/icons/*)"""
import os
from PIL import Image, ImageDraw, ImageFont

FONT = os.environ.get("K_FONT", "/home/claude/kostudy/app/fonts/InterDisplay-SemiBold.ttf")
INK, PAPER = (17, 17, 17, 255), (255, 255, 255, 255)
R = "android-assets/res"

def k_layer(size, letter_h, color, bg=None, shape=None):
    """Een K met hoogte letter_h (fractie van size), optisch gecentreerd."""
    S = size * 4
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    if bg is not None:
        if shape == "circle": d.ellipse([0, 0, S - 1, S - 1], fill=bg)
        elif shape == "round": d.rounded_rectangle([0, 0, S - 1, S - 1], radius=int(S * 0.22), fill=bg)
        else: d.rectangle([0, 0, S, S], fill=bg)
    # lettergrootte zo kiezen dat de K precies letter_h hoog is
    f = ImageFont.truetype(FONT, 100)
    b = f.getbbox("K")
    f = ImageFont.truetype(FONT, int(100 * letter_h * S / (b[3] - b[1])))
    b = f.getbbox("K")
    w, h = b[2] - b[0], b[3] - b[1]
    x = (S - w) / 2 - b[0] + S * 0.012  # K oogt links zwaar: iets naar rechts
    y = (S - h) / 2 - b[1]
    d.text((x, y), "K", font=f, fill=color)
    return im.resize((size, size), Image.LANCZOS)

dens = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
for name, m in dens.items():
    os.makedirs(f"{R}/mipmap-{name}", exist_ok=True)
    k_layer(int(48 * m), 0.40, PAPER, INK, "round").save(f"{R}/mipmap-{name}/ic_launcher.png")
    k_layer(int(48 * m), 0.40, PAPER, INK, "circle").save(f"{R}/mipmap-{name}/ic_launcher_round.png")
    # adaptief: voorgrond 108 dp, veilige zone 66 dp
    k_layer(int(108 * m), 0.25, PAPER).save(f"{R}/mipmap-{name}/ic_launcher_foreground.png")
    # meldingsicoon: wit op transparant
    os.makedirs(f"{R}/drawable-{name}", exist_ok=True)
    k_layer(int(24 * m), 0.72, PAPER).save(f"{R}/drawable-{name}/ic_stat_training.png")

# opstartscherm: wit met een kleine zwarte K
for root, _, files in os.walk(R):
    for fn in files:
        if fn == "splash.png":
            p = os.path.join(root, fn)
            w, h = Image.open(p).size
            s = min(w, h)
            bg = Image.new("RGB", (w, h), (255, 255, 255))
            k = k_layer(int(s * 0.36), 0.42, INK, (255, 255, 255, 255), "round")
            bg.paste(k, ((w - k.width) // 2, (h - k.height) // 2), k)
            bg.save(p)

with open(f"{R}/values/ic_launcher_background.xml", "w") as fh:
    fh.write('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <color name="ic_launcher_background">#111111</color>\n</resources>\n')

os.makedirs("public/icons", exist_ok=True)
k_layer(192, 0.40, PAPER, INK, "round").save("public/icons/icon-192.png")
k_layer(512, 0.40, PAPER, INK, "round").save("public/icons/icon-512.png")
k_layer(512, 0.30, PAPER, INK).save("public/icons/icon-maskable-512.png")
print("klaar")
