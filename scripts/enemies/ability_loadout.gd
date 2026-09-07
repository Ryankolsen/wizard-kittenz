class_name AbilityLoadout
extends RefCounted

# Per-kind ability loadout table (PRD #518 / tracer slice #533). One place
# answers "which archetypes does this enemy compose, tuned how", so giving an
# enemy a new move is a data change here rather than a new AI class.
#
# Keyed on kind AND is_boss because BossRoster reuses ROGUE_ROOMBA as the
# floor-1 Vacuum: the standard roomba keeps its own moves, the Vacuum composes
# Pull + Telegraphed charge.
#
# Exhaustive over EnemyKind, mirroring EnemyBehavior.for_kind. Kinds whose
# archetype conversion lands in later issues (#534-#545) answer with a single
# LegacyBehaviorAbility standing for "this kind's existing bespoke behavior
# already drives its moves" — the list is never empty, so the Enemy node's
# generic pump always has something to drive and never needs a per-kind branch.

static func for_enemy(kind: int, is_boss: bool) -> Array:
	if is_boss and kind == EnemyData.EnemyKind.ROGUE_ROOMBA:
		return vacuum_loadout()
	# SIR_PICKLETON is a dedicated kind (unlike ROGUE_ROOMBA, it's never
	# reused for a standard mob), so it's keyed on kind alone.
	if kind == EnemyData.EnemyKind.SIR_PICKLETON:
		return pickleton_loadout()
	if kind == EnemyData.EnemyKind.OLD_LADY_PEARL:
		return pearl_loadout()
	return [LegacyBehaviorAbility.new()]


# The Vacuum (floor 1). Pull teaches spacing, the telegraphed charge teaches
# sidestepping. Wind-ups are long relative to the player's 60 px/s walk so both
# are beatable on foot — the PRD forbids leaning on a dash the game never gave.
static func vacuum_loadout() -> Array:
	return [
		PullAbility.new(5.0, 0.9, 0.25, 0.3, 160.0, 28.0, 48.0),
		TelegraphedChargeAbility.new(6.5, 0.8, 0.35, 0.3, 140.0, 24.0),
	]


# Sir Pickleton (floor 2 / issue #536). Ambush teaches attention — keep him in
# your sights and the scare cannot land; look away and it petrifies you
# briefly. Failing the scare (or getting caught before charge maxes out)
# falls through to the telegraphed charge, teaching the sidestep as the
# fallback punish for not noticing him in time.
static func pickleton_loadout() -> Array:
	return [
		AmbushAbility.new(0.4, 0.2, 0.3, 40.0, 1.75),
		TelegraphedChargeAbility.new(6.0, 0.8, 0.35, 0.3, 130.0, 22.0),
	]


# Old Lady Pearl (floor 3 / issue #537). Summon adds forces a choice between
# clearing the cats and eating chip damage; retreat-and-fire keeps her out of
# melee entirely, so the fight is a spacing puzzle around both the cats and
# her own kept distance.
static func pearl_loadout() -> Array:
	return [
		SummonAddsAbility.new(),
		RetreatAndFireAbility.new(),
	]
