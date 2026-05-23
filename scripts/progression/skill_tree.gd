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

# Snapshot accessor for UI / tests that want to iterate the graph without
# mutating `nodes` directly. Returns the live array — mutations bleed back.
func all_nodes() -> Array:
	return nodes

func is_unlocked(node_id: String) -> bool:
	var n := find(node_id)
	return n != null and n.unlocked

# Forces a node into the unlocked state without going through SkillTreeManager
# (no prereq / skill-point checks). Useful for save-restore (#46) and tests
# that need to set up a known unlock state. Unknown ids are a no-op.
func unlock(node_id: String) -> bool:
	var n := find(node_id)
	if n == null:
		return false
	n.unlocked = true
	return true

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

# Per-class skill trees (PRD #124 / issue #127). Each tree has exactly 5 nodes
# gated solely by level_required (1/3/5/8/12) — no prerequisite chains. Power
# and cooldown values are placeholders to be tuned during playtest. Cat-tier
# classes share their Kitten counterpart's tree (see GameState._build_tree_for)
# so a tier-2 upgrade preserves unlocks.
static func make_battle_kitten_tree() -> SkillTree:
	var t := SkillTree.new()
	var paw_smash := Spell.make("paw_smash", "Paw Smash", Spell.EffectKind.DAMAGE, 3, 0.8)
	# Hissy Fit (issue #129): self-damage cast cost. The 2 HP bite is small
	# enough that Battle Kitten can still afford to chain it for the burst
	# damage payoff; tuning happens in playtest.
	var hissy_fit := Spell.make("hissy_fit", "Hissy Fit", Spell.EffectKind.DAMAGE, 5, 1.5, 2)
	var fur_missile := Spell.make("fur_missile", "Fur Missile", Spell.EffectKind.DAMAGE, 7, 1.8)
	var cat_nap := Spell.make("cat_nap", "Cat Nap", Spell.EffectKind.AREA, 6, 3.0)
	var feral_frenzy := Spell.make("feral_frenzy", "Feral Frenzy", Spell.EffectKind.AREA, 10, 5.0)
	t.add_node(SkillNode.make("paw_smash", "Paw Smash", paw_smash, [], 1, 1, "Smacks a single enemy with a powerful paw."))
	t.add_node(SkillNode.make("hissy_fit", "Hissy Fit", hissy_fit, [], 1, 3, "Furious scratch burst. Costs 2 HP to cast."))
	t.add_node(SkillNode.make("fur_missile", "Fur Missile", fur_missile, [], 1, 5, "Launches a spinning fur-ball at one enemy."))
	t.add_node(SkillNode.make("cat_nap", "Cat Nap", cat_nap, [], 1, 8, "A relaxed swipe that hits all nearby enemies."))
	t.add_node(SkillNode.make("feral_frenzy", "Feral Frenzy", feral_frenzy, [], 1, 12, "Unleashes chaos on all surrounding enemies."))
	return t

static func make_wizard_kitten_tree() -> SkillTree:
	var t := SkillTree.new()
	# mp_cost tiers (issue #177): early 2-3 / mid 4-6 / powerful 7-10. All values
	# fit under base_max_mp_for(WIZARD_KITTEN, 1) == 10 so a fresh wizard can
	# cast any unlocked spell from level 1 (within unlock gating).
	var hairball_hex := Spell.make("hairball_hex", "Hairball Hex", Spell.EffectKind.DAMAGE, 3, 0.8, 0, 2)
	var catnip_curse := Spell.make("catnip_curse", "Catnip Curse", Spell.EffectKind.BUFF, 4, 3.0, 0, 4)
	var whisker_bolt := Spell.make("whisker_bolt", "Whisker Bolt", Spell.EffectKind.DAMAGE, 6, 1.2, 0, 5)
	var litter_storm := Spell.make("litter_storm", "Litter Storm", Spell.EffectKind.AREA, 5, 2.5, 0, 6)
	var arcane_purr := Spell.make("arcane_purr", "Arcane Purr", Spell.EffectKind.DAMAGE, 10, 4.0, 0, 8)
	t.add_node(SkillNode.make("hairball_hex", "Hairball Hex", hairball_hex, [], 1, 1, "Lobs a magical hairball at one enemy."))
	t.add_node(SkillNode.make("catnip_curse", "Catnip Curse", catnip_curse, [], 1, 3, "Boosts your own combat power temporarily."))
	t.add_node(SkillNode.make("whisker_bolt", "Whisker Bolt", whisker_bolt, [], 1, 5, "Fires a crackling whisker bolt at one enemy."))
	t.add_node(SkillNode.make("litter_storm", "Litter Storm", litter_storm, [], 1, 8, "Rains litter down on all nearby enemies."))
	t.add_node(SkillNode.make("arcane_purr", "Arcane Purr", arcane_purr, [], 1, 12, "Channels pure arcane energy into one devastating blast."))
	return t

