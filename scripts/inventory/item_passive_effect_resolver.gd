class_name ItemPassiveEffectResolver
extends RefCounted

# Dispatches an equipped item's passive effect by item id, mirroring
# SpellEffectResolver's "dispatch by id" convention (Catnip Curse, Iron
# Hide, etc.) but for item passives registered via ItemInventory.equip()/
# unequip() instead of a one-shot spell cast. Unknown item ids are a
# no-op, same safety net as SpellEffectResolver's BUFF/DOT/DEBUFF dispatch.

const PASSIVE_LIFESTEAL := "lifesteal"
const PASSIVE_CRIT_ECHO := "crit_echo"

# Issue #459: Lifesteal-on-kill heals the caster by a percentage of the
# killing blow's damage. Fixed percentage (not stat-scaled), matching how
# SpellEffectResolver's buff amounts are fixed per-skill constants.
const LIFESTEAL_PCT := 0.15

# Issue #462: Crit Echo gives a critical hit a flat chance to not consume the
# ability's cooldown, refunding cooldown_remaining to 0 in place — a fixed
# chance (not stat-scaled), matching Lifesteal's fixed-percentage precedent.
const CRIT_ECHO_CHANCE := 0.3

static func passive_id_for(item_id: String) -> String:
	match item_id:
		"guardians_locket":
			return PASSIVE_LIFESTEAL
		"executioners_signet":
			return PASSIVE_CRIT_ECHO
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

# Called at the moment a cast's crit outcome is known, keyed by item id.
# `spell` is the Spell instance whose cooldown was just started by cast() —
# on a successful roll its cooldown_remaining is reset to 0, refunding the
# cooldown as if the cast never happened. Non-crits and unequipped callers
# never reach here (passive_id_for("") returns "", matching no branch), so
# cooldown consumption proceeds normally by default. Returns true when the
# cooldown was refunded, so callers/tests can observe the outcome.
static func resolve_on_crit(item_id: String, spell: Spell, is_crit: bool, rng: RandomNumberGenerator = null) -> bool:
	return resolve_passive_on_crit(passive_id_for(item_id), spell, is_crit, rng)

static func resolve_passive_on_crit(passive_id: String, spell: Spell, is_crit: bool, rng: RandomNumberGenerator = null) -> bool:
	match passive_id:
		PASSIVE_CRIT_ECHO:
			return _apply_crit_echo(spell, is_crit, rng)
		_:
			return false

static func _apply_crit_echo(spell: Spell, is_crit: bool, rng: RandomNumberGenerator) -> bool:
	if spell == null or not is_crit:
		return false
	var roll := rng.randf() if rng != null else randf()
	if roll < CRIT_ECHO_CHANCE:
		spell.cooldown_remaining = 0.0
		return true
	return false
