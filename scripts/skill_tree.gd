class_name SkillTree
extends RefCounted

# Directed acyclic graph of SkillNodes. The graph shape lives in the per-class
# factory (`make_mage_tree`, etc.); the runtime-mutable state is each node's
# `unlocked` flag, which is what the save layer round-trips.

var nodes: Array = []

func add_node(node: SkillNode) -> void:
	nodes.append(node)

func find(node_id: String) -> SkillNode:
	for n in nodes:
		if n.id == node_id:
			return n
	return null

func unlocked_ids() -> Array:
	var out: Array = []
	for n in nodes:
		if n.unlocked:
			out.append(n.id)
	return out

# Re-applies a saved unlocked-id set onto the freshly-built tree. Unknown ids
# are ignored so an old save against a renamed node won't crash — it just
# silently drops the stale entry.
func apply_unlocked_ids(ids: Array) -> void:
	for n in nodes:
		n.unlocked = ids.has(n.id)

func get_unlocked_spells() -> Array:
	var out: Array = []
	for n in nodes:
		if n.unlocked and n.spell != null:
			out.append(n.spell)
	return out

# Mage tree per #9: Fireball (base) -> Frost Nova (req Fireball) ->
# Arcane Surge (req Frost Nova). EffectKind values diverge so each spell is a
# distinct combat behavior (single-target damage / area / self-buff).
# Cooldowns scale with power: 0.8s / 1.5s / 4.0s. Costs are 1 skill point each
# while skill_points come from level-ups; tune once #8 + playtest data lands.
static func make_mage_tree() -> SkillTree:
	var t := SkillTree.new()
	var fireball := Spell.make("fireball", "Fireball", Spell.EffectKind.DAMAGE, 3, 0.8)
	var frost_nova := Spell.make("frost_nova", "Frost Nova", Spell.EffectKind.AREA, 4, 1.5)
	var arcane_surge := Spell.make("arcane_surge", "Arcane Surge", Spell.EffectKind.BUFF, 5, 4.0)
	t.add_node(SkillNode.make("fireball", "Fireball", fireball, [], 1))
	t.add_node(SkillNode.make("frost_nova", "Frost Nova", frost_nova, ["fireball"], 1))
	t.add_node(SkillNode.make("arcane_surge", "Arcane Surge", arcane_surge, ["frost_nova"], 1))
	return t

# Thief tree per #10: Backstab (base, single-target) -> Smoke Bomb (area, req
# Backstab) -> Shadow Step (self-buff, req Smoke Bomb). Cooldowns trade off
# power: short on Backstab so the burst feels snappy, long on Shadow Step
# because it's intended as an escape. Backstab carries a higher base power
# than Fireball — Thief leans on burst single-target rather than the Mage's
# spell-mix flexibility.
static func make_thief_tree() -> SkillTree:
	var t := SkillTree.new()
	var backstab := Spell.make("backstab", "Backstab", Spell.EffectKind.DAMAGE, 4, 1.0)
	var smoke_bomb := Spell.make("smoke_bomb", "Smoke Bomb", Spell.EffectKind.AREA, 2, 3.0)
	var shadow_step := Spell.make("shadow_step", "Shadow Step", Spell.EffectKind.BUFF, 3, 5.0)
	t.add_node(SkillNode.make("backstab", "Backstab", backstab, [], 1))
	t.add_node(SkillNode.make("smoke_bomb", "Smoke Bomb", smoke_bomb, ["backstab"], 1))
	t.add_node(SkillNode.make("shadow_step", "Shadow Step", shadow_step, ["smoke_bomb"], 1))
	return t

# Ninja tree per #10: Shuriken Throw (base, single-target) -> Blade Storm
# (area, req Shuriken) -> Vanish (self-buff, req Blade Storm). Shuriken is the
# fastest-cooldown opener in the game (0.6s) so Ninja feels relentless;
# Blade Storm has the highest area power (5) to back up "precise and
# aggressive" archetype.
static func make_ninja_tree() -> SkillTree:
	var t := SkillTree.new()
	var shuriken := Spell.make("shuriken_throw", "Shuriken Throw", Spell.EffectKind.DAMAGE, 3, 0.6)
	var blade_storm := Spell.make("blade_storm", "Blade Storm", Spell.EffectKind.AREA, 5, 2.0)
	var vanish := Spell.make("vanish", "Vanish", Spell.EffectKind.BUFF, 4, 6.0)
	t.add_node(SkillNode.make("shuriken_throw", "Shuriken Throw", shuriken, [], 1))
	t.add_node(SkillNode.make("blade_storm", "Blade Storm", blade_storm, ["shuriken_throw"], 1))
	t.add_node(SkillNode.make("vanish", "Vanish", vanish, ["blade_storm"], 1))
	return t
