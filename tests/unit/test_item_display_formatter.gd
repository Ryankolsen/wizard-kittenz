extends GutTest

# Tests for ItemDisplayFormatter — PRD #292, Slice #293.

const _COMMON_BORDER := Color(0.72, 0.74, 0.78, 0.95)
const _RARE_BORDER := Color(0.36, 0.56, 0.95, 0.95)
const _EPIC_BORDER := Color(0.74, 0.42, 0.96, 0.95)

func _make_single(stat: String, value: float, rarity: int = ItemData.Rarity.COMMON, name: String = "Test Sword") -> ItemData:
	return ItemData.make("test_id", name, ItemData.Slot.WEAPON, rarity, stat, value)

func test_core_wiring_single_bonus_common():
	var item := _make_single("attack", 2.0)
	assert_eq(ItemDisplayFormatter.display_name(item), "Test Sword")
	assert_eq(ItemDisplayFormatter.rarity_label(item), "Common")
	assert_eq(ItemDisplayFormatter.bonus_lines(item), ["+2 Attack"] as Array[String])

func test_humanize_magic_attack():
	assert_eq(ItemDisplayFormatter.bonus_lines(_make_single("magic_attack", 1.0))[0], "+1 Magic Attack")

func test_humanize_magic_resistance():
	assert_eq(ItemDisplayFormatter.bonus_lines(_make_single("magic_resistance", 1.0))[0], "+1 Magic Resistance")

func test_humanize_crit_chance():
	assert_eq(ItemDisplayFormatter.bonus_lines(_make_single("crit_chance", 1.0))[0], "+1 Crit Chance")

func test_humanize_max_hp_is_uppercase():
	assert_eq(ItemDisplayFormatter.bonus_lines(_make_single("max_hp", 1.0))[0], "+1 Max HP")

func test_humanize_max_mp_is_uppercase():
	assert_eq(ItemDisplayFormatter.bonus_lines(_make_single("max_mp", 1.0))[0], "+1 Max MP")

func test_humanize_mp_regen_is_uppercase():
	assert_eq(ItemDisplayFormatter.bonus_lines(_make_single("mp_regen", 1.0))[0], "+1 MP Regen")

func test_humanize_regeneration():
	assert_eq(ItemDisplayFormatter.bonus_lines(_make_single("regeneration", 1.0))[0], "+1 Regeneration")

func test_integer_bonus_has_no_decimals():
	assert_eq(ItemDisplayFormatter.bonus_lines(_make_single("attack", 2.0))[0], "+2 Attack")

func test_fractional_bonus_has_two_decimals():
	assert_eq(ItemDisplayFormatter.bonus_lines(_make_single("evasion", 0.08))[0], "+0.08 Evasion")

func test_multi_bonus_preserves_order():
	var item := ItemData.make_multi(
		"multi", "Comet Caller", ItemData.Slot.WEAPON, ItemData.Rarity.RARE,
		[StatBonus.make("attack", 4.0), StatBonus.make("magic_attack", 4.0)]
	)
	assert_eq(ItemDisplayFormatter.bonus_lines(item), ["+4 Attack", "+4 Magic Attack"] as Array[String])

func test_rarity_label_and_color_common():
	var item := _make_single("attack", 1.0, ItemData.Rarity.COMMON)
	assert_eq(ItemDisplayFormatter.rarity_label(item), "Common")
	assert_eq(ItemDisplayFormatter.rarity_color(item), _COMMON_BORDER)

func test_rarity_label_and_color_rare():
	var item := _make_single("attack", 1.0, ItemData.Rarity.RARE)
	assert_eq(ItemDisplayFormatter.rarity_label(item), "Rare")
	assert_eq(ItemDisplayFormatter.rarity_color(item), _RARE_BORDER)

func test_rarity_label_and_color_epic():
	var item := _make_single("attack", 1.0, ItemData.Rarity.EPIC)
	assert_eq(ItemDisplayFormatter.rarity_label(item), "Epic")
	assert_eq(ItemDisplayFormatter.rarity_color(item), _EPIC_BORDER)

func test_unmapped_stat_falls_back_to_title_case():
	var item := ItemData.make("frost", "Frost Blade", ItemData.Slot.WEAPON, ItemData.Rarity.COMMON, "frost_power", 3.0)
	assert_eq(ItemDisplayFormatter.bonus_lines(item)[0], "+3 Frost Power")
