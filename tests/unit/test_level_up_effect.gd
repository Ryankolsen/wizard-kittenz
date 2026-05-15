extends GutTest

# --- LevelUpEffect.is_real_level_up predicate -------------------------------

func test_is_real_level_up_true_when_new_exceeds_old():
	assert_true(LevelUpEffect.is_real_level_up(1, 2))
	assert_true(LevelUpEffect.is_real_level_up(1, 5))

func test_is_real_level_up_false_when_levels_equal():
	# An XP gain that doesn't cross a threshold leaves level unchanged.
	# No effect should fire (AC: no fire when levels_gained == 0).
	assert_false(LevelUpEffect.is_real_level_up(1, 1))
	assert_false(LevelUpEffect.is_real_level_up(10, 10))

func test_is_real_level_up_false_when_new_below_old():
	# Defensive against a future caller wiring with stale state — a
	# regression that lowered level should never play a celebratory burst.
	assert_false(LevelUpEffect.is_real_level_up(5, 3))

# --- CoopXPSubscriber.level_up signal plumbing (scene-layer trigger source) ----

func _make_member(lvl: int = 1) -> PartyMember:
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN, "k")
	c.level = lvl
	c.xp = 0
	c.max_hp = CharacterData.base_max_hp_for(CharacterData.CharacterClass.WIZARD_KITTEN, lvl)
	c.hp = c.max_hp
	return PartyMember.from_character(c)

# Capture-friendly signal sink. GDScript lambdas don't reliably mutate
# captured local primitives; using a tiny RefCounted holder + bound method
# gives stable mutate-from-signal semantics across the test cases below.
class _Capture extends RefCounted:
	var fired: bool = false
	var old_level: int = -1
	var new_level: int = -1
	func on_level_up(o: int, n: int) -> void:
		fired = true
		old_level = o
		new_level = n

func test_local_xp_router_level_up_fires_on_threshold_cross():
	# Core wiring: when an XP broadcast pushes the local member across a
	# level threshold, CoopXPSubscriber emits level_up(old, new). This is the
	# co-op trigger source for the level-up effect.
	var bc := XPBroadcaster.new()
	bc.register_player("p1")
	var member := _make_member(1)
	var router := CoopXPSubscriber.new(bc, "p1", member)
	var capture := _Capture.new()
	router.level_up.connect(capture.on_level_up)
	bc.on_enemy_killed(ProgressionSystem.xp_to_next_level(1), "p1")
	assert_eq(member.real_stats.level, 2, "precondition: level advanced")
	assert_true(capture.fired, "level_up signal fires on level advance")

func test_local_xp_router_level_up_carries_old_and_new_level():
	# Content detail: signal carries (old_level, new_level) so the effect
	# can render "Level N!" text or iterate intermediate levels in a
	# multi-level jump.
	var bc := XPBroadcaster.new()
	bc.register_player("p1")
	var member := _make_member(1)
	var router := CoopXPSubscriber.new(bc, "p1", member)
	var capture := _Capture.new()
	router.level_up.connect(capture.on_level_up)
	bc.on_enemy_killed(ProgressionSystem.xp_to_next_level(1), "p1")
	assert_eq(capture.old_level, 1)
	assert_eq(capture.new_level, 2)

func test_local_xp_router_no_signal_on_sub_threshold_gain():
	# AC: no effect fires when levels_gained == 0. A small XP award that
	# doesn't cross a threshold must not emit level_up.
	var bc := XPBroadcaster.new()
	bc.register_player("p1")
	var member := _make_member(1)
	var router := CoopXPSubscriber.new(bc, "p1", member)
	var capture := _Capture.new()
	router.level_up.connect(capture.on_level_up)
	bc.on_enemy_killed(1, "p1")  # tiny amount, no level-up
	assert_false(capture.fired)

# --- LevelUpEffect.play() emits triggered signal ---------------------------

class _LevelCapture extends RefCounted:
	var captured: int = -1
	func on_triggered(lvl: int) -> void:
		captured = lvl

func test_play_emits_triggered_signal_with_new_level():
	# play(new_level) is the scene-layer entry point. The triggered signal
	# lets a future analytics / achievement listener react to level-ups
	# without reaching into the particle/audio internals.
	var effect := LevelUpEffect.new()
	add_child_autofree(effect)
	await get_tree().process_frame
	var capture := _LevelCapture.new()
	effect.triggered.connect(capture.on_triggered)
	effect.play(7)
	assert_eq(capture.captured, 7)

func test_play_is_safe_before_ready():
	# Defensive: a caller that constructs a LevelUpEffect and calls play()
	# before _ready (no scene attach) shouldn't crash. The particle/audio
	# children are built in _ready, but play() must null-guard them.
	var effect := LevelUpEffect.new()
	var capture := _LevelCapture.new()
	effect.triggered.connect(capture.on_triggered)
	effect.play(3)
	assert_eq(capture.captured, 3, "triggered fires even before _ready")
	effect.free()
