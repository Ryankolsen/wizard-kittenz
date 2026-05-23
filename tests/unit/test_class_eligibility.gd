extends GutTest

const _CC := CharacterData.CharacterClass

func _item_for(classes: Array) -> ItemData:
	return ItemData.make("t_item", "Test Item", ItemData.Slot.WEAPON, ItemData.Rarity.COMMON, "attack", 1.0, classes)

func test_wizard_item_allows_wizard_blocks_battle():
	var item := _item_for([_CC.WIZARD_KITTEN])
	assert_true(ClassEligibility.is_class_allowed(item, _CC.WIZARD_KITTEN))
	assert_false(ClassEligibility.is_class_allowed(item, _CC.BATTLE_KITTEN))

func test_cat_tier_inherits_kitten_eligibility():
	var battle_item := _item_for([_CC.BATTLE_KITTEN])
	assert_true(ClassEligibility.is_class_allowed(battle_item, _CC.BATTLE_CAT))
	var wizard_item := _item_for([_CC.WIZARD_KITTEN])
	assert_true(ClassEligibility.is_class_allowed(wizard_item, _CC.WIZARD_CAT))
	var sleepy_item := _item_for([_CC.SLEEPY_KITTEN])
	assert_true(ClassEligibility.is_class_allowed(sleepy_item, _CC.SLEEPY_CAT))
	var chonk_item := _item_for([_CC.CHONK_KITTEN])
	assert_true(ClassEligibility.is_class_allowed(chonk_item, _CC.CHONK_CAT))

func test_cat_does_not_inherit_other_kitten_class():
	var battle_item := _item_for([_CC.BATTLE_KITTEN])
	assert_false(ClassEligibility.is_class_allowed(battle_item, _CC.WIZARD_CAT))
	assert_false(ClassEligibility.is_class_allowed(battle_item, _CC.CHONK_CAT))

func test_generic_item_allows_all_eight_classes():
	var generic := _item_for([
		_CC.BATTLE_KITTEN, _CC.WIZARD_KITTEN, _CC.SLEEPY_KITTEN, _CC.CHONK_KITTEN,
	])
	for klass in [_CC.BATTLE_KITTEN, _CC.WIZARD_KITTEN, _CC.SLEEPY_KITTEN, _CC.CHONK_KITTEN,
			_CC.BATTLE_CAT, _CC.WIZARD_CAT, _CC.SLEEPY_CAT, _CC.CHONK_CAT]:
		assert_true(ClassEligibility.is_class_allowed(generic, klass), "class %d should be allowed" % klass)

func test_empty_allowed_classes_blocks_everyone():
	var item := _item_for([])
	for klass in [_CC.BATTLE_KITTEN, _CC.WIZARD_KITTEN, _CC.SLEEPY_KITTEN, _CC.CHONK_KITTEN,
			_CC.BATTLE_CAT, _CC.WIZARD_CAT, _CC.SLEEPY_CAT, _CC.CHONK_CAT]:
		assert_false(ClassEligibility.is_class_allowed(item, klass))

func test_null_item_returns_false():
	assert_false(ClassEligibility.is_class_allowed(null, _CC.BATTLE_KITTEN))
