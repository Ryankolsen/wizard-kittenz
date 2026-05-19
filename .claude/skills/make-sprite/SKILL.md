---
name: make-sprite
description: Convert a Midjourney-generated enemy image into transparent Godot sprites. Use when the user drops an image in images-to-be-sprites/, wants to add a new enemy sprite, or asks about sprite conversion.
---

# Make Sprite

## Workflow overview

1. User generates art in Midjourney using the prompt template below
2. User drops the downloaded image into `images-to-be-sprites/`
3. Run `tools/make_sprite.py` to split the 2x2 grid and remove the white background
4. Verify output in `assets/sprites/`
5. Wire up the sprite in Godot

---

## Step 1 — Midjourney Prompt Template

Use this template for all enemy sprites. Swap in the enemy name/description:

```
[ENEMY DESCRIPTION], pixel art style, white background, 2x2 sprite sheet showing left-facing and right-facing poses, top-down dungeon crawler perspective, flat colors, no shading, no drop shadows, simple silhouette, fantasy RPG enemy
```

**Midjourney settings:**
- Aspect ratio: `--ar 1:1`
- `--style raw` for flatter colors (easier background removal)

**Example — Angry Pigeon:**
```
angry pigeon standing upright in fighting stance, wearing a tattered purple cloak, red glowing eyes, pixel art style, white background, 2x2 sprite sheet showing left-facing and right-facing poses, top-down dungeon crawler perspective, flat colors, no shading, no drop shadows, simple silhouette, fantasy RPG enemy --ar 1:1 --style raw
```

**Grid convention (critical):**
```
[ right-facing ] [ left-facing  ]
[ right-facing ] [ left-facing  ]  ← alt pose (idle vs attack, etc.)
```
Top row is the primary pair used in game. Bottom row is alt poses or duplicates — still extracted but may not be used immediately.

**If the bottom row is unusable (shadows, silhouettes, garbage):** Crop to just the top half first, then run with `--grid 2x1`:
```bash
python3 -c "
from PIL import Image
img = Image.open('images-to-be-sprites/<file>.png')
img.crop((0, 0, img.width, img.height // 2)).save('/tmp/sprite_top.png')
"
python3 tools/make_sprite.py /tmp/sprite_top.png <name> --grid 2x1
```

---

## Step 2 — Drop image into the folder

Save the downloaded Midjourney image (any filename) to:
```
images-to-be-sprites/
```

---

## Step 3 — Run the conversion script

```bash
python3 tools/make_sprite.py "images-to-be-sprites/<filename>.png" <sprite_name>
```

**Options:**
```
--grid 2x2        Grid layout (default: 2x2)
--tolerance 15    White removal tolerance 0-255 (raise if white fringing remains; default: 15)
--out assets/sprites  Output directory (default: assets/sprites)
```

**Example:**
```bash
python3 tools/make_sprite.py "images-to-be-sprites/davinci_angry_pigeon.png" angry_pigeon
```

**Output files:**
```
assets/sprites/angry_pigeon_right.png      ← primary right-facing
assets/sprites/angry_pigeon_left.png       ← primary left-facing
assets/sprites/angry_pigeon_right_alt.png  ← alt pose
assets/sprites/angry_pigeon_left_alt.png   ← alt pose
```

---

## Step 4 — Verify transparency

```bash
python3 -c "
from PIL import Image
img = Image.open('assets/sprites/<name>_right.png')
px = img.load()
w, h = img.size
print('Mode:', img.mode)
print('Top-left alpha:', px[0, 0][3])   # should be 0
"
```

Alpha = 0 at corners = transparent background. The Godot/file viewer renders on white — that's normal.

---

## Step 5 — Wire up in Godot

The mob scene uses `$Sprite2D` with `flip_h` for directional facing:

```gdscript
# In mob script — set texture on ready
func _ready():
    $Sprite2D.texture = preload("res://assets/sprites/angry_pigeon_right.png")

# When facing direction changes
func face(dir: Vector2):
    $Sprite2D.flip_h = dir.x < 0
```

This means you only need `_right.png` in Godot — `flip_h` handles the left-facing version automatically. The `_left.png` file is kept as a reference but not loaded.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| White fringing around sprite edges | Rerun with `--tolerance 25` or `--tolerance 30` |
| Image not splitting cleanly | Check Midjourney gave a clean 2x2 (no watermarks, no borders) |
| Sprite looks blurry in Godot | Set import filter to **Nearest** in Godot's import panel |
| Wrong faces (left/right swapped) | Swap the `_right` and `_left` filenames, or use `flip_h = true` as default |