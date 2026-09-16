#!/usr/bin/env python3
"""Rebuild the vendored brand fonts.

Downloads the upstream variable faces, instances them to the weights each
surface declares, subsets them to latin + latin-ext, and writes them into every
project. Run it after a font update or when adding a weight; the output is
committed, so a normal build never needs this or any network access.

    pip install 'fonttools[woff]'
    scripts/build_fonts.py

See docs/design-tokens.md for how each surface picks the files up.
"""

import shutil
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
UPSTREAM = "https://raw.githubusercontent.com/google/fonts/main"

# The character set: latin + latin-ext, plus the punctuation, currency and
# arrows the interfaces actually use. Anything outside it falls back.
UNICODES = ",".join([
    "U+0000-00FF", "U+0100-02AF", "U+0304", "U+0308", "U+0329", "U+0131",
    "U+0152-0153", "U+02BB-02BC", "U+02C6", "U+02DA", "U+02DC",
    "U+1E00-1E9F", "U+1EF2-1EFF", "U+2000-206F", "U+20A0-20C0", "U+2113",
    "U+2122", "U+2191", "U+2193", "U+2212", "U+2215", "U+2C60-2C7F",
    "U+A720-A7FF", "U+FEFF", "U+FFFD",
])

FLUTTER_APPS = [ROOT / "mobile" / "assets" / "fonts", ROOT / "mobile_customer" / "assets" / "fonts"]
PANEL = ROOT / "panel" / "src" / "fonts"
WEBSITE = ROOT / "website" / "src" / "fonts"
WEB_APPS = [PANEL, WEBSITE]

FAMILIES = [
    # family, upstream path, static weights for Flutter, extra axes to pin, who ships it.
    # The apps and the panel set headings and body in the reader's own UI sans, so
    # only the marketing site still carries a display and a text face.
    ("Sora", "ofl/sora/Sora%5Bwght%5D.ttf", [600, 700], {}, [WEBSITE]),
    ("Inter", "ofl/inter/Inter%5Bopsz,wght%5D.ttf", [400, 500, 600, 700], {"opsz": 14}, [WEBSITE]),
    ("JetBrainsMono", "ofl/jetbrainsmono/JetBrainsMono%5Bwght%5D.ttf", [500, 700], {},
     FLUTTER_APPS + WEB_APPS),
]
LICENCE_PATHS = {
    "Sora": "ofl/sora/OFL.txt",
    "Inter": "ofl/inter/OFL.txt",
    "JetBrainsMono": "ofl/jetbrainsmono/OFL.txt",
}


def run(*args: str) -> None:
    subprocess.run([sys.executable, "-m", *args], check=True, capture_output=True)


def fetch(path: str, destination: Path) -> None:
    with urllib.request.urlopen(f"{UPSTREAM}/{path}", timeout=60) as response:
        destination.write_bytes(response.read())


def main() -> int:
    for directory in FLUTTER_APPS + WEB_APPS:
        directory.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory() as raw:
        work = Path(raw)

        for family, upstream, weights, extra_axes, targets in FAMILIES:
            flutter_targets = [d for d in targets if d in FLUTTER_APPS]
            web_targets = [d for d in targets if d in WEB_APPS]

            variable = work / f"{family}-var.ttf"
            fetch(upstream, variable)

            licence = work / f"OFL-{family}.txt"
            fetch(LICENCE_PATHS[family], licence)
            for directory in targets:
                shutil.copy(licence, directory / licence.name)

            # Flutter: one static face per declared weight.
            for weight in weights if flutter_targets else []:
                pinned = work / f"{family}-{weight}.pinned.ttf"
                axes = [f"wght={weight}"] + [f"{k}={v}" for k, v in extra_axes.items()]
                run("fontTools.varLib.instancer", str(variable), *axes, "-o", str(pinned))

                static = work / f"{family}-{weight}.ttf"
                run("fontTools.subset", str(pinned), f"--unicodes={UNICODES}",
                    "--layout-features=*", "--notdef-outline", "--name-IDs=*",
                    "--glyph-names", f"--output-file={static}")
                for directory in flutter_targets:
                    shutil.copy(static, directory / static.name)
                print(f"  {static.name:28} {static.stat().st_size // 1024:>4} KB  → mobile apps")

            # Web: keep the weight axis, one woff2 per family.
            if not web_targets:
                continue
            ranged = work / f"{family}-Variable.pinned.ttf"
            axes = ["wght=400:700"] + [f"{k}={v}" for k, v in extra_axes.items() if k != "opsz"]
            if "opsz" in extra_axes:
                axes.append("opsz=14:32")
            run("fontTools.varLib.instancer", str(variable), *axes, "-o", str(ranged))

            woff2 = work / f"{family}-Variable.woff2"
            run("fontTools.subset", str(ranged), f"--unicodes={UNICODES}",
                "--layout-features=*", "--notdef-outline", "--name-IDs=*",
                "--flavor=woff2", f"--output-file={woff2}")
            for directory in web_targets:
                shutil.copy(woff2, directory / woff2.name)
            names = ", ".join(d.parent.parent.name for d in web_targets)
            print(f"  {woff2.name:28} {woff2.stat().st_size // 1024:>4} KB  → {names}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
