"""Renders the supplied ShirazTyres artwork to every launcher size both apps need.

The two source files in docs/brand/source are the artwork as delivered: the mark
on a white ground, no alpha. Everything here is derived from them, so the icons
are regenerated rather than hand-cut, and re-running this after new artwork lands
is the whole update.

    python3 tools/make-icons.py

The white ground is lifted off by un-compositing it rather than by keying it out,
so an icon laid back on white is pixel-for-pixel the artwork — anti-aliased edges
and all — while the alpha left behind is a true silhouette for themed icons.
"""
import os
import numpy as np
from PIL import Image, ImageDraw

SOURCE = "docs/brand/source"


def cutout(path):
    """The artwork on transparency, trimmed to its own edges.

    Every pixel was drawn over white, so `c = c'·a + 255·(1 - a)`. Taking the
    darkest channel to be the one the artist drove to zero fixes `a`, and the
    rest is that equation solved for `c'`.
    """
    rgb = np.asarray(Image.open(path).convert("RGB"), dtype=np.float64)
    alpha = 255.0 - rgb.min(axis=2)
    # The ground was scanned at 253, not 255, and a percent of opacity left
    # everywhere would defeat the trim below.
    alpha[alpha < 8] = 0

    lit = alpha > 0
    scale = np.where(lit, alpha, 1.0)[..., None]
    colour = np.clip((rgb - (255.0 - alpha)[..., None]) * 255.0 / scale, 0, 255)

    art = Image.fromarray(
        np.dstack([np.where(lit[..., None], colour, 0), alpha[..., None]]).astype(np.uint8),
        "RGBA",
    )
    return art.crop(art.getbbox())


def placed(art, canvas, width):
    """`art` centred on a transparent square of `canvas` px, `width` px wide."""
    scaled = art.resize((round(width), max(1, round(width * art.height / art.width))), Image.LANCZOS)
    layer = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    layer.alpha_composite(scaled, ((canvas - scaled.width) // 2, (canvas - scaled.height) // 2))
    return layer


def in_safe_circle(art, diameter):
    """The widest the artwork can be and still sit inside a circle of `diameter`.

    An adaptive icon is only guaranteed to show the middle 66 of its 108dp, and
    a launcher is free to mask that to a circle — a wide lockup fitted to the
    square loses its ends the first time somebody's phone does. Measured against
    the ink rather than the bounding box, because this mark's box corners are
    empty and fitting those would leave the icon a third smaller than it needs
    to be.
    """
    ink = np.asarray(art.getchannel("A")) > 16
    ys, xs = np.nonzero(ink)
    reach = np.hypot(xs - art.width / 2, ys - art.height / 2).max()
    return art.width * (diameter / 2) / reach


def rounded(img, radius_ratio):
    px = img.size[0]
    mask = Image.new("L", (px * 4, px * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, px * 4 - 1, px * 4 - 1], radius=px * 4 * radius_ratio, fill=255)
    img.putalpha(mask.resize((px, px), Image.LANCZOS))
    return img


def on_field(art, px, colour, *, width_ratio, radius_ratio=None, opaque=False):
    base = Image.new("RGBA", (px, px), colour)
    if radius_ratio is not None:
        base = rounded(base, radius_ratio)
    base.alpha_composite(placed(art, px, px * width_ratio))
    return base.convert("RGB") if opaque else base


# The artwork carries its own colour, so both apps stand on the white ground it
# was drawn on; the technician's tyre is blue where the customer's is gold, and
# that is what tells the two apart on a phone with both installed.
FIELD = (255, 255, 255, 255)
BACKGROUND = "#FFFFFF"

APPS = {"mobile": "technician", "mobile_customer": "customer"}

ANDROID = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
IOS = [("20x20", 1), ("20x20", 2), ("20x20", 3), ("29x29", 1), ("29x29", 2), ("29x29", 3),
       ("40x40", 1), ("40x40", 2), ("40x40", 3), ("60x60", 2), ("60x60", 3),
       ("76x76", 1), ("76x76", 2), ("83.5x83.5", 2), ("1024x1024", 1)]

for app, label in APPS.items():
    art = cutout(f"{SOURCE}/{app}.png")

    res = f"{app}/android/app/src/main/res"
    for density, scale in ANDROID.items():
        os.makedirs(f"{res}/mipmap-{density}", exist_ok=True)
        legacy = round(48 * scale)
        on_field(art, legacy, FIELD, width_ratio=0.80, radius_ratio=0.22).save(
            f"{res}/mipmap-{density}/ic_launcher.png")

        # Adaptive: a 108dp canvas the launcher masks down to 66dp.
        fg = round(108 * scale)
        width = in_safe_circle(art, 66 * scale)
        placed(art, fg, width).save(f"{res}/mipmap-{density}/ic_launcher_foreground.png")

        # A themed icon is tinted from the alpha alone, so all it needs is the
        # silhouette — spoke gaps and all.
        mono = Image.new("RGBA", (fg, fg), (255, 255, 255, 0))
        mono.putalpha(placed(art, fg, width).getchannel("A"))
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
        f'    <color name="ic_launcher_background">{BACKGROUND}</color>\n</resources>\n')

    # iOS applies its own mask and refuses an icon with alpha in it.
    ios = f"{app}/ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for base, scale in IOS:
        side = round(float(base.split("x")[0]) * scale)
        on_field(art, side, FIELD, width_ratio=0.80, opaque=True).save(
            f"{ios}/Icon-App-{base}@{scale}x.png")

    # A big flat one for the docs and anywhere the app shows itself off.
    os.makedirs("docs/brand", exist_ok=True)
    on_field(art, 512, FIELD, width_ratio=0.80, radius_ratio=0.22).save(
        f"docs/brand/{label}-icon.png")
    print(app, "icons written")
