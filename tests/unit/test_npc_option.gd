extends GutTest

# Issue #195: pure-data NPCOption / NPCOptionList. These tests cover construction,
# the lazy is_enabled predicate, and list helpers. No scene tree.

func test_option_holds_label_and_effect_id():
	var opt := NPCOption.make("Shop", "open_shop")
	assert_eq(opt.label, "Shop")
	assert_eq(opt.effect_id, "open_shop")


func test_option_enabled_by_default_when_no_predicate():
	var opt := NPCOption.make("Exit", "close")
	assert_true(opt.is_enabled(), "options with no predicate default to enabled")


func test_option_enabled_predicate_evaluated_lazily():
	# Proves the predicate is re-evaluated on each is_enabled() call rather than
	# snapshotted at construction — mutating the dict after make() must flip
	# the answer.
	var state := {"gold": 10}
	var predicate := func() -> bool: return state["gold"] >= 25
	var opt := NPCOption.make("Get a beer", "buy_beer", predicate, NPCOption.CurrencyType.GOLD, 25)
	assert_false(opt.is_enabled(), "10 gold < 25 cost -> disabled")
	state["gold"] = 50
	assert_true(opt.is_enabled(), "50 gold >= 25 cost -> enabled after mutation")


func test_list_size_and_indexing():
	var a := NPCOption.make("Shop", "open_shop")
	var b := NPCOption.make("Get a beer", "buy_beer")
	var c := NPCOption.make("Exit", "close")
	var list := NPCOptionList.make([a, b, c])
	assert_eq(list.size(), 3)
	assert_eq(list.get(1).label, "Get a beer")


func test_list_enabled_indices_skips_disabled():
	var always_off := func() -> bool: return false
	var a := NPCOption.make("Shop", "open_shop")
	var b := NPCOption.make("Get a beer", "buy_beer", always_off)
	var c := NPCOption.make("Exit", "close")
	var list := NPCOptionList.make([a, b, c])
	assert_eq(list.enabled_indices(), [0, 2] as Array[int])


func test_list_empty_enabled_indices_when_all_disabled():
	var off := func() -> bool: return false
	var list := NPCOptionList.make([
		NPCOption.make("A", "a", off),
		NPCOption.make("B", "b", off),
	])
	assert_eq(list.enabled_indices(), [] as Array[int])
