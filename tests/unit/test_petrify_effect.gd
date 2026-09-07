extends GutTest

# Petrify effect (PRD #518 / issue #536). Same tick-based coverage shape as
# tests/unit/test_player_debuffs.gd's wet/slowness coverage, routed through
# the unified PowerUpManager.apply path since that's the seam every debuff
# source (including Sir Pickleton's ambush) actually calls through.

func _new_data() -> CharacterData:
	return CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN, "Test")


# --- 1. Core wiring -------------------------------------------------------

func test_petrify_blocks_movement_and_expires_after_duration():
	var c := _new_data()
	var manager := PowerUpManager.new()
	manager.apply(PetrifyEffect.TYPE, c, 0.5)
	assert_true(c.is_petrified(), "movement should be blocked while petrified")
	manager.tick(0.6)
	assert_false(c.is_petrified(), "petrify should expire and restore movement after its duration")


# --- 2. Actions stay free ---------------------------------------------------

func test_petrify_leaves_attacking_available():
	var c := _new_data()
	var effect := PetrifyEffect.new()
	effect.apply_to(c)
	var attack_controller := AttackController.new()
	assert_true(attack_controller.can_attack(0.0),
		"attacking must remain available while petrified")

func test_petrify_leaves_casting_available():
	var c := _new_data()
	var effect := PetrifyEffect.new()
	effect.apply_to(c)
	var spell := Spell.make("test_bolt", "Test Bolt", Spell.EffectKind.DAMAGE, 5, 1.0)
	assert_true(spell.cast(c), "casting must remain available while petrified")

func test_petrify_leaves_potion_use_available():
	var c := _new_data()
	var effect := PetrifyEffect.new()
	effect.apply_to(c)
	var belt := PotionBelt.new()
	assert_false(belt.is_on_cooldown(), "potion use must remain available while petrified")


# --- 3. Edge cases -----------------------------------------------------------

func test_petrify_zero_duration_expires_on_first_tick():
	var c := _new_data()
	var manager := PowerUpManager.new()
	manager.apply(PetrifyEffect.TYPE, c, 0.0)
	assert_true(c.is_petrified(), "petrify should apply immediately even at zero duration")
	manager.tick(0.001)
	assert_false(c.is_petrified(), "zero duration should expire on the very next tick")

func test_petrify_negative_delta_does_not_expire_early():
	var c := _new_data()
	var manager := PowerUpManager.new()
	manager.apply(PetrifyEffect.TYPE, c, 1.0)
	manager.tick(-5.0)
	assert_true(c.is_petrified(), "a negative delta must not expire petrify early")

func test_petrify_reapply_refreshes_rather_than_stacks():
	var c := _new_data()
	var manager := PowerUpManager.new()
	var first := manager.apply(PetrifyEffect.TYPE, c, 1.0)
	manager.tick(0.8)
	var second := manager.apply(PetrifyEffect.TYPE, c, 1.0)
	assert_eq(second, first, "re-applying while already petrified should refresh the same instance")
	assert_almost_eq(first.remaining, 1.0, 0.0001, "remaining should reset to full on refresh")
	assert_eq(manager.active_count(), 1, "refresh should not stack a second PetrifyEffect")
	# The counter-based lock must not be double-pushed by the second apply() —
	# a single expiry should fully clear it.
	manager.tick(1.1)
	assert_false(c.is_petrified(), "a single expiry should clear petrify even though apply() was called twice")

func test_petrify_ticking_after_expiry_stays_expired():
	var c := _new_data()
	var manager := PowerUpManager.new()
	manager.apply(PetrifyEffect.TYPE, c, 0.5)
	manager.tick(0.6)
	assert_false(c.is_petrified(), "precondition: petrify has expired")
	manager.tick(1.0)
	assert_false(c.is_petrified(), "ticking after expiry should keep petrify cleared")
