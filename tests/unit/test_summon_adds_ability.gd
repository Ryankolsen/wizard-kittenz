extends GutTest

# Summon adds archetype (PRD #518 / issue #537). Old Lady Pearl's half: spawns
# 2-3 standard mobs on a cooldown, capped so the room cannot fill without
# bound, with deterministic kinds/count/offsets/ids so co-op clients agree.
# Same _MockEnemy-style mock pattern as tests/unit/test_enemy_behavior.gd.

class _MockData:
	var enemy_id: String = ""

class _MockEnemy:
	var global_position: Vector2 = Vector2.ZERO
	var state: int = 1  # EnemyAIState.State.CHASE
	var data: _MockData = _MockData.new()


func _seeded(enemy_id: String) -> _MockEnemy:
	var e := _MockEnemy.new()
	e.data.enemy_id = enemy_id
	return e


# --- 1. Core wiring ----------------------------------------------------------

func test_summon_published_after_cooldown_with_two_to_three_entries():
	var b := SummonAddsAbility.new()
	var e := _seeded("f3-r1-e0")
	for _i in range(int(ceil(b.cooldown())) + 1):
		b.tick(1.0, e)
	assert_true(b.pending_summons.size() >= 2 and b.pending_summons.size() <= 3,
		"a summon volley should publish between 2 and 3 entries, got %d" % b.pending_summons.size())


# --- 2. Content details -------------------------------------------------------

func test_summon_entries_carry_a_standard_kind_and_an_offset_position():
	var b := SummonAddsAbility.new()
	var e := _seeded("f3-r1-e1")
	e.global_position = Vector2(100.0, 100.0)
	for _i in range(int(ceil(b.cooldown())) + 1):
		b.tick(1.0, e)
	assert_false(b.pending_summons.is_empty(), "precondition: a volley should have published")
	for entry in b.pending_summons:
		assert_true(SummonAddsAbility.STANDARD_MOB_KINDS.has(entry.get("kind")),
			"each entry's kind should be a standard mob kind")
		var pos: Vector2 = entry.get("position")
		assert_ne(pos, e.global_position,
			"each entry's spawn position should be offset from the summoner, not stacked on it")


# --- 3. Cap --------------------------------------------------------------------

func test_alive_add_count_never_exceeds_the_cap():
	var b := SummonAddsAbility.new(1.0, 3)
	var e := _seeded("f3-r1-e2")
	for _i in range(200):
		b.tick(1.0, e)
		assert_true(b.alive_add_count() <= 3,
			"alive add count must never exceed the cap, got %d" % b.alive_add_count())


# --- 4. Determinism ------------------------------------------------------------

func test_same_enemy_id_produces_identical_kinds_count_and_offsets():
	var a := SummonAddsAbility.new()
	var b := SummonAddsAbility.new()
	var batch_a := a.roll_summon_batch(_seeded("f3-r2-e5"))
	var batch_b := b.roll_summon_batch(_seeded("f3-r2-e5"))
	assert_eq(batch_a.size(), batch_b.size(), "same enemy_id should roll the same count")
	for i in range(batch_a.size()):
		assert_eq(batch_a[i].get("kind"), batch_b[i].get("kind"),
			"same enemy_id should roll the same kind at index %d" % i)
		assert_eq(batch_a[i].get("offset"), batch_b[i].get("offset"),
			"same enemy_id should roll the same offset at index %d" % i)


func test_different_enemy_ids_do_not_share_one_sequence():
	var differs := false
	for i in range(3):
		var a := SummonAddsAbility.new()
		var b := SummonAddsAbility.new()
		var batch_a := a.roll_summon_batch(_seeded("f3-r2-e%d-x" % i))
		var batch_b := b.roll_summon_batch(_seeded("f3-r2-e%d-y" % i))
		if batch_a.size() != batch_b.size():
			differs = true
			break
		for j in range(batch_a.size()):
			if batch_a[j].get("kind") != batch_b[j].get("kind") \
					or batch_a[j].get("offset") != batch_b[j].get("offset"):
				differs = true
				break
	assert_true(differs, "different enemy_ids must not roll identical summon batches")


# --- 5. Edge cases ---------------------------------------------------------------

func test_idle_enemy_publishes_nothing():
	var b := SummonAddsAbility.new()
	var e := _seeded("f3-r1-e3")
	e.state = 0  # IDLE
	for _i in range(int(ceil(b.cooldown())) + 5):
		b.tick(1.0, e)
	assert_true(b.pending_summons.is_empty(), "IDLE enemy must not publish a summon request")


func test_dead_enemy_publishes_nothing():
	var b := SummonAddsAbility.new()
	var e := _seeded("f3-r1-e4")
	e.state = 3  # DEAD
	for _i in range(int(ceil(b.cooldown())) + 5):
		b.tick(1.0, e)
	assert_true(b.pending_summons.is_empty(), "DEAD enemy must not publish a summon request")


func test_null_enemy_does_not_crash():
	var b := SummonAddsAbility.new()
	b.tick(1.0, null)
	assert_true(b.pending_summons.is_empty(), "null enemy must not crash and must not publish")


# --- 6. Second consumer (issue #576) ---------------------------------------------

func test_karaoke_karen_reuses_the_unmodified_archetype_with_an_independent_cap():
	# Test 11 (second consumer, issue #576): Karaoke Karen composes this same
	# archetype unmodified (AbilityLoadout.karaoke_karen_loadout), and her
	# alive-add cap must be tracked on her own instance, independent of
	# whatever Old Lady Pearl's own summoner has already summoned.
	var karen_summoner := SummonAddsAbility.new()
	var e := _seeded("karen-e0")
	for _i in range(int(ceil(karen_summoner.cooldown())) + 1):
		karen_summoner.tick(1.0, e)
	assert_true(
		karen_summoner.pending_summons.size() >= 2 and karen_summoner.pending_summons.size() <= 3,
		"Karen's summon tuning must still produce a valid 2-3 entry batch through the unmodified archetype")

	var pearl_summoner := SummonAddsAbility.new()
	var pearl_enemy := _seeded("pearl-e0")
	for _i in range(400):
		pearl_summoner.tick(1.0, pearl_enemy)
	assert_eq(pearl_summoner.alive_add_count(), SummonAddsAbility.CAP,
		"precondition: Pearl's own summoner should have filled her own cap")
	assert_lt(karen_summoner.alive_add_count(), SummonAddsAbility.CAP + 1,
		"precondition: Karen's cap tracking is sane on its own")
	assert_ne(karen_summoner.alive_add_count(), 0,
		"precondition: Karen's summoner should have summoned something by now")
	# The two summoners never share bookkeeping: driving Pearl's instance to
	# its cap must not have moved Karen's independent count.
	var karen_count_before_pearl_drive := karen_summoner.alive_add_count()
	for _i in range(400):
		pearl_summoner.tick(1.0, pearl_enemy)
	assert_eq(karen_summoner.alive_add_count(), karen_count_before_pearl_drive,
		"driving Pearl's summoner further must not change Karen's independently-tracked cap")
