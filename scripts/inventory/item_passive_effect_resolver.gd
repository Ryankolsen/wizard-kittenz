class_name ItemPassiveEffectResolver
extends RefCounted

# Dispatches an equipped item's passive effect by item id, mirroring
# SpellEffectResolver's "dispatch by id" convention (Catnip Curse, Iron
# Hide, etc.) but for item passives registered via ItemInventory.equip()/
# unequip() instead of a one-shot spell cast. Unknown item ids are a
# no-op, same safety net as SpellEffectResolver's BUFF/DOT/DEBUFF dispatch.

const PASSIVE_LIFESTEAL := "lifesteal"

# Issue #459: Lifesteal-on-kill heals the caster by a percentage of the
# killing blow's damage. Fixed percentage (not stat-scaled), matching how
# SpellEffectResolver's buff amounts are fixed per-skill constants.
const LIFESTEAL_PCT := 0.15

static func passive_id_for(item_id: String) -> String:
	match item_id:
		"guardians_locket":
			return PASSIVE_LIFESTEAL
		_:
			return ""

# Called at kill time with the killing blow's damage. `caster` is the
# character earning the kill; duck-typed the same way SpellEffectResolver
# duck-types caster methods so CharacterData and any future test fake both
# work without a shared base class.
static func resolve(item_id: String, caster, damage: int) -> void:
	resolve_passive(passive_id_for(item_id), caster, damage)

# Same dispatch as resolve(), but keyed by passive id rather than item id —
# this is what ItemInventory.active_passive_ids() callers (KillRewardRouter)
# already have on hand, so they don't need to re-derive the item id.
static func resolve_passive(passive_id: String, caster, damage: int) -> void:
	match passive_id:
		PASSIVE_LIFESTEAL:
			_apply_lifesteal(caster, damage)

static func _apply_lifesteal(caster, damage: int) -> void:
	if caster == null or damage <= 0 or not caster.has_method("heal"):
		return
	caster.heal(int(ceil(damage * LIFESTEAL_PCT)))
