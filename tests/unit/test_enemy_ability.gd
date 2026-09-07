extends GutTest

# EnemyAbility (PRD #518 / tracer slice #533). The archetype base every enemy
# ability composes from: a cooldown, a wind-up, the danger zone it produces and
# the commit payload it fires once. Pure RefCounted — driven here with inline
# mocks in the same style as test_enemy_behavior.gd, no SceneTree.


class _MockEnemy:
	var global_position: Vector2 = Vector2.ZERO
	var state: int = 1  # EnemyAIState.State.CHASE
	var _player_ref: Node2D = null


# Minimal concrete archetype: publishes a fixed lane and counts its commits.
class _MockAbility extends EnemyAbility:
	var commit_count: int = 0
	var last_zone = null

	func cooldown() -> float:
		return 2.0

	func windup_duration() -> float:
		return 0.7

	func commit_duration() -> float:
		return 0.2

	func fade_duration() -> float:
		return 0.3

	func _build_zone(enemy) -> DangerZoneShape:
		return DangerZoneShape.make_lane(
			enemy.global_position, Vector2.RIGHT, 100.0, 20.0,
			windup_duration(), commit_duration(), fade_duration())

	func _on_commit(_enemy, zone) -> void:
		commit_count += 1
		last_zone = zone


func test_ability_wants_to_fire_only_once_the_cooldown_has_elapsed():
	# Acceptance #6 (cooldown edge). Mirrors the pigeon's wants_to_charge()
	# assertions: below the cooldown the ability stays quiet; past it, it fires.
	var a := _MockAbility.new()
	var e := _MockEnemy.new()
	a.tick(1.0, e)
	assert_false(a.wants_to_fire(), "ability must not fire below its cooldown")
	a.tick(1.5, e)
	assert_true(a.wants_to_fire(), "ability must want to fire once the cooldown elapses")


func test_ability_produces_a_zone_at_windup_start_and_commits_exactly_once():
	# Acceptance #7 (wind-up edge). Firing publishes a zone immediately — the
	# telegraph is what the player reads — and the payload lands once on the
	# commit edge rather than once per frame of the damage window.
	var a := _MockAbility.new()
	var e := _MockEnemy.new()
	a.begin(e)
	assert_not_null(a.active_zone, "firing must produce a zone at wind-up start")
	assert_eq(a.active_zone.phase_at(a.zone_elapsed()), DangerZoneShape.Phase.WINDUP,
		"the freshly produced zone starts in its wind-up")
	assert_eq(a.commit_count, 0, "the payload must not fire during the wind-up")
	# 0.05s steps across the whole 0.7 + 0.2 + 0.3 lifecycle.
	for _i in range(30):
		a.tick(0.05, e)
	assert_eq(a.commit_count, 1, "the commit payload must fire exactly once, not per frame")


func test_idle_enemy_neither_accrues_cooldown_nor_telegraphs():
	# Acceptance #8 (aggro gate). Matches EnemyBehavior.is_aggroed: an IDLE
	# enemy is out of detection range, so nothing winds up on it.
	var a := _MockAbility.new()
	var idle := _MockEnemy.new()
	idle.state = 0  # EnemyAIState.State.IDLE
	for _i in range(10):
		a.tick(1.0, idle)
	assert_false(a.wants_to_fire(), "an IDLE enemy must not accrue ability cooldown")
	assert_null(a.active_zone, "an IDLE enemy must not produce a danger zone")


# --- Vacuum archetypes (PRD #518 / tracer slice #533) ------------------------

func _charge_setup(player_position: Vector2) -> Array:
	var a := TelegraphedChargeAbility.new()
	var e := _MockEnemy.new()
	var p: Node2D = autofree(Node2D.new())
	p.global_position = player_position
	e._player_ref = p
	a.begin(e)
	return [a, e, p]


func test_player_who_walks_clear_of_the_lane_takes_no_damage():
	# Acceptance: "a player standing outside a drawn zone at commit takes no
	# damage from it". The lane is locked at telegraph start, so stepping
	# perpendicular during the wind-up is a complete answer to the charge.
	var setup := _charge_setup(Vector2(100.0, 0.0))
	var a: TelegraphedChargeAbility = setup[0]
	var e = setup[1]
	var p: Node2D = setup[2]
	p.global_position = Vector2(100.0, 60.0)  # sidestepped out of the lane
	for _i in range(40):
		a.tick(0.05, e)
	assert_null(a.pending_hit_target,
		"a player outside the drawn lane at commit must not be hit")


