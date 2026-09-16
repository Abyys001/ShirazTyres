"""Renders the ShirazTyres mark to every launcher size both apps need.

The geometry is the same 100-unit drawing as lib/widgets/brand_logo.dart, so the
icon on the home screen and the badge inside the app are the same object.
"""
import math, os, json, shutil
from PIL import Image, ImageDraw

SS = 8  # supersample

BLOCKS, TREAD_R, TREAD_W, GROOVE_W, GROOVE_SCALE = 18, 43.0, 9.5, 12.5, 0.84
GROOVE = [
    ((68, 33), (66, 24), (52, 21), (43, 26)),
    ((43, 26), (32, 32), (32, 44), (44, 49)),
    ((44, 49), (57, 55), (69, 57), (68, 68)),
    ((68, 68), (67, 79), (51, 82), (38, 76)),
]

def bezier(p0, p1, p2, p3, n=48):
    for i in range(n + 1):
        t = i / n
        u = 1 - t
        yield (u*u*u*p0[0] + 3*u*u*t*p1[0] + 3*u*t*t*p2[0] + t*t*t*p3[0],
               u*u*u*p0[1] + 3*u*u*t*p1[1] + 3*u*t*t*p2[1] + t*t*t*p3[1])

def groove_points():
    pts = []
    for seg in GROOVE:
        for p in bezier(*seg, n=90):
            q = (50 + (p[0] - 50) * GROOVE_SCALE, 50 + (p[1] - 50) * GROOVE_SCALE)
            if not pts or q != pts[-1]:
                pts.append(q)
    return pts

def draw_mark(px, colour, box=100.0):
    """The mark alone, on transparency, in a square of `px` pixels."""
    n = px * SS
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    k = n / box
    off = (box - 100) / 2  # centre the 100-unit drawing in a larger box

    def T(p):
        return ((p[0] + off) * k, (p[1] + off) * k)

    rim = [T((50 - TREAD_R, 50 - TREAD_R)), T((50 + TREAD_R, 50 + TREAD_R))]
    step = 360 / BLOCKS
    for i in range(BLOCKS):
        a0 = i * step
        d.arc([rim[0][0], rim[0][1], rim[1][0], rim[1][1]],
              a0, a0 + step * 0.58, fill=colour, width=max(1, round(TREAD_W * k)))

    # Stamped rather than stroked: PIL's joins leave hairlines on a curve this
    # tight, and a dense run of discs is the same shape with round caps free.
    r = GROOVE_W * k / 2
    for x, y in (T(p) for p in groove_points()):
        d.ellipse([x - r, y - r, x + r, y + r], fill=colour)

    return img.resize((px, px), Image.LANCZOS)

def gradient(px, top, bottom):
    img = Image.new("RGB", (px, px))
    d = ImageDraw.Draw(img)
    for y in range(px):
        t = y / max(1, px - 1)
        d.line([(0, y), (px, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    return img.convert("RGBA")

def rounded(img, radius_ratio):
    px = img.size[0]
    mask = Image.new("L", (px * 4, px * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, px * 4 - 1, px * 4 - 1], radius=px * 4 * radius_ratio, fill=255)
    img.putalpha(mask.resize((px, px), Image.LANCZOS))
    return img

def compose(px, theme, *, mark_ratio, radius_ratio=None, opaque=False):
    base = gradient(px, theme["field_top"], theme["field_bottom"])
    if radius_ratio is not None:
        base = rounded(base, radius_ratio)
    m = round(px * mark_ratio)
    base.alpha_composite(draw_mark(m, theme["mark"]), ((px - m) // 2, (px - m) // 2))
    return base.convert("RGB") if opaque else base

THEMES = {
    "mobile_customer": {  # the motorist's app wears the light treatment
        "field_top": (255, 215, 0), "field_bottom": (251, 191, 36),
        "mark": (11, 19, 21, 255), "background": "#FFD700",
    },
    "mobile": {           # the technician's is its negative
        "field_top": (22, 35, 39), "field_bottom": (11, 19, 21),
        "mark": (255, 215, 0, 255), "background": "#0B1315",
    },
}

ANDROID = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
IOS = [("20x20", 1), ("20x20", 2), ("20x20", 3), ("29x29", 1), ("29x29", 2), ("29x29", 3),
       ("40x40", 1), ("40x40", 2), ("40x40", 3), ("60x60", 2), ("60x60", 3),
       ("76x76", 1), ("76x76", 2), ("83.5x83.5", 2), ("1024x1024", 1)]

for app, theme in THEMES.items():
    res = f"{app}/android/app/src/main/res"
    for density, scale in ANDROID.items():
        os.makedirs(f"{res}/mipmap-{density}", exist_ok=True)
        legacy = round(48 * scale)
        compose(legacy, theme, mark_ratio=0.60, radius_ratio=0.22).save(
            f"{res}/mipmap-{density}/ic_launcher.png")
        # Adaptive: 108dp canvas, art inside the 66dp safe circle.
        fg = round(108 * scale)
        layer = Image.new("RGBA", (fg, fg), (0, 0, 0, 0))
        m = round(fg * 0.52)
        layer.alpha_composite(draw_mark(m, theme["mark"]), ((fg - m) // 2, (fg - m) // 2))
        layer.save(f"{res}/mipmap-{density}/ic_launcher_foreground.png")
        mono = Image.new("RGBA", (fg, fg), (0, 0, 0, 0))
        mono.alpha_composite(draw_mark(m, (255, 255, 255, 255)), ((fg - m) // 2, (fg - m) // 2))
        mono.save(f"{res}/mipmap-{density}/ic_launcher_monochrome.png")

    os.makedirs(f"{res}/mipmap-anydpi-v26", exist_ok=True)
    adaptive = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background" />\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
        '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />\n'
        '</adaptive-icon>\n'
    )
    for name in ("ic_launcher.xml", "ic_launcher_round.xml"):
        open(f"{res}/mipmap-anydpi-v26/{name}", "w").write(adaptive)
    open(f"{res}/values/ic_launcher_background.xml", "w").write(
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
        f'    <color name="ic_launcher_background">{theme["background"]}</color>\n</resources>\n')

    ios = f"{app}/ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for base, scale in IOS:
        side = round(float(base.split("x")[0]) * scale)
        suffix = f"@{scale}x"
        compose(side, theme, mark_ratio=0.62, opaque=True).save(
            f"{ios}/Icon-App-{base}{suffix}.png")

    # A big flat lockup for the splash and anywhere the app shows itself off.
    os.makedirs("docs/brand", exist_ok=True)
    compose(512, theme, mark_ratio=0.60, radius_ratio=0.22).save(
        "docs/brand/" + ("driver" if app == "mobile_customer" else "technician") + "-icon.png")
    print(app, "icons written")
