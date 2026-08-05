# Tome & Scroll Art Checklist

First-pass icon art for the two new reward item types introduced in issue #453 (Achievements Expansion). Unlike weapons, these aren't wired to a per-id resolver yet — see "Wired" notes per row.

## da Vinci prompt template

```
[ITEM DESCRIPTION], single fantasy item, pixel art style, white background,
centered, [ORIENTATION], chunky pixels, flat colors, minimal shading, bold dark
outline, no drop shadow, clean simple silhouette, cute RPG inventory icon --ar 1:1 --style raw
```

- **Settings:** `--ar 1:1 --style raw`
- **Background:** WHITE (flat, clean) — required for the `make-sprite` background-removal step.
- Generate one item at a time; pick the best of the returned options; drop into `images-to-be-sprites/`.

## Pipeline (3 boxes each)

- **Art** = generated in da Vinci, best picked, saved to `images-to-be-sprites/`
- **Sprite** = white background removed, transparent PNG written to `assets/sprites/<file>`
- **Wired** = actually referenced in-game. **Blocked** for both rows below until follow-up work lands: Tomes need a new `Spell.icon` field (see `scripts/ui/slot_icon_factory.gd` — spells currently render a generated placeholder disc, not real art); Scrolls need `ScrollCatalog` content to exist (deferred per #453's Out of Scope).

| Art | Sprite | Wired | Item | File | Prompt `[DESCRIPTION]` | Orientation |
|-----|--------|-------|------|------|-------------------------|-------------|
| ☐ | ☐ | ☐ (blocked — needs `Spell.icon`) | **Tome** (shared icon for Phase Tome I/II/III) | `item_tome.png` | `a thick ancient spellbook with a worn leather cover, a glowing purple rune symbol embossed on the front, a brass clasp, closed` | `resting flat with the cover facing up` |
| ☐ | ☐ | ☐ (blocked — needs `ScrollCatalog` content) | **Scroll** (generic placeholder, pending real scroll content) | `item_scroll.png` | `a rolled parchment scroll tied shut with a red ribbon and a wax seal, aged paper texture` | `resting flat, angled slightly` |
