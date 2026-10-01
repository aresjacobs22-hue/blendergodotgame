# Builds labelled contact sheets from rendered shots.
import sys, json
from PIL import Image, ImageDraw, ImageFont, ImageOps, ImageFilter
from post import grade
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
FONT2 = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"

def vignette(im, strength=0.55):
    w, h = im.size
    mask = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(mask)
    d.ellipse([-w*0.25, -h*0.15, w*1.25, h*1.15], fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(w*0.12))
    dark = Image.new("RGB", (w, h), (0, 0, 0))
    return Image.composite(im, Image.blend(im, dark, strength), mask)

def sheet(spec):
    # spec: {"out", "title", "gray": bool, "cols": [{"label", "sub", "main", "small": [p, p]}]}
    cols = spec["cols"]
    mw, mh = Image.open(cols[0]["main"]).size
    sw, sh = (300, 400) if cols[0].get("small") else (0, 0)
    pad, top, lab = 14, 70, 64
    W = pad + len(cols) * (mw + pad)
    H = top + lab + mh + (sh + pad if sh else 0) + pad
    out = Image.new("RGB", (W, H), (12, 12, 12))
    d = ImageDraw.Draw(out)
    d.text((pad, 18), spec["title"], font=ImageFont.truetype(FONT, 34), fill=(235, 235, 235))
    for i, c in enumerate(cols):
        x = pad + i * (mw + pad)
        d.text((x, top), c["label"], font=ImageFont.truetype(FONT, 28), fill=(255, 255, 255))
        d.text((x, top + 34), c.get("sub", ""), font=ImageFont.truetype(FONT2, 18), fill=(170, 170, 170))
        im = vignette(grade(Image.open(c["main"]), spec["mood"]))
        out.paste(im, (x, top + lab))
        for j, p in enumerate(c.get("small", [])):
            sm = Image.open(p)
            if sm.size != (sw, sh):
                sm = sm.resize((sw, int(sw * sm.size[1] / sm.size[0])), Image.LANCZOS).crop((0, 0, sw, sh))
            sm = vignette(grade(sm, spec["mood"]), 0.4)
            out.paste(sm, (x + j * (sw + (mw - 2 * sw)), top + lab + mh + pad))
    out.save(spec["out"])
    print("sheet", spec["out"], out.size)

for s in json.load(open(sys.argv[1])):
    sheet(s)
