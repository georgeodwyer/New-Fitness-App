#!/usr/bin/env python3
"""Adds Strava's official brand images to the app.

Download Strava's button and logo files (developers.strava.com/guidelines: "Connect with
Strava" buttons and the "Powered by" / "Compatible with" logos), unzip them into one folder,
then run:

    python3 scripts/add_strava_assets.py path/to/strava-files

It picks the right files by Strava's file names and adds them to the asset catalog as
StravaConnectButton, PoweredByStrava and StravaCompatible, which the app uses automatically
(the plain stand-ins are only used while they're missing). The images are copied as they
are: Strava's rules don't allow changing them.
"""
import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "Kinetix/Resources/Assets.xcassets"
# Asset name → words that must all be in Strava's file name (orange button, light-background logos).
WANTED = {
    "StravaConnectButton": ["connectwith", "orange"],
    "PoweredByStrava": ["pwrdby", "horiz"],
    "StravaCompatible": ["cptblwith", "horiz"],
}


def pick(files, words):
    matches = [f for f in files if all(w in f.name.lower().replace("_", "") for w in words)]
    # Prefer the version for light backgrounds, then the PNG at the highest scale.
    matches.sort(key=lambda f: ("light" not in f.name.lower() and "orange" not in f.name.lower(),
                                f.suffix.lower() != ".png", "@3x" not in f.name, "@2x" not in f.name))
    return matches


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(1)
    files = [f for f in Path(sys.argv[1]).rglob("*") if f.suffix.lower() in (".png", ".pdf", ".svg")]
    for name, words in WANTED.items():
        matches = pick(files, words)
        if not matches:
            print(f"Not found: {name} (a file name containing {' and '.join(words)})")
            continue
        folder = ASSETS / f"{name}.imageset"
        shutil.rmtree(folder, ignore_errors=True)
        folder.mkdir(parents=True)
        best = matches[0]
        scale = "3x" if "@3x" in best.name else "2x" if "@2x" in best.name else "1x"
        target = folder / f"{name}{best.suffix.lower()}"
        shutil.copy(best, target)
        image = {"filename": target.name, "idiom": "universal"}
        if best.suffix.lower() == ".png":
            image["scale"] = scale
        contents = {"images": [image], "info": {"author": "xcode", "version": 1}}
        if best.suffix.lower() in (".pdf", ".svg"):
            contents["properties"] = {"preserves-vector-representation": True}
        (folder / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")
        print(f"Added {name} from {best.name}")


if __name__ == "__main__":
    main()
