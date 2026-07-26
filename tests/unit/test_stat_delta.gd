extends GutTest

# --- StatDelta.compute pure helper -------------------------------------------

func test_compute_returns_entry_per_stat():
	var result := StatDelta.compute(
		{"max_hp": 10, "attack": 7, "defense": 1, "speed": 70.0},
		{"max_hp": 12, "attack": 9, "defense": 2, "speed": 75.0}
	)
	assert_eq(result.size(), 4)

func test_compute_reports_correct_deltas():
	var result := StatDelta.compute(
		{"max_hp": 10, "attack": 7, "defense": 1, "speed": 70.0},
		{"max_hp": 12, "attack": 9, "defense": 2, "speed": 75.0}
	)
	var by_label := {}
	for entry in result:
		by_label[entry["label"]] = entry

	assert_eq(by_label["Max HP"]["old_value"], 10.0)
	assert_eq(by_label["Max HP"]["new_value"], 12.0)
	assert_eq(by_label["Max HP"]["delta"], 2.0)
	assert_eq(by_label["Attack"]["delta"], 2.0)
	assert_eq(by_label["Defense"]["delta"], 1.0)
	assert_eq(by_label["Speed"]["delta"], 5.0)

func test_compute_labels_are_human_readable():
	var result := StatDelta.compute(
		{"max_hp": 10, "attack": 7, "defense": 1, "speed": 70.0},
		{"max_hp": 12, "attack": 9, "defense": 2, "speed": 75.0}
	)
	var labels := []
	for entry in result:
		labels.append(entry["label"])
	assert_eq(labels, ["Max HP", "Attack", "Defense", "Speed"])

func test_compute_zero_delta_stat_still_included():
	var result := StatDelta.compute(
		{"max_hp": 10, "attack": 7, "defense": 1, "speed": 70.0},
		{"max_hp": 12, "attack": 9, "defense": 1, "speed": 75.0}
	)
	var defense_entry = null
	for entry in result:
		if entry["label"] == "Defense":
			defense_entry = entry
	assert_not_null(defense_entry, "Defense entry should still be present")
	assert_eq(defense_entry["delta"], 0.0)

func test_compute_missing_key_defaults_to_zero():
	var result := StatDelta.compute(
		{"max_hp": 10, "attack": 7, "defense": 1, "speed": 70.0},
		{}
	)
	for entry in result:
		assert_eq(entry["new_value"], 0.0)
