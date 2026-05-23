#!/usr/bin/env python3
"""
Convert a Midjourney sprite sheet into individual transparent PNGs ready for Godot.

Usage:
    python3 tools/make_sprite.py <image_path> <sprite_name> [--grid NxM] [--tolerance N] [--bg white|black]

Examples:
    python3 tools/make_sprite.py images-to-be-sprites/pigeon.png angry_pigeon
    python3 tools/make_sprite.py images-to-be-sprites/pigeon.png angry_pigeon --grid 2x2 --tolerance 20
    python3 tools/make_sprite.py images-to-be-sprites/catnip.png catnip --grid 1x1 --bg black
"""

import sys
import argparse
from pathlib import Path
from PIL import Image


def remove_background(img: Image.Image, tolerance: int = 15, bg: str = "white") -> Image.Image:
    """Flood-fill from border corners to remove background. Interior pixels are protected."""
    from collections import deque
    img = img.convert("RGBA")
    pixels = img.load()
    w, h = img.size

    def is_bg(x, y):
        r, g, b, a = pixels[x, y]
        if bg == "black":
            return r <= tolerance and g <= tolerance and b <= tolerance
        return r >= 255 - tolerance and g >= 255 - tolerance and b >= 255 - tolerance

    visited = set()
    queue = deque()
    for x in range(w):
        for y in (0, h - 1):
            if is_bg(x, y) and (x, y) not in visited:
                visited.add((x, y))
                queue.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if is_bg(x, y) and (x, y) not in visited:
                visited.add((x, y))
                queue.append((x, y))

    while queue:
        x, y = queue.popleft()
        r, g, b, _ = pixels[x, y]
        pixels[x, y] = (r, g, b, 0)
        for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and (nx, ny) not in visited and is_bg(nx, ny):
                visited.add((nx, ny))
                queue.append((nx, ny))

    return img


def autocrop(img: Image.Image, padding: int = 2) -> Image.Image:
    bbox = img.getbbox()
    if bbox is None:
        return img
    left = max(0, bbox[0] - padding)
    top = max(0, bbox[1] - padding)
    right = min(img.width, bbox[2] + padding)
    bottom = min(img.height, bbox[3] + padding)
    return img.crop((left, top, right, bottom))


def split_grid(img: Image.Image, cols: int, rows: int) -> list[Image.Image]:
    w, h = img.size
    cw, ch = w // cols, h // rows
    cells = []
    for row in range(rows):
        for col in range(cols):
            box = (col * cw, row * ch, (col + 1) * cw, (row + 1) * ch)
            cells.append(img.crop(box))
    return cells


GRID_LABELS = {
    (2, 2): ["right", "left", "right_alt", "left_alt"],
    (2, 1): ["right", "left"],
    (1, 2): ["right", "left"],
    (1, 4): ["right", "left", "right_alt", "left_alt"],
    (4, 1): ["right", "left", "right_alt", "left_alt"],
    (1, 1): ["sprite"],
}


def main():
    parser = argparse.ArgumentParser(description="Convert sprite sheet to individual transparent PNGs")
    parser.add_argument("image", help="Path to the source image")
    parser.add_argument("name", help="Base sprite name (e.g. angry_pigeon)")
    parser.add_argument("--grid", default="2x2", help="Grid layout, e.g. 2x2, 1x4 (default: 2x2)")
    parser.add_argument("--tolerance", type=int, default=15, help="Background removal tolerance 0-255 (default: 15)")
    parser.add_argument("--bg", default="white", choices=["white", "black"], help="Background color to remove (default: white)")
    parser.add_argument("--size", type=int, default=48, help="Fit sprite within this pixel box (default: 48). Set 0 to skip resize.")
    parser.add_argument("--out", default="assets/sprites", help="Output directory (default: assets/sprites)")
    args = parser.parse_args()

    cols, rows = map(int, args.grid.lower().split("x"))
    src = Path(args.image)
    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    img = Image.open(src)
    print(f"Source: {src.name}  {img.size}  mode={img.mode}  grid={cols}x{rows}  bg={args.bg}")

    cells = split_grid(img, cols, rows)
    labels = GRID_LABELS.get((cols, rows), [f"frame_{i}" for i in range(len(cells))])

    saved = []
    for i, cell in enumerate(cells):
        label = labels[i] if i < len(labels) else f"frame_{i}"
        cell = remove_background(cell, args.tolerance, args.bg)
        cell = autocrop(cell)
        if args.size > 0:
            scale = args.size / max(cell.width, cell.height)
            cell = cell.resize((round(cell.width * scale), round(cell.height * scale)), Image.LANCZOS)
        out_path = out_dir / f"{args.name}_{label}.png"
        cell.save(out_path)
        saved.append(out_path)
        print(f"  Saved {out_path}  ({cell.size[0]}x{cell.size[1]})")

    print(f"\nDone. {len(saved)} sprites written to {out_dir}/")


if __name__ == "__main__":
    main()
