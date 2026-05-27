# Weapon Art Checklist — 28 Weapons

First-pass per-weapon sprites for all 4 classes. Theme: **weakest = absurd improvised junk, strongest = legendary.** Ultimate weapons come later.

## da Vinci prompt template

```
[WEAPON DESCRIPTION], single fantasy weapon item, pixel art style, white background,
centered, [ORIENTATION], chunky pixels, flat colors, minimal shading, bold dark
outline, no drop shadow, clean simple silhouette, cute RPG inventory icon --ar 1:1 --style raw
```

- **Settings:** `--ar 1:1 --style raw`
- **Background:** WHITE (flat, clean) — required for the `make-sprite` background-removal step.
- **ORIENTATION** (the engine rotates the sprite at runtime — author in this neutral rest pose, NOT the angle seen in combat):
  - Blades / wands / staffs → `lying horizontal, tip/business-end pointing right, grip on the left, drawn long to fill the frame width` (matches the ~48×12 horizontal source sprites)
  - Beers (Chonk) → `standing upright, foam on top, handle on the left` (matches the ~47×48 upright mug sprite)
  - Sanity check: open the matching existing sprite (`weapon_sword/wand/staff/mug_sprite.png`) beside your generation — if the silhouette lines up, the engine will hold it correctly.
- Generate one weapon at a time; pick the best of the 4 returned; drop into `images-to-be-sprites/`.

## Per-weapon pipeline (3 boxes each)

- **Art** = generated in da Vinci, best of 4 picked, saved to `images-to-be-sprites/`
- **Sprite** = white background removed, transparent PNG written to `assets/sprites/<file>`
- **Wired** = `ItemImageResolver` resolves this item id to its sprite in-game

Filenames are slugs of the **new name** (human-readable while generating). The item `id` stays the same (renames are display-only), so the resolver will use an **id → filename** lookup rather than deriving the path from `id`.

---

## ⚔️ Battle Kitten — blades (junk → legend)

| Art | Sprite | Wired | New name              | id (was)                  | Tier      | File                           | Prompt `[DESCRIPTION]`                                                                                   |
|-----|--------|-------|-----------------------|---------------------------|-----------|--------------------------------|----------------------------------------------------------------------------------------------------------|
| ☑   | ☑      | ☑     | **Slippery Mackerel** | `iron_sword`              | Common    | `weapon_slippery_mackerel.png` | `a shiny silver fish held by the tail like a sword, googly eyes, the worst weapon imaginable`            |
| ☑   | ☑      | ☑     | **Pointy Stick**      | `rusted_dagger`           | Common    | `weapon_pointy_stick.png`      | `a crooked sharpened twig with a leaf still on it, tiny and pathetic`                                    |
| ☑   | ☑      | ☑     | **Butter Knife**      | `shop_iron_dirk`          | Common 🛒 | `weapon_butter_knife.png`      | `a dull stubby kitchen butter knife, faintly smeared, comically harmless`                                |
| ☑   | ☑      | ☑     | **Alley-Cat Cutlass** | `silver_sword`            | Rare      | `weapon_alley_cat_cutlass.png` | `a scrappy curved cutlass forged from scrap metal, fishbone crossguard, surprisingly sharp`              |
| ☑   | ☑      | ☑     | **Tin-Knight Sabre**  | `knights_sabre`           | Rare      | `weapon_tin_knight_sabre.png`  | `a polished proper sabre with a swept guard and a little blue ribbon, gleaming`                          |
| ☑   | ☑      | ☑     | **Clawbur**           | `enchanted_blade`         | Epic      | `weapon_clawbur.png`           | `a legendary glowing sword with a translucent blue-purple rune-etched blade and a golden cat-paw pommel` |
| ☑   | ☑      | ☑     | **Catana**            | `dragonslayer_greatsword` | Epic      | `weapon_catana.png`            | `a massive glowing katana with a red-hot ember edge and a dragon-scale wrapped hilt`                     |

## 🔮 Wizard Kitten — attack magic (party tricks → cosmic)

| Art | Sprite | Wired | New name                 | id (was)              | Tier    | File                              | Prompt `[DESCRIPTION]`                                                                 |
|-----|--------|-------|--------------------------|-----------------------|---------|-----------------------------------|----------------------------------------------------------------------------------------|
| ☐   | ☐      | ☐     | **Birthday Sparkler**    | `apprentice_wand`     | Common  | `weapon_birthday_sparkler.png`    | `a single lit handheld birthday sparkler firework shedding tiny sparks`                |
| ☐   | ☐      | ☐     | **Firefly Jar**          | `novice_wand`         | Common  | `weapon_firefly_jar.png`          | `a stick with a small glass jar of glowing green fireflies tied to the end`            |
| ☐   | ☐      | ☐     | **Crackle Wand**         | `arcane_staff`        | Rare    | `weapon_crackle_wand.png`         | `a polished wand spitting little arcs of blue lightning from a crystal tip`            |
| ☐   | ☐      | ☐     | **Stormtwig Staff**      | `runed_staff`         | Rare    | `weapon_stormtwig_staff.png`      | `a gnarled dark branch crackling with glowing blue runes and static`                   |
| ☐   | ☐      | ☐     | **Comet Caller**         | `starfire_rod`        | Epic    | `weapon_comet_caller.png`         | `a sleek rod tipped with a blazing orange-yellow comet trailing fire and sparks`       |
| ☐   | ☐      | ☐     | **Wand of the Big Bang** | `voidcaller_staff`    | Epic    | `weapon_wand_of_the_big_bang.png` | `a black staff topped with a swirling purple cosmic void orb crackling with starlight` |
| ☐   | ☐      | ☐     | **Archmage's Astrolabe** | `shop_archmage_staff` | Epic 🛒 | `weapon_archmage_astrolabe.png`   | `an ornate golden staff with a radiant blue crystal ringed by tiny orbiting planets`   |

