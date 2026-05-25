extends GutTest

# Issue #264: per-player toggleable wall-collision capability. The walls
# physics bit (#263) is added to / removed from collision_mask via the
# Player.set_can_phase_through_walls setter. Default is phasing-on so the
# pre-#264 pass-through behavior survives.

const _WALLS_MASK := EnemyBehavior.WALL_COLLISION_MASK
const _ACTOR_BIT := 1  # default CharacterBody2D collision_mask bit 0

func _make_player() -> Player:
	var p := Player.new()
	add_child_autofree(p)
	return p


func test_phasing_on_by_default():
	var p := _make_player()
	assert_true(p.can_phase_through_walls(),
		"fresh Player must default to phasing enabled")
	assert_eq(p.collision_mask & _WALLS_MASK, 0,
		"default collision_mask must not include the walls bit")


func test_disabling_phasing_adds_wall_mask():
	var p := _make_player()
	var before_other := p.collision_mask & ~_WALLS_MASK
	p.set_can_phase_through_walls(false)
	assert_false(p.can_phase_through_walls(),
		"setter must flip the capability flag")
	assert_eq(p.collision_mask & _WALLS_MASK, _WALLS_MASK,
		"disabling phasing must set the walls bit")
	assert_eq(p.collision_mask & ~_WALLS_MASK, before_other,
		"other mask bits must be untouched")


func test_re_enabling_phasing_removes_wall_mask():
	var p := _make_player()
	p.set_can_phase_through_walls(false)
	var before_other := p.collision_mask & ~_WALLS_MASK
	p.set_can_phase_through_walls(true)
	assert_true(p.can_phase_through_walls(),
		"setter must flip the capability flag back")
	assert_eq(p.collision_mask & _WALLS_MASK, 0,
		"re-enabling phasing must clear the walls bit")
	assert_eq(p.collision_mask & ~_WALLS_MASK, before_other,
		"other mask bits must be untouched")


func test_toggle_is_idempotent():
	# Re-applying the same value must leave the mask in the expected single
	# state — no bit accumulation, no double-clear that wipes other bits.
	var p := _make_player()
	p.set_can_phase_through_walls(false)
	var mask_after_one_disable := p.collision_mask
	p.set_can_phase_through_walls(false)
	assert_eq(p.collision_mask, mask_after_one_disable,
		"disabling twice must leave collision_mask unchanged")

	p.set_can_phase_through_walls(true)
	var mask_after_one_enable := p.collision_mask
	p.set_can_phase_through_walls(true)
	assert_eq(p.collision_mask, mask_after_one_enable,
		"enabling twice must leave collision_mask unchanged")
	assert_eq(p.collision_mask & _WALLS_MASK, 0,
		"final state: phasing on -> walls bit cleared")


func test_per_instance_does_not_leak_to_other_players():
	# Co-op safety: toggling capability on player A must not mutate player B.
	var a := _make_player()
	var b := _make_player()
	var b_mask_before := b.collision_mask
	a.set_can_phase_through_walls(false)
	assert_eq(b.collision_mask, b_mask_before,
		"toggling on one player must not change another player's mask")
	assert_true(b.can_phase_through_walls(),
		"other player's capability flag must still be the default")
