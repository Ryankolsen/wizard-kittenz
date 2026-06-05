# CharacterClass enum is non-zero-based — map value→name with class_name_for, never keys()[value]

`CharacterData.CharacterClass` does not start at 0. Its values are pinned explicitly:

```gdscript
enum CharacterClass {
    BATTLE_KITTEN = 6, WIZARD_KITTEN = 7, SLEEPY_KITTEN = 8, CHONK_KITTEN = 9,
    BATTLE_CAT = 10, WIZARD_CAT = 11, SLEEPY_CAT = 12, CHONK_CAT = 13,
}
```

The offset is deliberate and must not be renumbered: `KittenSaveData._migrate_character_class` treats raw ints `0–5` as the sentinel for legacy class values (MAGE..SHADOW_NINJA, since removed). Starting the current enum at 6 keeps legacy save ints from colliding with current ones, so the migration stays correct on existing player saves.

The consequence is a sharp edge: `CharacterClass.keys()` returns an 8-element array indexed `0–7` in declaration order, but a stored `character_class` holds the enum *value* (`6–13`). So **`keys()[character_class]` is always wrong** — it reads the wrong name for the low classes (`keys()[6]` is "SLEEPY_CAT", not "BATTLE_KITTEN") and runs off the end for `SLEEPY_KITTEN=8` and up, crashing with "Out of bounds get index". This bit the co-op create/join path (#337): joining multiplayer with a Sleepy/Chonk kitten or any cat crashed in `character_creation.gd` while building the lobby roster's display name.

The decision: enum value → name goes through `CharacterData.class_name_for(value)`, which resolves the declaration index via `CharacterClass.values().find(value)` before indexing `keys()`, and returns `""` for an unknown value rather than crashing. All class-name lookups route through it (`character_creation`, `pause_menu`; `character_grid.class_display_name` already used the same `values().find()` shape). Direct `keys()[enum_value]` indexing is the bug pattern and must not be reintroduced — the array index and the enum value are not the same number for this enum.