static func make_sleepy_kitten_tree() -> SkillTree:
	var t := SkillTree.new()
	# mp_cost tiers (issue #177): early 2-3 / mid 4-6 / powerful 7-10. All values
	# fit under base_max_mp_for(SLEEPY_KITTEN, 1) == 10 so a fresh sleepy can
	# cast any unlocked spell from level 1 (within unlock gating).
	var fuzzy_warmth := Spell.make("fuzzy_warmth", "Fuzzy Warmth", Spell.EffectKind.SMART_HEAL, 3, 1.5, 0, 2)
	var cozy_aura := Spell.make("cozy_aura", "Cozy Aura", Spell.EffectKind.PARTY_BUFF, 0, 4.0, 0, 4)
	var warm_blanket := Spell.make("warm_blanket", "Warm Blanket", Spell.EffectKind.AOE_HEAL, 5, 2.5, 0, 5)
	var regen_snooze := Spell.make("regen_snooze", "Regen Snooze", Spell.EffectKind.GROUP_REGEN, 0, 3.5, 0, 6)
	var nap_of_the_gods := Spell.make("nap_of_the_gods", "Nap of the Gods", Spell.EffectKind.AOE_HEAL, 12, 6.0, 0, 8)
	t.add_node(SkillNode.make("fuzzy_warmth", "Fuzzy Warmth", fuzzy_warmth, [], 1, 1, "Heals the most wounded ally nearby, or yourself if alone."))
	t.add_node(SkillNode.make("cozy_aura", "Cozy Aura", cozy_aura, [], 1, 3, "Wraps nearby allies in a cozy aura, boosting defense and magic resistance for 15 seconds."))
	t.add_node(SkillNode.make("warm_blanket", "Warm Blanket", warm_blanket, [], 1, 5, "A cozy blanket that heals all nearby allies."))
	t.add_node(SkillNode.make("regen_snooze", "Regen Snooze", regen_snooze, [], 1, 8, "The party curls up for a cat-nap, regenerating HP over time."))
	t.add_node(SkillNode.make("nap_of_the_gods", "Nap of the Gods", nap_of_the_gods, [], 1, 12, "A divine slumber that restores a large amount of HP to all nearby allies."))
	return t

static func make_chonk_kitten_tree() -> SkillTree:
	var t := SkillTree.new()
	var chonk_taunt := Spell.make("chonk_taunt", "Chonk Taunt", Spell.EffectKind.TAUNT, 0, 5.0)
	var belly_flop := Spell.make("belly_flop", "Belly Flop", Spell.EffectKind.AREA, 4, 2.5)
	var sit_on_it := Spell.make("sit_on_it", "Sit On It", Spell.EffectKind.DAMAGE, 7, 1.5)
	var hairball_horrors := Spell.make("hairball_horrors", "Hairball Horrors", Spell.EffectKind.AREA, 6, 3.5)
	var maximum_chonk := Spell.make("maximum_chonk", "Maximum Chonk", Spell.EffectKind.BUFF, 8, 6.0)
	t.add_node(SkillNode.make("chonk_taunt", "Chonk Taunt", chonk_taunt, [], 1, 1, "Draws all enemy attention with your impressive mass."))
	t.add_node(SkillNode.make("belly_flop", "Belly Flop", belly_flop, [], 1, 3, "Drops your full weight on nearby enemies."))
	t.add_node(SkillNode.make("sit_on_it", "Sit On It", sit_on_it, [], 1, 5, "Sits on a single enemy with crushing force."))
	t.add_node(SkillNode.make("hairball_horrors", "Hairball Horrors", hairball_horrors, [], 1, 8, "Scatters hairballs across the area."))
	t.add_node(SkillNode.make("maximum_chonk", "Maximum Chonk", maximum_chonk, [], 1, 12, "Reaches peak chonkiness, boosting all stats."))
	return t

# DEPRECATED — pre-PRD-#124 archetype-shaped trees. Retained only so legacy
# tests / save migration shims still resolve `find("fireball")` etc. New code
# should call the per-Kitten factories above; GameState._build_tree_for routes
# all 8 class values to those.
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
