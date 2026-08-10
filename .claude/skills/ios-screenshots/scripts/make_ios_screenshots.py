#!/usr/bin/env python3
"""
Resize game screenshots to valid App Store Connect dimensions.

Apple requires iOS screenshots to be one of:
  1242x2688, 2688x1242 (6.5" portrait/landscape)
  1284x2778, 2778x1284 (6.7" portrait/landscape)

This scales each source PNG to fit within the target canvas (preserving
aspect ratio, no distortion) and pads the remainder with a solid color
(default black) to hit the exact required dimensions.

Operates on the current working directory, not the script's own location —
run it from inside your screenshots/ folder.

Usage:
  python3 make_ios_screenshots.py                # process all *.png in cwd
  python3 make_ios_screenshots.py foo.png bar.png # process specific files
  python3 make_ios_screenshots.py --target 1284x2778 --pad "20,20,30"
"""
import argparse
import sys
from pathlib import Path

from PIL import Image

VALID_SIZES = {
    (1242, 2688), (2688, 1242),
    (1284, 2778), (2778, 1284),
}

SCRIPT_DIR = Path.cwd()
OUTPUT_DIRNAME = "ios_ready"


def parse_size(s: str) -> tuple[int, int]:
    w, h = s.lower().split("x")
    return int(w), int(h)


def parse_color(s: str) -> tuple[int, int, int]:
    parts = [int(p) for p in s.split(",")]
    if len(parts) == 1:
        return (parts[0],) * 3
    return tuple(parts)  # type: ignore[return-value]


def fit_and_pad(img: Image.Image, target_w: int, target_h: int, pad_color) -> Image.Image:
    src_w, src_h = img.size
    scale = min(target_w / src_w, target_h / src_h)
    new_w, new_h = round(src_w * scale), round(src_h * scale)
    resized = img.resize((new_w, new_h), Image.LANCZOS)

    canvas = Image.new("RGB", (target_w, target_h), pad_color)
    offset = ((target_w - new_w) // 2, (target_h - new_h) // 2)
    canvas.paste(resized, offset)
    return canvas


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("files", nargs="*", help="Specific PNG files to process (default: all *.png in this dir)")
    parser.add_argument("--target", default="2778x1284", help="Target WxH, must be a valid Apple size (default 2778x1284)")
    parser.add_argument("--pad", default="0,0,0", help="Pad color as R,G,B or single gray value (default black)")
    parser.add_argument("--out", default=OUTPUT_DIRNAME, help=f"Output subdirectory (default {OUTPUT_DIRNAME})")
    parser.add_argument("--force", action="store_true", help="Reprocess even if source already matches target size")
    args = parser.parse_args()

    target_w, target_h = parse_size(args.target)
    if (target_w, target_h) not in VALID_SIZES:
        print(f"Warning: {target_w}x{target_h} is not one of Apple's accepted sizes: {sorted(VALID_SIZES)}", file=sys.stderr)

    pad_color = parse_color(args.pad)

    out_dir = SCRIPT_DIR / args.out
    out_dir.mkdir(exist_ok=True)

    if args.files:
        sources = [Path(f) for f in args.files]
    else:
        sources = sorted(
            p for p in SCRIPT_DIR.glob("*.png")
            if p.parent == SCRIPT_DIR  # skip anything already in a subdir like ios_ready/
        )

    if not sources:
        print("No PNG files found to process.")
        return

    for src in sources:
        if not src.exists():
            print(f"SKIP  {src.name}: not found")
            continue
        img = Image.open(src)
        img = img.convert("RGB") if img.mode != "RGB" else img

        if img.size == (target_w, target_h) and not args.force:
            print(f"SKIP  {src.name}: already {target_w}x{target_h}")
            continue

        result = fit_and_pad(img, target_w, target_h, pad_color)
        dest = out_dir / src.name
        result.save(dest)
        print(f"OK    {src.name}: {img.size[0]}x{img.size[1]} -> {dest.relative_to(SCRIPT_DIR)} ({target_w}x{target_h})")


if __name__ == "__main__":
    main()
