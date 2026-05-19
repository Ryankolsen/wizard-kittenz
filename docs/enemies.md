# Wizard Kittenz — Enemy Roster

All enemies were generated with Midjourney (pixel art style, white background) and processed into transparent PNGs using `tools/make_sprite.py`. Sprites live in `assets/sprites/`. Each enemy has a `_right.png` canonical sprite; `flip_h` on `Sprite2D` handles left-facing rendering at runtime.

The boss remains **The Vacuum** — a separate sprite with its own scene. The enemies below are the standard dungeon roster.

---

## Angry Pigeon

**Sprite:** `assets/sprites/angry_pigeon_right.png`

Pigeons and cats have beef. This one is massive, unhinged, and wearing a tattered cloak. Glowing red eyes. It has decided today is the day.

**Current behavior:** Contact damage. Chases the nearest player.

**Planned behavior:**
- Dive bomb attack — charges across the room in a straight line, dealing heavy damage on impact
- Leaves droppings on the floor that act as a slow zone for a few seconds
- Short detection radius but very fast chase speed once aggro'd

---

## Rogue Roomba

**Sprite:** `assets/sprites/rogue_roomba_right.png`

A possessed robot vacuum covered in cracked magical runes, sparking with dark energy. Cousin to the Vacuum Boss. It pathfinds poorly but with absolute conviction.

**Current behavior:** Contact damage. Chases the nearest player.

**Planned behavior:**
- Erratic pathfinding — bounces off walls at angles instead of steering directly, making it unpredictable
- Leaves a trail of dark energy behind it that damages players who walk through it
- Speeds up significantly at low HP (going berserk mode)

---

## Dog Knight

**Sprite:** `assets/sprites/dog_knight_right.png`

An armored Doberman in full dark spiked plate, snarling with fangs exposed, holding a half-empty bottle of mead in one gauntlet and a greatsword in the other. Battle-scarred. Slightly swaying.

**Current behavior:** Contact damage. Chases the nearest player.

**Planned behavior:**
- Tank — higher defense than standard enemies, absorbs hits before taking real damage
- Drunk charge — periodically charges in a straight line (not necessarily toward the player), crashes into walls
- The mead bottle: on death, drops a mead pickup that grants the Ale power-up effect to whoever grabs it

---

## Catnip Dealer

**Sprite:** `assets/sprites/catnip_dealer_right.png`

A shady mouse in a long trench coat and a low-tilted fedora, coat open to reveal glowing green bags of catnip pinned inside. One visible eye, shifty sideways glance. He has what you need. You don't want what he has.

**Current behavior:** Contact damage. Chases the nearest player.

**Planned behavior:**
- Ranged — throws catnip bags at players from a distance, preferring to stay out of melee range
- Catnip hit applies a random debuff (one of: confusion — reversed controls; slowness; random spell firing)
- Flees when a player gets within melee range, repositioning before throwing again

---

## Haunted Spray Bottle

**Sprite:** `assets/sprites/haunted_spray_bottle_right.png`

A possessed spray bottle floating in midair, dripping ectoplasm, angry glowing green eyes on the label, spectral wisps trailing behind it. Every cat knows the spray bottle is the ultimate threat.

**Current behavior:** Contact damage. Chases the nearest player.

**Planned behavior:**
- Ranged — fires a stream of ghostly water in a short cone ahead of it
- Wet status effect: slows movement speed for a few seconds; stacks with other slows
- Floats — ignores collision with ground-level obstacles, can pass over low terrain features

---

## Brainstorm Backlog

Enemies discussed but not yet produced. Future candidates for additional dungeon floors:

| Enemy | Vibe | Planned behavior |
|---|---|---|
| **The Cucumber** | Cats are legendarily terrified of cucumbers | Sneaks up behind the player, causes a panic debuff |
| **Yarn Golem** | Giant tangled yarn ball that's done being played with | Entangles / roots players |
| **Cardboard Box Mimic** | Looks exactly like an inviting cardboard box. It is not. | Lures cats in, snaps shut |
| **Tinfoil Mouse** | A mouse that figured out the cats' magic and made a tin foil hat | Magic-resistant, taunts |
| **Dogs in a Trenchcoat** | Three dogs stacked, pretending to be one tall enemy | Falls apart at low HP into 3 smaller dogs |
| **Empty Food Bowl** | A sentient food bowl radiating existential dread | Aura attack, drains mana |
| **Laser Wisp** | An enchanted laser pointer dot with its own will | Erratically dashes; cats feel compelled to chase it (player confusion debuff) |
| **Squirrel Ranger** | Squirrel with a tiny bow and infinite contempt | Ranged, always repositions just out of melee range |
| **The Vet's Needle** | A giant syringe with legs | Chases relentlessly, injects debuffs on hit |
| **Alarm Clock Golem** | A shrieking alarm clock construct | AoE screech, causes confusion in a radius |
| **Drunk Raccoon** | Found the catnip stash AND the ale. Barely standing. | Unpredictable movement, randomly buffs or debuffs itself |
| **The Monday** | Anthropomorphized Monday. Garfield would understand. | Aura of despair, drains XP on hit |
