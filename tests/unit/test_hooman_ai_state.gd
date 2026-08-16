extends GutTest

const _State := HoomanAIState.State

# --- Pure state machine: HoomanAIState.next_state ---

func test_follow_transitions_to_chase_when_mob_enters_detection_radius():
	# Acceptance #1: Follow -> Chase when a mob enters the detection radius.
	var inside := HoomanAIState.DETECTION_RADIUS - 5.0
	var s := HoomanAIState.next_state(_State.FOLLOW, inside, 1.0, true)
	assert_eq(s, _State.CHASE, "mob in detection range -> CHASE")

func test_chase_transitions_to_attack_within_melee_range():
	# Acceptance #2: Chase -> Attack once the mob is within melee range.
	var melee := HoomanAIState.MELEE_RANGE - 1.0
	var s := HoomanAIState.next_state(_State.CHASE, melee, 1.0, true)
	assert_eq(s, _State.ATTACK)

func test_heal_preempts_attack_when_player_hp_below_threshold():
	# Acceptance #3: HEAL wins even mid-combat.
	var melee := HoomanAIState.MELEE_RANGE - 1.0
	var low_hp := HoomanAIState.HEAL_HP_THRESHOLD - 0.05
	var s := HoomanAIState.next_state(_State.ATTACK, melee, low_hp, true)
	assert_eq(s, _State.HEAL)

func test_follow_stays_follow_when_no_mob_in_range_and_hp_healthy():
	# Acceptance #4: default is FOLLOW when nothing is in range and HP is fine.
	var outside := HoomanAIState.DETECTION_RADIUS + 50.0
	var s := HoomanAIState.next_state(_State.FOLLOW, outside, 1.0, true)
	assert_eq(s, _State.FOLLOW)

func test_inactive_forces_follow_regardless_of_mob_distance_or_low_hp():
	# Acceptance #5: unpaid-floor gate wins over both mob-in-range and low-HP.
	var melee := HoomanAIState.MELEE_RANGE - 1.0
	var s := HoomanAIState.next_state(_State.ATTACK, melee, 0.1, false)
	assert_eq(s, _State.FOLLOW,
		"inactive rental forces FOLLOW even with a mob in melee and low player HP")

func test_constants_are_sensible():
	# Acceptance #6: guard against a tuning typo breaking the state geometry.
	assert_lt(HoomanAIState.MELEE_RANGE, HoomanAIState.DETECTION_RADIUS,
		"melee must be a tighter ring than detection")
	assert_gt(HoomanAIState.ATTACK_COOLDOWN, 0.0)
	assert_gt(HoomanAIState.HEAL_COOLDOWN, 0.0)
	assert_gt(HoomanAIState.HEAL_HP_THRESHOLD, 0.0)
	assert_lt(HoomanAIState.HEAL_HP_THRESHOLD, 1.0)

func test_state_name_returns_human_readable_strings():
	assert_eq(HoomanAIState.state_name(_State.FOLLOW), "Follow")
	assert_eq(HoomanAIState.state_name(_State.CHASE), "Chase")
	assert_eq(HoomanAIState.state_name(_State.ATTACK), "Attack")
	assert_eq(HoomanAIState.state_name(_State.HEAL), "Heal")