func test_player_standing_in_the_lane_is_hit_once_at_commit():
	# The other half of drawn-equals-hit: standing in the corridor the enemy
	# drew does get you run over.
	var setup := _charge_setup(Vector2(100.0, 0.0))
	var a: TelegraphedChargeAbility = setup[0]
	var e = setup[1]
	var p: Node2D = setup[2]
	for _i in range(40):
		a.tick(0.05, e)
	assert_eq(a.pending_hit_target, p,
		"a player standing in the drawn lane must be hit when it commits")


func test_charge_windup_is_long_enough_to_walk_out_of_the_lane():
	# Acceptance: the wind-up must be beatable at normal walking speed, since
	# the PRD gives the player no dash. 60.0 px/s is the player's baseline
	# `speed` (scripts/core/player.gd); clearing the lane means covering half
	# its width from the centreline.
	var walk_speed := 60.0
	var a := TelegraphedChargeAbility.new()
	var escape_distance: float = a.lane_width() * 0.5
	assert_gt(a.windup_duration() * walk_speed, escape_distance * 2.0,
		"wind-up must leave at least double the margin needed to clear the lane")


# --- resolve_hit core wiring (issue #566) ------------------------------------
# The seam _apply_ability_damage / _try_contact_damage's shared tail is built
# on. Asserted directly (not just indirectly via TelegraphedChargeAbility)
# so a future dedup refactor in enemy.gd cannot silently move this contract.

func test_resolve_hit_returns_the_local_player_when_the_zone_contains_them():
	var setup := _charge_setup(Vector2(100.0, 0.0))
	var a: TelegraphedChargeAbility = setup[0]
	var e = setup[1]
	var p: Node2D = setup[2]
	# resolve_hit's contains() check only reads true during the zone's COMMIT
	# phase, so advance past the wind-up (0.8s) without reaching fade (1.15s).
	for _i in range(17):
		a.tick(0.05, e)
	assert_eq(a.resolve_hit(e, a.active_zone), p,
		"resolve_hit must return the local player when the zone contains them")


func test_resolve_hit_returns_null_when_the_zone_does_not_contain_the_player():
	var setup := _charge_setup(Vector2(100.0, 0.0))
	var a: TelegraphedChargeAbility = setup[0]
	var e = setup[1]
	var p: Node2D = setup[2]
	p.global_position = Vector2(100.0, 60.0)  # sidestepped out of the lane
	for _i in range(17):
		a.tick(0.05, e)
	assert_null(a.resolve_hit(e, a.active_zone),
		"resolve_hit must return null when the zone does not contain the player")


func test_resolve_hit_returns_null_for_a_null_enemy():
	var a := TelegraphedChargeAbility.new()
	assert_null(a.resolve_hit(null, null), "a null enemy must not crash resolve_hit")


func test_resolve_hit_returns_null_for_a_null_zone():
	var a := TelegraphedChargeAbility.new()
	var e := _MockEnemy.new()
	assert_null(a.resolve_hit(e, null), "a null zone must not crash resolve_hit")


func test_resolve_hit_returns_null_when_the_enemy_has_no_player_ref():
	var a := TelegraphedChargeAbility.new()
	var e := _MockEnemy.new()
	var zone := DangerZoneShape.make_lane(
		e.global_position, Vector2.RIGHT, 100.0, 20.0, 0.7, 0.2, 0.3)
	assert_null(a.resolve_hit(e, zone),
		"an enemy with no _player_ref must not crash resolve_hit")


func test_pull_drags_a_tethered_player_toward_the_enemy():
	# The Pull archetype's commit payload: the caught player is displaced along
	# the direction the zone itself reports, so the drag and the drawn tether
	# cannot disagree.
	var a := PullAbility.new()
	var e := _MockEnemy.new()
	var p: Node2D = autofree(Node2D.new())
	p.global_position = Vector2(120.0, 0.0)
	e._player_ref = p
	a.begin(e)
	for _i in range(40):
		a.tick(0.05, e)
	assert_lt(p.global_position.x, 120.0,
		"a tethered player must end up closer to the enemy")
	assert_gt(p.global_position.x, e.global_position.x,
		"the pull must not drag the player past the enemy")
