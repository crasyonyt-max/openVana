# openVana Server vendor logos (login screen etc.), replacing Debian's via the
# "vendor-logos" alternative. Usage: vendor-logos.py OUTDIR   (needs python3-pil, fonts-inter)
import sys
from PIL import Image, ImageDraw, ImageFont

OUT = sys.argv[1]
DARK = (14, 59, 44); GREEN = (76, 219, 154); WHITE = (240, 240, 236)
F = "/usr/share/fonts/opentype/inter/Inter-%s.otf"

def icon(size):
    s = size * 4
    im = Image.new("RGBA", (s, s), (0, 0, 0, 0)); d = ImageDraw.Draw(im); u = s / 100
    d.rounded_rectangle([0, 0, s - 1, s - 1], radius=int(26 * u), fill=DARK)
    d.ellipse([50*u-26.75*u, 56*u-26.75*u, 50*u+26.75*u, 56*u+26.75*u], outline=GREEN, width=int(7.5*u))
    pts = [(36*u, 22*u), (50*u, 54*u), (64*u, 22*u)]
    d.line(pts, fill=DARK, width=int(15*u), joint="curve")
    d.line(pts, fill=WHITE, width=int(7.5*u), joint="curve")
    for p in pts:
        d.ellipse([p[0]-3.75*u, p[1]-3.75*u, p[0]+3.75*u, p[1]+3.75*u], fill=WHITE)
    return im.resize((size, size), Image.LANCZOS)

def text_logo(h, version):
    ic = icon(int(h * 0.8))
    fs = int(h * 0.5)
    parts = [("open", ImageFont.truetype(F % "Regular", fs), WHITE),
             ("Vana", ImageFont.truetype(F % "Bold", fs), GREEN),
             (" Server", ImageFont.truetype(F % "Regular", fs), WHITE)]
    if version:
        parts.append((" 1.0", ImageFont.truetype(F % "Regular", fs), WHITE))
    tw = int(sum(f.getlength(s) for s, f, _ in parts))
    gap = int(h * 0.18)
    im = Image.new("RGBA", (ic.width + gap + tw + 4, h), (0, 0, 0, 0))
    im.paste(ic, (0, (h - ic.height) // 2), ic)
    d = ImageDraw.Draw(im); x = ic.width + gap
    asc, desc = parts[0][1].getmetrics()
    y = (h - (asc + desc)) // 2
    for s, f, c in parts:
        d.text((x, y), s, font=f, fill=c); x += f.getlength(s)
    return im

for h in (64, 128, 256):
    icon(h).save(f"{OUT}/logo-{h}.png")
    text_logo(h, False).save(f"{OUT}/logo-text-{h}.png")
    text_logo(h, True).save(f"{OUT}/logo-text-version-{h}.png")
