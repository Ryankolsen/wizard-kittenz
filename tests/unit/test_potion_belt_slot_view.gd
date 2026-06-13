extends GutTest

# Item (potion) hotkeys must read as visually distinct from the ability
# (quickbar) hotkeys. We don't pin exact hues — just guard that the slot
# chrome differs, and that the item palette leans green (G is the dominant
# channel) while the ability palette stays blue-grey.

func test_item_slot_chrome_differs_from_ability_slot():
	assert_ne(PotionBeltSlotView.SLOT_BG_COLOR, QuickbarSlotView.SLOT_BG_COLOR,
		"item slot background must differ from ability slot background")
	assert_ne(PotionBeltSlotView.SLOT_BORDER_COLOR, QuickbarSlotView.SLOT_BORDER_COLOR,
		"item slot border must differ from ability slot border")

func test_item_border_is_green_dominant():
	var c := PotionBeltSlotView.SLOT_BORDER_COLOR
	assert_gt(c.g, c.r, "item border green channel must exceed red")
	assert_gt(c.g, c.b, "item border green channel must exceed blue")
