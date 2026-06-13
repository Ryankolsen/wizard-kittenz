extends GutTest

# Item (potion) hotkeys must read as visually distinct from the ability
# (quickbar) hotkeys. We don't pin exact hues — just guard that the slot
# chrome differs, and that the item palette reads bright yellow (high red +
# green, low blue) while the ability palette stays blue-grey.

func test_item_slot_chrome_differs_from_ability_slot():
	assert_ne(PotionBeltSlotView.SLOT_BG_COLOR, QuickbarSlotView.SLOT_BG_COLOR,
		"item slot background must differ from ability slot background")
	assert_ne(PotionBeltSlotView.SLOT_BORDER_COLOR, QuickbarSlotView.SLOT_BORDER_COLOR,
		"item slot border must differ from ability slot border")

func test_item_border_is_yellow():
	var c := PotionBeltSlotView.SLOT_BORDER_COLOR
	assert_gt(c.r, 0.7, "item border red channel must be high (yellow)")
	assert_gt(c.g, 0.7, "item border green channel must be high (yellow)")
	assert_lt(c.b, 0.4, "item border blue channel must be low (yellow)")
