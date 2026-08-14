---
name: ios-screenshots
description: Convert raw wizard-kittenz game screenshots into App Store Connect-ready screenshots by scaling and letterboxing them to Apple's required dimensions. Use when the user wants to prepare, convert, resize, or create iOS/App Store/TestFlight screenshots, mentions the "dimensions of one or more screenshots are wrong" App Store Connect error, or has dropped new screenshots into screenshots/ that need to be made upload-ready.
---

# iOS Screenshots

Wraps `scripts/make_ios_screenshots.py`, which scales each source PNG to
fit within Apple's required canvas (preserving aspect ratio, no distortion)
and pads the remainder with a solid color to hit the exact size. Output
goes to `screenshots/ios_ready/`, leaving originals untouched.

## Apple's accepted sizes

| Device class | Portrait | Landscape |
|---|---|---|
| 6.5" | 1242x2688 | 2688x1242 |
| 6.7" | 1284x2778 | 2778x1284 |

App Store Connect only needs **one** device-class set uploaded (6.7" is
the current default it asks for); it derives the others. Don't generate
both unless the user asks.

## Workflow

1. **Check what's in `screenshots/`** — `sips -g pixelWidth -g pixelHeight screenshots/*.png`
   (or equivalent) to see current dimensions and orientation. Wizard
   Kittenz screenshots are landscape gameplay captures, so the target is
   almost always `2778x1284`.
2. **Pick pad color** — this game already renders black letterbox bars
   around the play area at these capture resolutions, so black (the
   default) blends in seamlessly. Only ask the user if a screenshot has no
   existing dark border and padding would be visually obvious.
3. **Run the script from inside `screenshots/`** (it operates on the
   current working directory, not its own location):
   ```bash
   cd screenshots
   python3 ../.claude/skills/ios-screenshots/scripts/make_ios_screenshots.py
   ```
   This processes every `*.png` in `screenshots/`, skips anything already
   at the target size, and writes results to `screenshots/ios_ready/`.
4. **Spot-check 1-2 outputs** with Read (view the image) to confirm the
   padding blends and nothing got cropped or distorted.
5. Tell the user to upload from `screenshots/ios_ready/`, not the originals.

## Script options

```bash
python3 make_ios_screenshots.py                    # all *.png in cwd
python3 make_ios_screenshots.py foo.png bar.png     # specific files
python3 make_ios_screenshots.py --target 1284x2778  # portrait 6.7" instead
python3 make_ios_screenshots.py --pad "20,20,30"    # custom pad color (R,G,B or single gray value)
python3 make_ios_screenshots.py --force             # reprocess even if already at target size
```

Requires Pillow (`python3 -c "import PIL"` to confirm it's installed).
