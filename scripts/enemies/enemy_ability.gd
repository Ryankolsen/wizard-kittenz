class_name EnemyAbility
extends RefCounted

# Ability archetype base (PRD #518 / tracer slice #533). An archetype is four
# things: a cooldown, a wind-up, the danger zone it produces, and the payload it
# commits once that zone goes live. Subclasses declare tuning by overriding the
# duration accessors and supply behaviour through `_build_zone` / `_on_commit`;
# everything else — the cooldown clock, the three-phase advance, the fire-once
# commit edge and the aggro gate — lives here so a new archetype is a small file
# rather than another hand-rolled state machine.
#
# Pure RefCounted, exactly like EnemyBehavior: no SceneTree, so every cooldown
# and wind-up edge is unit testable. The Enemy node pumps abilities generically
# (tick, then begin when `wants_to_fire`) and only handles the scene-side work
# the ability publishes through `pending_zone`.

# The zone currently drawn / queried, or null when the ability is dormant.
var active_zone: DangerZoneShape = null
# Handoff to the Enemy node: set when a zone is created, cleared by the node
# once it has parented a DangerZoneRenderer for it. Same publish/consume shape
# as AngryPigeonBehavior.pending_hazard_position.
var pending_zone: DangerZoneShape = null

# Handoffs the Enemy node consumes after the pump: the player caught by the
# commit payload (damage is routed node-side so co-op routing stays in one
# place) and the player displaced by a pull (VFX only).
var pending_hit_target = null
var pending_pull_target = null

var _cooldown_elapsed: float = 0.0
var _zone_elapsed: float = 0.0
var _committed: bool = false


# --- Tuning hooks. Subclasses override; the base is an inert archetype. ---

func cooldown() -> float:
	return 0.0

func windup_duration() -> float:
	return 0.0

func commit_duration() -> float:
	return 0.0

func fade_duration() -> float:
	return 0.0

# Builds the danger zone for this firing, snapshotting the enemy's and target's
# positions so the geometry is locked at telegraph start. Returning null means
# "conditions weren't right after all" and the firing is abandoned.
func _build_zone(_enemy) -> DangerZoneShape:
	return null

# The commit payload — damage, displacement, a dash. Called exactly once per
# firing, on the frame the zone crosses from wind-up into its damage window.
func _on_commit(_enemy, _zone) -> void:
	pass

# True while this ability owns the enemy's motion (e.g. a charge dash), which
# the behavior aggregates so the Enemy node skips its state-machine block.
func is_overriding_motion() -> bool:
	return false


# --- Pump interface, driven by the Enemy node. ---

func is_active() -> bool:
	return active_zone != null

func wants_to_fire() -> bool:
	return not is_active() and _cooldown_elapsed >= cooldown()

# Locks the zone in and starts the wind-up. Called by the pump when
# `wants_to_fire` — same shape as AngryPigeonBehavior.begin_charge.
func begin(enemy) -> void:
	var zone := _build_zone(enemy)
	_cooldown_elapsed = 0.0
	if zone == null:
		return
	active_zone = zone
	pending_zone = zone
	_zone_elapsed = 0.0
	_committed = false

func zone_elapsed() -> float:
	return _zone_elapsed

func tick(delta: float, enemy) -> void:
	if is_active():
		_advance_zone(delta, enemy)
		return
	# Aggro gate (issue #261 / PRD #518): an out-of-range enemy neither accrues
	# cooldown nor telegraphs, so a freshly-loaded level isn't full of zones the
	# player never provoked. A committed zone above still runs to completion.
	if not EnemyBehavior.is_aggroed(enemy):
		return
	_cooldown_elapsed += delta

func _advance_zone(delta: float, enemy) -> void:
	_zone_elapsed += delta
	var phase := active_zone.phase_at(_zone_elapsed)
	if phase != DangerZoneShape.Phase.WINDUP and not _committed:
		# Fire-once edge: the payload lands on the commit frame, not every
		# frame of the damage window.
		_committed = true
		_on_commit(enemy, active_zone)
	if active_zone.is_expired(_zone_elapsed):
		active_zone = null
		_zone_elapsed = 0.0
		_committed = false


# Position the ability locks onto at telegraph start. Reads `_player_ref` — the
# same cached local target the chase state tracks — so a zone aims at whoever
# the enemy was already fighting, and each client resolves against its own
# player only (PRD #518 co-op section: no new packets, no remote interpolation).
# Returns null (not Vector2.ZERO) when there is no target, so callers can tell
# "no target" from "target at the origin".
func target_position(enemy):
	if enemy == null:
		return null
	var p = enemy.get("_player_ref")
	if p == null or not (p is Node2D):
		return null
	return (p as Node2D).global_position


# The local player if the drawn zone contains them right now, else null. This is
# the whole of damage resolution: the same DangerZoneShape the renderer draws is
# the only thing consulted, so a player visibly outside the zone is never hit.
func resolve_hit(enemy, zone):
	if enemy == null or zone == null:
		return null
	var p = enemy.get("_player_ref")
	if p == null or not (p is Node2D):
		return null
	if zone.contains((p as Node2D).global_position, _zone_elapsed):
		return p
	return null


# Called by the pump each frame this ability owns motion. Default no-op; dash-
# style archetypes override to write the enemy's position.
func drive_motion(_delta: float, _enemy) -> void:
	pass
