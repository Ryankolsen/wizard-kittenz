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

# Single authority for "is this (kind, is_boss) pair the Vacuum?" (issue
# #567). BossRoster reuses EnemyKind.ROGUE_ROOMBA for the floor-1 Vacuum boss,
# so the standard roomba and the Vacuum share an enum value and are told
# apart only by is_boss. Before this, that fact was re-derived independently
# in three files (here, EnemyBehavior.for_kind, and VacuumBossBehavior._init);
# all three now consult this predicate instead, so a future dual-use kind (or
# a change to this one) is a one-line change, not three.
static func is_vacuum(kind: int, is_boss: bool) -> bool:
	return is_boss and kind == EnemyData.EnemyKind.ROGUE_ROOMBA


static func for_enemy(kind: int, is_boss: bool) -> Array:
	if is_vacuum(kind, is_boss):
		return vacuum_loadout()
	# SIR_PICKLETON is a dedicated kind (unlike ROGUE_ROOMBA, it's never
	# reused for a standard mob), so it's keyed on kind alone.
	if kind == EnemyData.EnemyKind.SIR_PICKLETON:
		return pickleton_loadout()
	if kind == EnemyData.EnemyKind.OLD_LADY_PEARL:
		return pearl_loadout()
	if kind == EnemyData.EnemyKind.DOG_KNIGHT:
		return dog_knight_loadout()
	if kind == EnemyData.EnemyKind.CATNIP_DEALER:
		return catnip_dealer_loadout()
	if kind == EnemyData.EnemyKind.TRASH_PANDA_TYRONE:
		return trash_panda_tyrone_loadout()
	if kind == EnemyData.EnemyKind.BIG_BRUISER_BUSTER:
		return big_bruiser_buster_loadout()
	if kind == EnemyData.EnemyKind.KARAOKE_KAREN:
		return karaoke_karen_loadout()
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


# Dog Knight (floor-1 standard mob / issue #581). The one standard-mob special
# players reliably notice today, because it's the only one with a big visible
# commitment — the migration keeps that commitment and speed exactly as they
# were (the retired DogKnightBehavior.CHARGE_COOLDOWN was 5.0s and
# CHARGE_SPEED was 140.0 px/s over a 1.0s CHARGE_DURATION, so a 1.0s commit
# over a 140.0 lane restates the same dash), while adding the uniform amber-
# to-red telegraph lane every other archetype already draws. Wind-up/fade/
# width are new legibility tuning the hand-rolled charge never had — the old
# charge fired instantly and hit on physical contact, not a drawn lane.
static func dog_knight_loadout() -> Array:
	return [
		TelegraphedChargeAbility.new(5.0, 1.0, 1.0, 0.3, 140.0, 48.0),
	]


# Catnip Dealer (floor-1 standard mob / issue #582). Composes the same
# retreat-and-fire archetype Old Lady Pearl uses, tuned to the dealer's own
# pre-migration constants and opted into the telegraph her fight leaves off —
# the catnip bag's throw now reads with the same amber-to-red tell every other
# archetype draws, rather than firing invisibly the instant range and cadence
# line up. The debuff itself and its projectile are unchanged (out of scope);
# only the kiting and the fire cadence move here.
static func catnip_dealer_loadout() -> Array:
	return [
		RetreatAndFireAbility.new(
			CatnipDealerBehavior.PREFERRED_RANGE,
			CatnipDealerBehavior.FLEE_RANGE,
			CatnipDealerBehavior.RANGE_DEADBAND,
			CatnipDealerBehavior.FIRE_INTERVAL,
			CatnipDealerBehavior.PROJECTILE_SPEED,
			CatnipDealerBehavior.PROJECTILE_RADIUS,
			CatnipDealerBehavior.PROJECTILE_COLOR,
			CatnipDealerBehavior.PROJECTILE_MAX_RANGE,
			true
		),
	]


# Trash Panda Tyrone (floor-2 standard mob / issue #571). First of two slices
# (the steal archetype + gold theft is the next one, deliberately deferred):
# for now Tyrone composes just the zone-denial disc, dropping trash-hazard
# discs to deny space and teach spacing/cornering the way the other
# archetypes teach their own counters. Defaults inherited from
# ZoneDenialAbility's own tuning — nothing here is Tyrone-specific yet.
static func trash_panda_tyrone_loadout() -> Array:
	return [
		ZoneDenialAbility.new(),
	]


# Big Bruiser Buster (floor-4 boss / issue #573). First of two slices (the
# knockback-shove archetype is the next one, deliberately deferred): for now
# Buster composes just the ground-slam ring, teaching "get outside the ring"
# as a spacing counter distinct from the disc's "don't stand here at all".
# Defaults inherited from GroundSlamAbility's own tuning — nothing here is
# Buster-specific yet.
static func big_bruiser_buster_loadout() -> Array:
	return [
		GroundSlamAbility.new(),
	]


# Karaoke Karen (floor-3 standard mob / issue #576). Completes her kit: a
# sustained cone-spray screech (facing locked at telegraph start, so flanking
# behind her is the counter) alongside the summon-adds archetype Old Lady
# Pearl already uses, unmodified — Karen's called-in help closes in while her
# screech covers the cone in front of her, so the player solves both spacing
# problems at once. SummonAddsAbility.CAP/SUMMON_COOLDOWN defaults are reused
# as-is; only the cone-spray tuning is Karen's own.
static func karaoke_karen_loadout() -> Array:
	return [
		ConeSprayAbility.new(),
		SummonAddsAbility.new(),
	]
