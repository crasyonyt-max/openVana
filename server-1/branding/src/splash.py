# openVana Server classic splash: a late-90s style boot screen.
# Drawn at 640x480, reduced to one fixed 256-colour palette with dithering,
# then scaled up with hard pixels.
#   splash.py --assets DIR   write splash.png + bar.png for the Plymouth theme
#   splash.py                raw RGB video frames on stdout (1440x1080, 30 fps)
# Needs: python3-pil, python3-numpy, fonts-inter.
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

LW, LH = 640, 480          # "VGA" resolution
OW, OH = 1440, 1080        # output, 4:3
FPS, DUR = 30, 8.8
DARK = (14, 59, 44); GREEN = (76, 219, 154); WHITE = (240, 240, 236)
rng = np.random.default_rng(7)

# ---- sky: vertical gradient + fractal clouds ----
def noise(scale):
    g = rng.random((LH // scale + 2, LW // scale + 2))
    img = Image.fromarray((g * 255).astype(np.uint8)).resize((LW + 2 * scale, LH + 2 * scale), Image.BICUBIC)
    img = img.filter(ImageFilter.GaussianBlur(scale * 0.45))     # soft, no blocky cells
    a = np.asarray(img, dtype=np.float32)[:LH, :LW] / 255
    return (a - a.mean()) / (a.std() + 1e-6)

# continents traced as rough (lon, lat) outlines; the clouds take their shape
WORLD = {
 "north_america": [(-168,66),(-162,70),(-140,70),(-120,74),(-95,74),(-82,70),(-75,62),(-64,60),(-56,52),
   (-66,44),(-71,41),(-76,35),(-81,31),(-80,25),(-82,27),(-84,30),(-90,29),(-97,27),(-97,21),(-92,18),
   (-88,15),(-83,10),(-79,8),(-82,8),(-86,12),(-92,14),(-100,17),(-105,20),(-110,24),(-112,30),(-117,32),
   (-121,36),(-124,40),(-124,46),(-128,51),(-135,57),(-146,60),(-155,58),(-165,61)],
 "greenland": [(-55,60),(-45,60),(-20,70),(-18,78),(-30,83),(-60,82),(-72,78),(-55,70)],
 "south_america": [(-79,8),(-72,12),(-62,10),(-52,5),(-44,-2),(-35,-6),(-39,-14),(-41,-22),(-48,-26),
   (-53,-34),(-58,-38),(-65,-41),(-66,-47),(-69,-52),(-74,-53),(-73,-45),(-72,-35),(-71,-25),(-70,-18),
   (-76,-14),(-81,-6),(-80,0),(-78,4)],
 "europe": [(-10,36),(-9,43),(-2,44),(-5,48),(0,50),(5,53),(8,57),(5,62),(12,66),(20,70),(30,71),(40,68),
   (45,66),(60,68),(60,45),(48,42),(40,41),(30,41),(26,38),(22,37),(20,40),(15,38),(16,41),(12,44),(8,44),
   (3,43),(-1,37),(-6,36)],
 "uk": [(-5,50),(1,51),(0,54),(-2,57),(-5,58),(-6,55),(-5,52)],
 "asia": [(60,68),(80,73),(100,77),(130,72),(160,70),(180,66),(178,62),(162,58),(156,51),(142,53),(141,46),
   (132,43),(128,36),(121,39),(121,31),(117,24),(108,21),(106,10),(100,13),(103,1),(99,7),(97,16),(92,21),
   (88,22),(80,15),(77,8),(72,20),(66,25),(57,26),(50,30),(48,41),(60,45)],
 "arabia": [(35,30),(48,30),(56,24),(59,22),(52,16),(44,12),(42,16),(38,22),(35,28)],
 "japan": [(130,31),(135,34),(140,36),(142,40),(141,43),(139,38),(133,34)],
 "africa": [(-17,21),(-16,12),(-12,7),(-5,5),(5,5),(9,4),(9,-1),(13,-6),(12,-17),(15,-27),(18,-34),(26,-34),
   (33,-28),(35,-23),(41,-15),(40,-5),(44,0),(51,11),(43,12),(38,18),(33,28),(32,31),(20,31),(11,33),(10,37),
   (0,36),(-6,35),(-10,30),(-15,27)],
 "madagascar": [(44,-25),(47,-25),(50,-15),(49,-12),(44,-17)],
 "australia": [(114,-22),(122,-18),(130,-12),(137,-12),(142,-11),(146,-19),(153,-26),(150,-37),(141,-38),
   (135,-35),(129,-32),(115,-34)],
}
SCALE, LON0, LAT_TOP = 2.2, -136, 82          # px per degree, left edge longitude, top latitude
mask = Image.new("L", (LW * 2, LH * 2), 0); md = ImageDraw.Draw(mask)
for poly in WORLD.values():
    md.polygon([((lon - LON0) * SCALE * 2, ((LAT_TOP - lat) * SCALE + 70) * 2) for lon, lat in poly], fill=255)
mask = mask.resize((LW, LH), Image.LANCZOS).filter(ImageFilter.GaussianBlur(5))
land = np.asarray(mask, dtype=np.float32) / 255
fluff = sum(noise(s) * w for s, w in ((40, 0.5), (20, 0.3), (10, 0.2)))   # puffy edges and texture
clouds = np.clip(land * 1.25 + fluff * 0.22 - 0.3, 0, 1) ** 0.9
clouds = np.maximum(clouds, np.clip(noise(70) * 0.25 - 0.35, 0, 1) * 0.5)  # a few wisps over the oceans
shade = np.clip(clouds - np.roll(clouds, -5, axis=0), -0.3, 0.3)            # lit from above
y = np.linspace(0, 1, LH)[:, None]
top = np.array([22, 58, 158]); bottom = np.array([108, 168, 232])           # deep blue -> light sky blue
sky = top + (bottom - top) * y[..., None]
cloud_col = np.array([246, 248, 252]) + shade[..., None] * np.array([-120, -110, -70])
sky = sky * (1 - clouds[..., None] * 0.92) + cloud_col * clouds[..., None] * 0.92
SKY = Image.fromarray(sky.astype(np.uint8), "RGB")

# ---- logo + wordmark with classic hard drop shadows ----
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

def shadow_paste(base, img, x, y, off=4):
    sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
    sh.putalpha(img.getchannel("A").point(lambda a: 150 if a > 100 else 0))
    base.paste(sh, (x + off, y + off), sh)
    base.paste(img, (x, y), img)

F = "/usr/share/fonts/opentype/inter/Inter-%s.otf"
f_open = ImageFont.truetype(F % "Regular", 64); f_vana = ImageFont.truetype(F % "Bold", 64)
f_tag = ImageFont.truetype(F % "SemiBold", 26)

def text_img(parts, pad=8):
    w = int(sum(f.getlength(s) for s, f, _ in parts)) + pad * 2
    im = Image.new("RGBA", (w, 110), (0, 0, 0, 0)); d = ImageDraw.Draw(im); x = pad
    for s, f, c in parts:
        d.text((x, 10), s, font=f, fill=c); x += f.getlength(s)
    return im.crop(im.getbbox())

ICON = icon(112)
WORD = text_img([("open", f_open, WHITE), ("Vana", f_vana, GREEN)])
TAG = text_img([("Server 1.0", f_tag, WHITE)])

SPLASH = SKY.convert("RGBA")
block_w = ICON.width + 22 + WORD.width
bx = (LW - block_w) // 2; by = 150
shadow_paste(SPLASH, ICON, bx, by)
shadow_paste(SPLASH, WORD, bx + ICON.width + 22, by + (ICON.height - WORD.height) // 2 - 8)
shadow_paste(SPLASH, TAG, bx + ICON.width + 24, by + ICON.height - TAG.height - 4, off=2)
SPLASH = SPLASH.convert("RGB")

# ---- scrolling colour bar along the bottom (period-style palette cycling) ----
BAR_H = 10
stops = [DARK, GREEN, WHITE, GREEN, DARK, (20, 110, 120), (120, 220, 230), (20, 110, 120)]
def bar_row(shift):
    xs = (np.arange(LW) + shift) % LW / LW * len(stops)
    i0 = xs.astype(int) % len(stops); i1 = (i0 + 1) % len(stops); f = (xs - xs.astype(int))[:, None]
    a = np.array(stops)[i0]; b = np.array(stops)[i1]
    return (a + (b - a) * f).astype(np.uint8)

# one fixed palette for the whole clip (no palette flicker between frames)
probe = SPLASH.copy()
probe.paste(Image.fromarray(np.repeat(bar_row(0)[None], BAR_H, 0)), (0, LH - BAR_H))
PAL = probe.quantize(colors=256, method=Image.Quantize.MEDIANCUT)

if len(sys.argv) == 3 and sys.argv[1] == "--assets":
    d = sys.argv[2]
    SPLASH.quantize(palette=PAL, dither=Image.Dither.FLOYDSTEINBERG).convert("RGB") \
        .resize((LW * 2, LH * 2), Image.NEAREST).save(f"{d}/splash.png", optimize=True)
    # one seamless period of the bar; the theme scrolls copies of it
    Image.fromarray(np.repeat(bar_row(0)[None], BAR_H, 0)).resize((LW * 2, BAR_H * 2), Image.NEAREST) \
        .save(f"{d}/bar.png", optimize=True)
    Image.new("RGB", (4, 4), (0, 0, 0)).save(f"{d}/black.png")
    sys.exit(0)

out = sys.stdout.buffer
black = bytes(OW * OH * 3)
for i in range(int(DUR * FPS)):
    t = i / FPS
    if t < 0.4 or t >= 8.3:            # hard cuts, like the real thing
        out.write(black); continue
    fr = SPLASH.copy()
    fr.paste(Image.fromarray(np.repeat(bar_row(int(t * 160))[None], BAR_H, 0)), (0, LH - BAR_H))
    fr = fr.quantize(palette=PAL, dither=Image.Dither.FLOYDSTEINBERG).convert("RGB")
    out.write(fr.resize((OW, OH), Image.NEAREST).tobytes())
