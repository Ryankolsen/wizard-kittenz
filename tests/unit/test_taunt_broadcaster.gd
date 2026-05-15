extends GutTest

# Unit tests for TauntBroadcaster — the co-op fan-out seam for Chonk
# Kitten's TAUNT cast (PRD #124, co-op follow-up to #128). Mirrors the
# shape of XPBroadcaster's tests: pin the contract for guarded no-ops
# and the (caster_id, enemy_id, duration) emission tuple.

func _capture(bc: TauntBroadcaster) -> Array:
	var captured: Array = []
	bc.taunt_applied.connect(func(c: String, e: String, d: float):
		captured.append([c, e, d])
	)
	return captured

func test_on_taunt_applied_emits_signal_with_tuple():
	var bc := TauntBroadcaster.new()
	var captured := _capture(bc)
	assert_true(bc.on_taunt_applied("u1", "r3_e0", 2.0))
	assert_eq(captured.size(), 1)
	assert_eq(captured[0][0], "u1")
	assert_eq(captured[0][1], "r3_e0")
	assert_eq(captured[0][2], 2.0)

func test_on_taunt_applied_rejects_empty_caster_id():
	# An empty caster_id means the receiving client can't resolve the
	# casting Player on its side — no point sending it on the wire.
	var bc := TauntBroadcaster.new()
	var captured := _capture(bc)
	assert_false(bc.on_taunt_applied("", "r3_e0", 2.0))
	assert_eq(captured.size(), 0, "no emission on empty caster_id")

func test_on_taunt_applied_rejects_empty_enemy_id():
	# Legacy / test enemies have empty enemy_id (same gate as
	# KillRewardRouter's apply_death skip). Without an addressable
	# enemy on the remote side, the broadcast is undeliverable.
	var bc := TauntBroadcaster.new()
	var captured := _capture(bc)
	assert_false(bc.on_taunt_applied("u1", "", 2.0))
	assert_eq(captured.size(), 0, "no emission on empty enemy_id")

func test_on_taunt_applied_rejects_non_positive_duration():
	# Zero/negative duration is a cleared taunt, not a new one. Mirrors
	# XPBroadcaster's non-positive-amount guard.
	var bc := TauntBroadcaster.new()
	var captured := _capture(bc)
	assert_false(bc.on_taunt_applied("u1", "r3_e0", 0.0))
	assert_false(bc.on_taunt_applied("u1", "r3_e0", -1.0))
	assert_eq(captured.size(), 0, "no emission on non-positive duration")

func test_multiple_taunts_emit_independently():
	# Each call is one event — no debouncing/aggregation in the
	# broadcaster. Two casts on two enemies produce two emissions.
	var bc := TauntBroadcaster.new()
	var captured := _capture(bc)
	bc.on_taunt_applied("u1", "r3_e0", 2.0)
	bc.on_taunt_applied("u1", "r3_e1", 2.0)
	assert_eq(captured.size(), 2)
	assert_eq(captured[0][1], "r3_e0")
	assert_eq(captured[1][1], "r3_e1")
