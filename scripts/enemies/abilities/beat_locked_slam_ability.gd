class_name BeatLockedSlamAbility
extends GroundSlamAbility

# Beat-locked slam archetype (PRD #518 / issue #579). DJ Dubstep's shockwave
# rings are exactly GroundSlamAbility's ring -- the wave shape, the hit
# resolution and the fire-once-per-firing bookkeeping are untouched -- but
# fired on a steady tempo instead of a free-running cooldown, so the interval
# a player learns stays learnable across a whole fight rather than drifting.
#
# There is no music-beat API in this codebase (no BPM source, no audio clock).
# The parent PRD names a fixed internal tempo as the acceptable fallback, so
# `_interval`/`_enraged_interval` below are just tuning values threaded
# through AbilityLoadout like every other archetype's numbers -- no
# music-sync layer is added here.
#
# The drift problem: EnemyAbility.tick only accrues `_cooldown_elapsed` while
# NOT active (see enemy_ability.gd) -- the clock freezes for the zone's whole
# windup+commit+fade lifetime and only resumes once it clears. That makes the
# real gap between firings `cooldown() + zone_lifetime`, not `cooldown()`,
# which drifts the instant the tempo is faster than (or close to) the zone's
# own lifetime. This subclass fixes that by also accruing `_cooldown_elapsed`
# while the zone is active, so the clock never pauses; `begin()` additionally
# carries forward any overshoot past the beat boundary (rather than snapping
# back to exactly zero) so per-tick rounding never compounds into audible
# drift over a long fight.
#
# Subclassing GroundSlamAbility (rather than composing it) is what keeps this
# a small file: every difference here is *when* a firing is allowed to start,
# never what a firing does once it starts, so reusing the parent's _init
# signature, hit resolution and DangerZoneShape.make_ring construction via
# inheritance is the natural seam -- there was no case where the EnemyAbility
# pump needed a different shape to fit this in.
#
# Enrage (issue #575, reused unmodified here as a sibling ability in
# AbilityLoadout) is what makes Dubstep the enum's second and final enrage
# user. That EnrageAbility instance mutates the enemy's move_speed and
# data.attack; it has no notion of a slam tempo, so this ability tracks its
# own one-shot HP-threshold check to speed up its own clock in lockstep --
# "same dance, faster" per the PRD, rather than swapping in a different move.

const _MIN_INTERVAL: float = 0.05

var _interval: float
var _enraged_interval: float
var _enrage_hp_fraction: float

# One-shot flag, same shape as EnrageAbility.has_enraged: once true, the
# shortened interval applies for the rest of the fight even if HP recovers.
var _enraged: bool = false


func _init(
	interval_seconds: float = 3.0,
	enraged_interval_seconds: float = 2.2,
	enrage_hp_fraction: float = 0.3,
	windup_seconds: float = 0.4,
	commit_seconds: float = 0.9,
	fade_seconds: float = 0.2,
	max_radius: float = 90.0,
	band_width: float = 20.0
) -> void:
	super._init(interval_seconds, windup_seconds, commit_seconds, fade_seconds, max_radius, band_width)
	# Clamp to a small positive floor rather than dividing by anything -- a
	# zero or negative tempo must not make wants_to_fire() true every single
	# frame once cooldown() reads 0.0.
	_interval = maxf(interval_seconds, _MIN_INTERVAL)
	_enraged_interval = maxf(enraged_interval_seconds, _MIN_INTERVAL)
	_enrage_hp_fraction = enrage_hp_fraction


func interval() -> float:
	return _interval

func enraged_interval() -> float:
	return _enraged_interval

func enrage_hp_fraction() -> float:
	return _enrage_hp_fraction

func is_enraged() -> bool:
	return _enraged

# The tempo currently in force -- shortens once, permanently, on enrage. This
# is the single seam every other piece of this ability's timing reads through
# (wants_to_fire's threshold and begin()'s overshoot carry both call this),
# so enraging never needs to touch either of them directly.
func cooldown() -> float:
	return _enraged_interval if _enraged else _interval


# Locks in a firing exactly like GroundSlamAbility.begin, but preserves the
# beat's phase: any elapsed time already accrued past the beat boundary
# (`overshoot`) is carried into the next cycle instead of being discarded to
# zero, so per-tick rounding never compounds into drift over a long fight.
func begin(enemy) -> void:
	var target_cooldown := cooldown()
	var overshoot: float = _cooldown_elapsed - target_cooldown
	super.begin(enemy)
	if is_active() and overshoot > 0.0:
		_cooldown_elapsed = overshoot


func tick(delta: float, enemy) -> void:
	_update_enrage(enemy)
	# Captured before super.tick() runs, not after: on the exact tick a zone
	# expires, _advance_zone flips `active_zone` to null partway through the
	# base class's active branch, which already returned without touching
	# `_cooldown_elapsed` for that tick. Checking is_active() afterward would
	# see it as already inactive and skip crediting that tick's delta too --
	# silently dropping one tick's worth of elapsed time on every zone
	# expiry, which is a small but real per-firing drift over a long fight.
	var was_active := is_active()
	# GroundSlamAbility.tick both advances an active zone's wave (including
	# its own fire-once hit resolution) and, when idle, accrues
	# `_cooldown_elapsed` via the inherited EnemyAbility.tick -- exactly the
	# behaviour this archetype keeps unchanged.
	super.tick(delta, enemy)
	# The one addition: keep the beat clock advancing even while a zone is
	# still active, rather than freezing for the zone's lifetime the way the
	# base class's active-branch does. This is the whole fix for a steady,
	# non-drifting tempo (see the class comment above).
	if was_active and EnemyBehavior.is_aggroed(enemy):
		_cooldown_elapsed += delta


func _update_enrage(enemy) -> void:
	if _enraged or enemy == null:
		return
	# Same DEAD/IDLE sink EnrageAbility applies: a dead or never-engaged boss
	# doesn't speed up its own beat.
	if not EnemyBehavior.is_aggroed(enemy):
		return
	var d = enemy.get("data")
	if d == null:
		return
	var max_hp_val = d.get("max_hp")
	var hp_val = d.get("hp")
	if max_hp_val == null or hp_val == null or float(max_hp_val) <= 0.0:
		return
	if float(hp_val) / float(max_hp_val) > _enrage_hp_fraction:
		return
	_enraged = true
