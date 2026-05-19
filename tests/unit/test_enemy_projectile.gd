extends GutTest

# Tests for the reusable EnemyProjectile primitive (issue #159). All tests
# drive movement / hit predicates directly so no SceneTree is required —
# matches the EnemyBehavior test pattern (issue #157).

var _spawned: Array = []

func _make(target: Vector2, speed: float, max_range: float = 400.0) -> EnemyProjectile:
	var p := EnemyProjectile.new()
	p.position = Vector2.ZERO
	p.configure(target, speed, 8.0, Color(1, 1, 1, 1), max_range, Callable())
	_spawned.append(p)
	return p

func after_each() -> void:
	for p in _spawned:
		if is_instance_valid(p):
			p.free()
	_spawned.clear()


func test_linear_movement_math():
	# Acceptance #1: moves toward target at `speed` px/sec.
	var p := _make(Vector2(100, 0), 50.0)
	p.simulate_move(1.0)
	assert_almost_eq(p.position.x, 50.0, 0.01, "should travel 50px in 1s at 50px/s")
	assert_almost_eq(p.position.y, 0.0, 0.01)


func test_on_hit_callback_fires():
	# Acceptance #2: on_hit callback fires with the player node.
	var p := EnemyProjectile.new()
	_spawned.append(p)
	var hit_flag := [false]
	var hit_arg := [null]
	p.configure(Vector2(100, 0), 50.0, 8.0, Color.WHITE, 400.0,
		func(player): hit_flag[0] = true; hit_arg[0] = player)
	var mock_player := RefCounted.new()
	p._on_player_hit(mock_player)
	assert_true(hit_flag[0], "on_hit should fire")
	assert_eq(hit_arg[0], mock_player, "on_hit should receive the player arg")


func test_max_range_expiry():
	# Acceptance #4: despawns after exceeding max_range.
	var p := _make(Vector2(1000, 0), 100.0, 80.0)
	assert_false(p.should_despawn(), "fresh projectile should not despawn")
	# 0.5s @ 100 px/s = 50px travelled — under max_range.
	p.simulate_move(0.5)
	assert_false(p.should_despawn(), "50px travelled is under 80px max_range")
	# Another 0.5s -> 100px total, past 80px max_range.
	p.simulate_move(0.5)
	assert_true(p.should_despawn(), "100px > 80px max_range should despawn")


func test_no_double_hit():
	# Acceptance #3: callback fires exactly once even if hit twice.
	var p := EnemyProjectile.new()
	_spawned.append(p)
	var count := [0]
	p.configure(Vector2(100, 0), 50.0, 8.0, Color.WHITE, 400.0,
		func(_player): count[0] += 1)
	var mock_player := RefCounted.new()
	p._on_player_hit(mock_player)
	p._on_player_hit(mock_player)
	assert_eq(count[0], 1, "on_hit should fire exactly once across two hits")
	assert_true(p.should_despawn(), "post-hit projectile should despawn")


func test_zero_speed_safe():
	# Acceptance #5: zero speed is a no-op, no crash, no movement.
	var p := _make(Vector2(100, 0), 0.0)
	var before := p.position
	p.simulate_move(1.0)
	assert_eq(p.position, before, "zero-speed projectile should not move")
	assert_false(p.should_despawn(), "zero-speed projectile should not auto-despawn")


func test_configure_sets_all_fields():
	# Acceptance #6: speed, color, radius, on_hit all configurable at spawn.
	var p := EnemyProjectile.new()
	_spawned.append(p)
	var cb := func(_player): pass
	p.configure(Vector2(10, 20), 75.0, 12.0, Color(0.5, 0.6, 0.7, 0.8), 250.0, cb)
	assert_eq(p.target_position, Vector2(10, 20))
	assert_almost_eq(p.speed, 75.0, 0.0001)
	assert_almost_eq(p.radius, 12.0, 0.0001)
	assert_eq(p.color, Color(0.5, 0.6, 0.7, 0.8))
	assert_almost_eq(p.max_range, 250.0, 0.0001)
	assert_true(p.on_hit.is_valid(), "on_hit Callable should be set")


func test_callback_unset_is_safe():
	# Hit path with no on_hit set should still mark despawn without crashing.
	var p := _make(Vector2(100, 0), 50.0)
	p._on_player_hit(RefCounted.new())
	assert_true(p.should_despawn(), "hit without on_hit should still despawn")
