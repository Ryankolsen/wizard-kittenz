extends GutTest

# CharacterAvatar (PRD #268 / issue #270). Renders a kitten body sprite
# plus a held weapon, sourcing the weapon texture through
# ItemImageResolver and reusing WeaponPivot's resting pose so the
# weapon reads as held. These tests pin the loadout/visibility/texture
# contract at the node level; pixel-accurate placement is verified in
# the manual QA slice.

const SwordTex := "res://assets/sprites/weapon_slippery_mackerel.png"
const WandTex := "res://assets/sprites/weapon_wand_sprite.png"
const MugTex := "res://assets/sprites/weapon_mug_sprite.png"

func _make_avatar() -> CharacterAvatar:
	var a := CharacterAvatar.new()
	add_child_autofree(a)
	return a

func _weapon_sprite(a: CharacterAvatar) -> Sprite2D:
	var pivot := a.find_child("WeaponPivot", true, false)
	if pivot == null:
		return null
	return pivot.get_node_or_null("Sprite2D") as Sprite2D

func _body_sprite(a: CharacterAvatar) -> Sprite2D:
	return a.find_child("Body", true, false) as Sprite2D

func test_set_loadout_battle_kitten_with_sword_shows_sword_texture():
	var a := _make_avatar()
	a.set_loadout(CharacterData.CharacterClass.BATTLE_KITTEN, ItemCatalog.find("iron_sword"))
	var ws := _weapon_sprite(a)
	assert_not_null(ws, "weapon sprite must exist")
	assert_true(ws.visible, "weapon sprite must be visible when weapon equipped")
	assert_not_null(ws.texture, "weapon texture must be loaded")
	assert_eq(ws.texture.resource_path, SwordTex)

func test_body_uses_sprite_helper_for_wizard_class():
	var a := _make_avatar()
	a.set_loadout(CharacterData.CharacterClass.WIZARD_KITTEN, null)
	var body := _body_sprite(a)
	assert_not_null(body, "body sprite must exist")
	assert_not_null(body.texture, "body texture must be loaded")
	assert_eq(
		body.texture.resource_path,
		SpriteHelper.path_for_class(CharacterData.CharacterClass.WIZARD_KITTEN)
	)

func test_chonk_with_heavy_club_shows_mug_texture():
	var a := _make_avatar()
	a.set_loadout(CharacterData.CharacterClass.CHONK_KITTEN, ItemCatalog.find("heavy_club"))
	var ws := _weapon_sprite(a)
	assert_not_null(ws.texture)
	assert_eq(ws.texture.resource_path, MugTex)

func test_no_weapon_hides_weapon_sprite():
	var a := _make_avatar()
	a.set_loadout(CharacterData.CharacterClass.BATTLE_KITTEN, null)
	var ws := _weapon_sprite(a)
	assert_not_null(ws)
	assert_false(ws.visible, "weapon sprite must be hidden when no weapon equipped")

func test_live_update_via_loadout_changed_signal():
	var inv := ItemInventory.new()
	var a := _make_avatar()
	a.bind(CharacterData.CharacterClass.BATTLE_KITTEN, inv)
	var ws := _weapon_sprite(a)
	assert_false(ws.visible, "no weapon at bind time → hidden")
	inv.equip(ItemCatalog.find("iron_sword"))
	assert_true(ws.visible, "equipping must show the weapon sprite live")
	assert_eq(ws.texture.resource_path, SwordTex)
	inv.unequip(ItemData.Slot.WEAPON)
	assert_false(ws.visible, "unequipping must hide the weapon sprite live")
