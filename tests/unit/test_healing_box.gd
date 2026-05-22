extends GutTest

# Tests for HealingBox (per-dungeon cardboard box healing zone). Drives tick()
# directly without a SceneTree — same headless pattern as test_floor_hazard.gd.

class _MockData:
	var hp: int = 5
	var max_hp: int = 10
	var magic_points: int = 3
	var max_mp: int = 10

	func heal(amount: int) -> int:
		var healed := mini(amount, max_hp - hp)
		hp += healed
		return healed

class _MockPlayer:
	var data: _MockData = _MockData.new()


var _spawned: Array = []

func _make() -> HealingBox:
	var h := HealingBox.new()
	_spawned.append(h)
	return h

func after_each() -> void:
	for h in _spawned:
		if is_instance_valid(h):
			h.free()
	_spawned.clear()


func test_tick_heals_hp_after_one_second():
	var h := _make()
	var target := _MockPlayer.new()
	target.data.hp = 5
	target.data.max_hp = 10
	h.tick(1.0, target)
	assert_eq(target.data.hp, 7, "2 HP/s tick should heal 2 HP in 1 second")


func test_tick_heals_mp_after_one_second():
	var h := _make()
	var target := _MockPlayer.new()
	target.data.magic_points = 3
	target.data.max_mp = 10
	h.tick(1.0, target)
	assert_eq(target.data.magic_points, 4, "1 MP/s tick should heal 1 MP in 1 second")


func test_tick_null_target_resets_accumulator():
	var h := _make()
	var target := _MockPlayer.new()
	target.data.hp = 5
	target.data.max_hp = 10
	# Partial tick accumulates 0.5s of HP (1 HP accrued, not yet whole)
	h.tick(0.4, target)
	# Null wipes the accumulator so re-entry doesn't front-load the fraction
	h.tick(0.4, null)
	var hp_before := target.data.hp
	h.tick(0.4, target)
	# Only 0.4s accumulation since re-entry, not 0.4 + 0.4 = 0.8
	assert_eq(target.data.hp, hp_before, "accumulator reset on null should prevent phantom heal")


func test_tick_fractional_accumulation_floors_to_whole():
	# 3 ticks of 0.3s at 2 HP/s → 0.6 + 0.6 + 0.6 = 1.8 accumulated → 1 HP dealt, 0.8 carried
	var h := _make()
	var target := _MockPlayer.new()
	target.data.hp = 5
	target.data.max_hp = 10
	h.tick(0.3, target)
	h.tick(0.3, target)
	h.tick(0.3, target)
	assert_eq(target.data.hp, 6, "1.8 accumulated HP should deal 1 whole HP")


func test_tick_does_not_overheal_beyond_max():
	var h := _make()
	var target := _MockPlayer.new()
	target.data.hp = 9
	target.data.max_hp = 10
	h.tick(2.0, target)
	assert_eq(target.data.hp, 10, "healing should cap at max_hp")


func test_tick_does_not_heal_mp_beyond_max():
	var h := _make()
	var target := _MockPlayer.new()
	target.data.magic_points = 9
	target.data.max_mp = 10
	h.tick(3.0, target)
	assert_eq(target.data.magic_points, 10, "MP heal should cap at max_mp")


func test_tick_skips_mp_heal_when_max_mp_is_zero():
	var h := _make()
	var target := _MockPlayer.new()
	target.data.magic_points = 0
	target.data.max_mp = 0
	h.tick(1.0, target)
	assert_eq(target.data.magic_points, 0, "max_mp=0 should not try to heal MP")
