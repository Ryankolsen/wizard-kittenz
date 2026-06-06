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

# Player stand-in carrying a real CharacterData so the co-op routing tests
# can exercise CoopRouter.target_for (which resolves the local member's
# effective_stats off a real CharacterData, not a mock).
class _RealPlayer:
	var data: CharacterData
	func _init(d: CharacterData) -> void:
		data = d


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


# --- Co-op HP routing (multiplayer box-heal fix) ---------------------------
#
# In co-op, incoming damage / death checks / the HUD HP bar all read the
# local PartyMember's effective_stats (CoopRouter.target_for); real_stats
# stays full. The box healed target.data (real_stats), so the heal landed on
# a block nobody fights with and was invisible in multiplayer. resolve_hp_data
# is the seam that points HP healing at the same block damage lands on.

func _make_lobby(player_specs: Array) -> LobbyState:
	var ls := LobbyState.new("ABCDE")
	for spec in player_specs:
		ls.add_player(LobbyPlayer.make(spec[0], spec[1], spec[2], false))
	return ls

func _make_two_room_dungeon() -> Dungeon:
	var d := Dungeon.new()
	var start := Room.make(0, Room.TYPE_START)
	start.connections = [1]
	d.add_room(start)
	d.start_id = 0
	var boss := Room.make(1, Room.TYPE_BOSS)
	boss.enemy_kind = EnemyData.EnemyKind.DOG_KNIGHT
	d.add_room(boss)
	d.boss_id = 1
	return d

func _make_active_session(local_id: String = "u1") -> CoopSession:
	var lobby := _make_lobby([["u1", "A", "Mage"]])
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN, "k")
	c.level = 1
	c.xp = 0
	var session := CoopSession.new(lobby, {"u1": c}, null, local_id)
	session.start(_make_two_room_dungeon())
	return session


func test_resolve_hp_data_solo_returns_node_data():
	var target := _MockPlayer.new()
	assert_eq(HealingBox.resolve_hp_data(target, null, ""), target.data,
		"solo / no session heals the node's own data (real == effective)")


func test_resolve_hp_data_coop_returns_effective_stats():
	var session := _make_active_session("u1")
	var real := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN, "k")
	var target := _RealPlayer.new(real)
	var resolved = HealingBox.resolve_hp_data(target, session, "u1")
	var member := session.member_for("u1")
	assert_eq(resolved, member.effective_stats,
		"co-op heals effective_stats — the block damage / death / HUD read")
	assert_ne(resolved, real, "co-op must not heal real_stats (stays full, invisible)")


func test_tick_heals_routed_hp_block_and_leaves_node_data_hp():
	# Co-op shape: HP heals the routed block (effective_stats stand-in) while
	# the node's own data.hp (real_stats) is untouched. MP still heals the
	# node data, since MP is tracked on real_stats in both modes.
	var h := _make()
	var target := _MockPlayer.new()
	target.data.hp = 10        # real_stats full — never the source of healing here
	target.data.max_hp = 10
	target.data.magic_points = 3
	target.data.max_mp = 10
	var effective := _MockData.new()  # the routed HP block damage lands on
	effective.hp = 5
	effective.max_hp = 10
	h.tick(1.0, target, effective)
	assert_eq(effective.hp, 7, "HP heals the routed (effective_stats) block")
	assert_eq(target.data.hp, 10, "real_stats HP left untouched in co-op")
	assert_eq(target.data.magic_points, 4, "MP still heals the node's own data")