## 💤 Sleepy Kitten — healing (cozy nonsense → dream magic)

| Art | Sprite | Wired | New name                | id (was)             | Tier    | File                             | Prompt `[DESCRIPTION]`                                                                        |
|-----|--------|-------|-------------------------|----------------------|---------|----------------------------------|-----------------------------------------------------------------------------------------------|
| ☐   | ☐      | ☐     | **Mushroom-on-a-Stick** | `healing_wand`       | Common  | `weapon_mushroom_on_a_stick.png` | `a cute wand topped with a plump red-and-white spotted mushroom`                              |
| ☐   | ☐      | ☐     | **Lollipop Wand**       | `feather_wand`       | Common  | `weapon_lollipop_wand.png`       | `a glossy rainbow swirl lollipop on a white stick used as a wand`                             |
| ☐   | ☐      | ☐     | **Dreamcatcher Staff**  | `dreamcatcher_staff` | Rare    | `weapon_dreamcatcher_staff.png`  | `a wooden staff with a woven dreamcatcher hoop, dangling beads and feathers`                  |
| ☐   | ☐      | ☐     | **Cloud-Puff Wand**     | `cloud_staff`        | Rare    | `weapon_cloud_puff_wand.png`     | `a pale wand topped with a small fluffy floating white cloud`                                 |
| ☐   | ☐      | ☐     | **Warm-Milk Ladle**     | `shop_lullaby_wand`  | Rare 🛒 | `weapon_warm_milk_ladle.png`     | `a cozy wooden ladle brimming with steaming warm milk, sleepy steam wisps`                    |
| ☐   | ☐      | ☐     | **Moonbeam Scepter**    | `lullaby_scepter`    | Epic    | `weapon_moonbeam_scepter.png`    | `an ornate pastel scepter topped with a glowing crescent moon and floating Zzz symbols`       |
| ☐   | ☐      | ☐     | **Caduceus of Catnaps** | `starlight_caduceus` | Epic    | `weapon_caduceus_of_catnaps.png` | `an elegant twin-snake caduceus staff crowned with a radiant glowing star, soft dreamy light` |

## 🍺 Chonk Kitten — Jonie's beers (upright orientation)

| Art | Sprite | Wired | New name                  | id (was)             | Tier      | File                               | Prompt `[DESCRIPTION]`                                                 |
|-----|--------|-------|---------------------------|----------------------|-----------|------------------------------------|------------------------------------------------------------------------|
| ☐   | ☐      | ☐     | **Cheap Tavern Pint**     | `heavy_club`         | Common    | `weapon_cheap_tavern_pint.png`     | `a chipped clay mug of flat cheap beer with thin foam`                 |
| ☐   | ☐      | ☐     | **Wooden Tankard**        | `oak_cudgel`         | Common    | `weapon_wooden_tankard.png`        | `a plain wooden tankard with a simple handle and modest foam`          |
| ☐   | ☐      | ☐     | **Sloshing Pint Glass**   | `shop_oak_mallet`    | Common 🛒 | `weapon_sloshing_pint_glass.png`   | `a tall glass pint of golden ale, a little beer spilling over the rim` |
| ☐   | ☐      | ☐     | **Iron-Banded Stein**     | `spiked_mace`        | Rare      | `weapon_iron_banded_stein.png`     | `a sturdy wooden stein wrapped in iron bands, thick frothy foam`       |
| ☐   | ☐      | ☐     | **Hefty Stein**           | `bone_crusher`       | Rare      | `weapon_hefty_stein.png`           | `a big heavy decorated ceramic stein overflowing with foam`            |
| ☐   | ☐      | ☐     | **Mighty Keg**            | `earthshaker_hammer` | Epic      | `weapon_mighty_keg.png`            | `a giant wooden beer keg on a handle, swung like a war-hammer`         |
| ☐   | ☐      | ☐     | **Golden Chalice of Ale** | `mountain_maul`      | Epic      | `weapon_golden_chalice_of_ale.png` | `an ornate glowing golden goblet frothing with magical golden beer`    |

---

## Follow-up code changes (after art lands)

1. **Per-item image mapping** — change `scripts/inventory/item_image_resolver.gd` to look up each weapon's sprite via an `id → filename` table (the filenames above), falling back to the class-default sprite when an entry/file is missing.
2. **Renames** — update display-name strings in `scripts/inventory/item_catalog.gd` to the new names above (stats/tiers/ids unchanged).
