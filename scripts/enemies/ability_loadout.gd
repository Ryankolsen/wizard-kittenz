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
	if kind == EnemyData.EnemyKind.DJ_DUBSTEP:
		return dj_dubstep_loadout()
	if kind == EnemyData.EnemyKind.WARDEN_WRETCHED:
		return warden_wretched_loadout()
	if kind == EnemyData.EnemyKind.ROGUE_ROOMBA:
		# is_vacuum already claimed the boss-flagged case above, so this only
		# ever runs for the standard mob.
		return rogue_roomba_loadout()
	if kind == EnemyData.EnemyKind.KARAOKE_KAREN:
		return karaoke_karen_loadout()
	if kind == EnemyData.EnemyKind.ANGRY_PIGEON:
		return angry_pigeon_loadout()
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


# DJ Dubstep (floor-9 boss / issue #579). His shockwave rings land on a fixed,
# steady tempo (BeatLockedSlamAbility) rather than a free-running cooldown, so
# the interval is something a player can actually learn and dance through.
# Enrage is Larry's archetype reused unmodified: once Dubstep drops low, his
# own move speed and damage spike exactly the way Larry's do, and separately
# (inside BeatLockedSlamAbility itself) his beat speeds up to the tuned
# enraged interval at the same HP threshold -- "same dance, faster" rather
# than a different move replacing the slam. The enraged interval (2.2s) still
# clears the escapability floor: windup (0.4s) + a 60 px/s walker crossing the
# ring's 90px max radius (1.5s) = 1.9s, comfortably under the 2.2s beat.
# Dubstep is the second and final planned enrage user (see the roster-
# constraint test in test_enemy_behavior.gd) -- no third kind may compose it.
static func dj_dubstep_loadout() -> Array:
	return [
		BeatLockedSlamAbility.new(
			3.0,   # interval_seconds: the base tempo the player learns
			2.2,   # enraged_interval_seconds: shortened, still escapable
			0.3,   # enrage_hp_fraction: matches EnrageAbility's own threshold below
			0.4,   # windup_seconds
			1.0,   # commit_seconds
			0.2,   # fade_seconds
			90.0,  # max_radius
			22.0   # band_width
		),
		EnrageAbility.new(),
	]


# Warden Wretched (floor-10 boss / issue #580). The two archetypes already
# exist -- Pull from the tracer slice (#533), zone denial from Tyrone's
# slice (#571) -- so this loadout is composition and tuning only, exactly
# the claim PRD #518 makes: adding a boss is naming two archetypes and a set
# of numbers, not a new AI class.
#
# The trap is the two firing in sequence, not just coincidentally overlapping:
# hazards accrue on a short cadence (3.0s cooldown, the shortest of any
# zone-denial user) so puddles are already dotting the floor well before the
# pull's own longer cooldown (7.0s) elapses. The pull's 1.0s wind-up gives a
# 60 px/s walker double the margin to clear its 26px-wide tether (matching
# every other Pull/charge user's escapability margin), and its committed
# hazard's 5.0s lingering duration comfortably outlasts the gap to the pull's
# own commit, so the first puddle laid is still live when the tether drags
# the player across it. Reach is the longest of any Pull user (see
# enemy_data.gd's stat-table comment: "the pull needs the longest reach") so
# the tether can span the whole puddle field rather than clipping short of
# it, and pull_distance is longer than the Vacuum's so a caught player is
# dragged across a hazard rather than stopping at its edge.
static func warden_wretched_loadout() -> Array:
	return [
		PullAbility.new(
			7.0,    # cooldown_seconds: slower than the Vacuum's 5.0, giving
			        # the floor time to fill between pulls
			1.0,    # windup_seconds: a full second to read and break the tether
			0.3,    # commit_seconds
			0.3,    # fade_seconds
			220.0,  # max_reach: longest of any Pull user, spans the puddle field
			26.0,   # tether_width
			60.0    # pull_distance: longer than the Vacuum's 48.0, far enough
			        # to cross a hazard rather than stop at its edge
		),
		ZoneDenialAbility.new(
			3.0,                           # cooldown_seconds: shortest of the
			                               # three zone-denial users, so hazards
			                               # are already down before the pull fires
			0.6, 0.2, 0.3,                 # windup/commit/fade
			34.0,                          # zone_radius
			5.0,                           # hazard_duration: between Tyrone's
			                               # 4.0 and Larry's 6.0
			0.35, 4.0, 32.0,               # slow/damage/radius: unchanged defaults
			Color(0.5, 0.15, 0.55, 0.45),  # violet puddle tint, distinct from
			                               # Tyrone's default and Larry's amber
			4,                             # cap: distinct from Tyrone's 3 and Larry's 5
			110.0                          # placement_radius: wider spread than
			                               # Tyrone's/Larry's 90.0
		),
	]


