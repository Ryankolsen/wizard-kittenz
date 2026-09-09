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
	if kind == EnemyData.EnemyKind.LAST_CALL_LARRY:
		return larry_loadout()
	if kind == EnemyData.EnemyKind.THE_BOUNCER:
		return the_bouncer_loadout()
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


# Trash Panda Tyrone (floor-2 standard mob / issues #571 + #572). Complete:
# zone-denial drops trash-hazard discs to deny space and teach spacing/
# cornering, and steal grabs the player's gold and flees, teaching priority —
# corner him before he escapes, since the theft is only undone by killing
# him. Defaults inherited from each archetype's own tuning — nothing here is
# Tyrone-specific yet.
static func trash_panda_tyrone_loadout() -> Array:
	return [
		ZoneDenialAbility.new(),
		StealAbility.new(),
	]


# Big Bruiser Buster (floor-4 boss / issues #573 + #574). Complete: ground
# slam teaches "get outside the ring" as a spacing counter distinct from the
# disc's "don't stand here at all", and knockback shove teaches "don't stand
# in his face" — fighting at range is the counter to both. Defaults inherited
# from each archetype's own tuning — nothing here is Buster-specific yet.
static func big_bruiser_buster_loadout() -> Array:
	return [
		GroundSlamAbility.new(),
		KnockbackShoveAbility.new(),
	]


# Last Call Larry (floor-6 boss / issue #575). Zone denial is Tyrone's
# archetype reused unchanged, tuned to more/longer-lived bottle puddles so
# the safe floor genuinely closes in as the fight drags on (shorter cooldown,
# longer hazard duration, a higher cap than Tyrone's defaults). Enrage is the
# fight's other half: once Larry drops low he speeds up and hits harder, so
# outlasting the shrinking floor without bursting him down first gets
# punished twice over. Enrage is deliberately rare across the roster --
# see AbilityLoadout.for_enemy's exhaustiveness and
# test_enemy_behavior.gd's roster-constraint test -- DJ Dubstep is the only
# other planned user (issue #579), and no third kind may ever compose it.
static func larry_loadout() -> Array:
	return [
		ZoneDenialAbility.new(
			4.0,                        # cooldown_seconds: shorter than Tyrone's 6.0
			0.7, 0.2, 0.3,              # windup/commit/fade: unchanged from Tyrone's
			36.0,                       # zone_radius: unchanged from Tyrone's
			6.0,                        # hazard_duration: longer than Tyrone's 4.0
			0.35, 4.0, 32.0,            # slow/damage/radius: unchanged from Tyrone's
			Color(0.85, 0.65, 0.15, 0.45),  # amber bottle-puddle tint
			5,                          # cap: more puddles alive at once than Tyrone's 3
			90.0                        # placement_radius: unchanged from Tyrone's
		),
		EnrageAbility.new(),
	]


# The Bouncer (floor-7 boss / issues #577 + #578). Complete: shielded front is
# the roster's only directional weakness -- getting behind him is the whole
# fight -- and knockback shove is Buster's archetype reused unmodified with
# the Bouncer's own tuning: harder (more displacement) and more frequent
# (shorter cooldown) than Buster's defaults, because the shove is what keeps
# pushing the player back around to the shielded front, so the flank has to
# be re-earned. Defaults inherited from ShieldedFrontAbility's own tuning --
# nothing there is Bouncer-specific yet.
static func the_bouncer_loadout() -> Array:
	return [
		ShieldedFrontAbility.new(),
		KnockbackShoveAbility.new(
			2.5,   # cooldown_seconds: shorter than Buster's default 4.0
			0.35, 0.15, 0.2,  # windup/commit/fade: unchanged from Buster's
			70.0,  # melee_range: unchanged from Buster's
			130.0  # knockback_distance: harder than Buster's default 90.0
		),
	]
