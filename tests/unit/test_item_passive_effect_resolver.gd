extends GutTest

# Issue #459: ItemPassiveEffectResolver dispatches an equipped item's passive
# effect by item id, mirroring SpellEffectResolver's "dispatch by id" shape
# (Catnip Curse, Iron Hide, etc.) but for item passives instead of spells.
# Scene-tree-free — CharacterData stands in for the caster, same convention
# as test_spell_effect_resolver.gd.

func _caster() -> CharacterData:
	return CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN)

func test_resolve_dispatches_guardians_locket_to_lifesteal():
	var caster := _caster()
	caster.hp = 1
	caster.max_hp = 100
	ItemPassiveEffectResolver.resolve("guardians_locket", caster, 100)
	assert_true(caster.hp > 1, "guardians_locket dispatches to the Lifesteal handler and heals the caster")

func test_resolve_unrecognized_item_id_is_no_op():
	var caster := _caster()
	caster.hp = 1
	caster.max_hp = 100
	ItemPassiveEffectResolver.resolve("not_a_real_item", caster, 100)
	assert_eq(caster.hp, 1, "unrecognized item id is a no-op, not an error")