# Rogue Roomba (floor-1 standard mob / issue #584). Retires the hand-rolled
# damage trail and one-shot berserk onto the shared archetypes -- the trail
# was the clearest untelegraphed mechanic in the game (a FloorHazard strip
# with no tell at all), so zone denial's draw-before-persist disc fixes that
# for free; berserk is RogueRoombaBehavior's own precedent for enrage, so this
# migration is the generalisation completing its own origin story.
#
# The retired RogueRoombaBehavior declared (values read off it before
# deletion, restated here rather than retuned):
#   TRAIL_INTERVAL = 0.3s, TRAIL_DURATION = 2.0s, TRAIL_DAMAGE_PER_SEC = 3.0,
#   TRAIL_RADIUS = 20.0px, TRAIL_COLOR = Color(0.7, 0.4, 0.4, 0.4)
#   BERSERK_HP_FRACTION = 0.3, BERSERK_SPEED_MULTIPLIER = 1.5
# (no damage multiplier existed on the old berserk, so enrage's damage
# multiplier is pinned to 1.0 here -- attack is untouched, matching the
# retired behavior exactly).
#
# Placement radius is pinned to 0.0: the old trail always dropped directly
# under the roomba (hazard.global_position = global_position, no offset), and
# ZoneDenialAbility.roll_zone_origin rolls its offset in [0, placement_radius]
# regardless of angle, so 0.0 reproduces "always exactly here" deterministically.
#
# Cadence-vs-legibility tension (flagged per the issue, not silently
# resolved): TRAIL_INTERVAL's 0.3s cooldown is far denser than any other
# zone-denial consumer's (Tyrone 6.0s, Larry 4.0s). A real disc telegraph
# needs a nonzero wind-up to read as amber-to-red at all, so the true
# steady-state gap between hazards is cooldown + windup + commit + fade, not
# a bare 0.3s -- restating TRAIL_INTERVAL as the *cooldown* value (rather than
# silently stretching it to make the full cycle equal 0.3s, which would be a
# retune the issue puts out of scope) means the roomba's trail now drops at
# roughly half its old real-world density once the minimal legible telegraph
# (0.15s windup / 0.05s commit / 0.1s fade below) is added on top. See this
# issue's final report for the explicit flag -- resolving the tension either
# way is a tuning decision left to a follow-up, not this migration.
static func rogue_roomba_loadout() -> Array:
	return [
		ZoneDenialAbility.new(
			0.3,                            # cooldown_seconds: retired TRAIL_INTERVAL
			0.15, 0.05, 0.1,                # windup/commit/fade: minimal legible telegraph
			20.0,                           # zone_radius: matches the retired TRAIL_RADIUS footprint
			2.0,                            # hazard_duration: retired TRAIL_DURATION
			0.0,                            # hazard_slow_percent: the old trail never slowed
			3.0,                            # hazard_damage_per_sec: retired TRAIL_DAMAGE_PER_SEC
			20.0,                           # hazard_radius: retired TRAIL_RADIUS
			Color(0.7, 0.4, 0.4, 0.4),      # hazard_color: retired TRAIL_COLOR
			3,                              # cap: alive-hazard ceiling under the dense cadence
			0.0                             # placement_radius: always directly under the roomba
		),
		EnrageAbility.new(0.3, 1.5, 1.0),  # BERSERK_HP_FRACTION, BERSERK_SPEED_MULTIPLIER, no damage change
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


# Angry Pigeon (floor-1 standard mob / issue #583). Legibility pass only, not a
# retune: the retired AngryPigeonBehavior's hand-rolled dive bomb committed
# with no wind-up the player could read, then dropped a slow-only floor
# hazard on impact. The migration keeps the same cadence and speed (retired
# CHARGE_COOLDOWN = 4.0, CHARGE_SPEED = 120.0 px/s) and the same hazard
# (retired HAZARD_DURATION = 3.0, HAZARD_SLOW_PERCENT = 0.5, HAZARD_RADIUS =
# 32.0, HAZARD_COLOR = Color(0.6, 0.5, 0.7, 0.4), and an implicit 0.0
# damage-per-second — the hazard only ever slowed, it never dealt damage)
# while adding the uniform amber-to-red lane telegraph and disc telegraph
# every other archetype already draws. Wind-up/fade/lane-width (a 1.0s
# wind-up, a 1.0s commit sized so a 120.0 lane over that commit restates the
# same 120.0 px/s dash, and a 24.0 lane width) are new legibility tuning the
# hand-rolled dive never had, chosen the same way the Dog Knight's migration
# (issue #581) restated its own retired speed. The zone-denial half keeps its
# own cooldown/wind-up/commit/zone-radius/cap at ZoneDenialAbility's defaults
# — same "nothing here is kind-specific yet beyond the hazard itself" stance
# Trash Panda Tyrone's loadout took (issue #571) — only the hazard's own
# duration/slow/damage/radius/color are the pigeon's preserved numbers.
#
# Direct-hit damage parity (issue #583 fix-mode round 2): unlike Dog Knight's
# pre-migration charge (which already dealt contact damage, so composing
# TelegraphedChargeAbility there was like-for-like), the pigeon's dive bomb
# never damaged the player on the dive itself — only the dropped hazard did,
# and that hazard dealt 0 damage. TelegraphedChargeAbility's shared commit
# still resolves a hit against the lane (needed for the lane telegraph and
# for Test 3's "zone is the hitbox" geometry assertion), but Enemy._consume_
# ability_payload discards that hit for exactly (ANGRY_PIGEON, this ability)
# rather than routing it into damage, so the migration cannot introduce a hit
# the hand-rolled dive never had.
static func angry_pigeon_loadout() -> Array:
	return [
		TelegraphedChargeAbility.new(4.0, 1.0, 1.0, 0.3, 120.0, 24.0),
		ZoneDenialAbility.new(
			6.0, 0.7, 0.2, 0.3, 36.0,
			3.0, 0.5, 0.0, 32.0, Color(0.6, 0.5, 0.7, 0.4)
		),
	]
