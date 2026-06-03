extends GutTest

# Tests for RemoteKitten character_class wiring (#169). The remote kitten
# scene gains a Sprite2D whose texture is assigned in _ready() via
# SpriteHelper.path_for_class(character_class). The Polygon2D placeholder
# remains in the scene for the pre-PLAYER_INFO window.

const REMOTE_KITTEN_PATH := "res://scenes/remote_kitten.tscn"

func _instance_with_class(cc: int) -> RemoteKitten:
	var scene: PackedScene = load(REMOTE_KITTEN_PATH)
	var inst: RemoteKitten = scene.instantiate()
	inst.character_class = cc
	add_child_autofree(inst)
	return inst

func test_sprite2d_node_exists_in_scene():
	var scene: PackedScene = load(REMOTE_KITTEN_PATH)
	var inst: RemoteKitten = scene.instantiate()
	add_child_autofree(inst)
	assert_not_null(inst.get_node_or_null("Sprite2D"),
		"remote_kitten.tscn must contain a Sprite2D child")

func test_placeholder_polygon_still_present():
	var scene: PackedScene = load(REMOTE_KITTEN_PATH)
	var inst: RemoteKitten = scene.instantiate()
	add_child_autofree(inst)
	assert_not_null(inst.get_node_or_null("Placeholder"),
		"Polygon2D placeholder must remain as fallback")

func test_battle_kitten_assigns_texture():
	var inst := _instance_with_class(CharacterData.CharacterClass.BATTLE_KITTEN)
	var sprite: Sprite2D = inst.get_node("Sprite2D")
	assert_not_null(sprite.texture)
	assert_string_contains(sprite.texture.resource_path, "battle_kitten")

func test_sleepy_kitten_assigns_texture():
	var inst := _instance_with_class(CharacterData.CharacterClass.SLEEPY_KITTEN)
	var sprite: Sprite2D = inst.get_node("Sprite2D")
	assert_not_null(sprite.texture)
	assert_string_contains(sprite.texture.resource_path, "sleepy_kitten")

func test_chonk_kitten_assigns_texture():
	var inst := _instance_with_class(CharacterData.CharacterClass.CHONK_KITTEN)
	var sprite: Sprite2D = inst.get_node("Sprite2D")
	assert_not_null(sprite.texture)
	assert_string_contains(sprite.texture.resource_path, "chonk_kitten")

func test_default_class_assigns_wizard_kitten_texture():
	var scene: PackedScene = load(REMOTE_KITTEN_PATH)
	var inst: RemoteKitten = scene.instantiate()
	add_child_autofree(inst)
	var sprite: Sprite2D = inst.get_node("Sprite2D")
	assert_not_null(sprite.texture, "default class should produce a non-null texture")
	assert_string_contains(sprite.texture.resource_path, "wizard_kitten")


# Slice 2 of PRD #328 (issue #330). apply_facing mirrors player.gd's
# `flip_h = moving_left != SpriteHelper.faces_left(cc)` XOR rule so the
# left-facing-asset classes (battle/chonk/wizard) and the right-facing
# sleepy asset all flip the correct way for a given input sign.

func test_apply_facing_left_on_left_facing_asset_no_flip():
	# Wizard art faces left visually, so when the peer is moving LEFT the
	# sprite must NOT be flipped (flip_h = false) — the artwork is already
	# pointing left.
	var inst := _instance_with_class(CharacterData.CharacterClass.WIZARD_KITTEN)
	inst.apply_facing(-1)
	assert_false(inst.get_node("Sprite2D").flip_h,
		"left-facing asset moving left stays unflipped")


func test_apply_facing_right_on_left_facing_asset_flips():
	# Wizard art faces left → moving RIGHT requires flip_h = true so the
	# rendered kitten appears to face right.
	var inst := _instance_with_class(CharacterData.CharacterClass.WIZARD_KITTEN)
	inst.apply_facing(1)
	assert_true(inst.get_node("Sprite2D").flip_h,
		"left-facing asset moving right is flipped")


func test_apply_facing_battle_kitten_matches_wizard_rule():
	# Battle kitten is the other left-facing asset family; same XOR rule
	# applies — pinned so a future asset re-export of just one class
	# can't silently desync from the others.
	var inst := _instance_with_class(CharacterData.CharacterClass.BATTLE_KITTEN)
	inst.apply_facing(-1)
	assert_false(inst.get_node("Sprite2D").flip_h)
	inst.apply_facing(1)
	assert_true(inst.get_node("Sprite2D").flip_h)


func test_apply_facing_chonk_kitten_matches_wizard_rule():
	var inst := _instance_with_class(CharacterData.CharacterClass.CHONK_KITTEN)
	inst.apply_facing(-1)
	assert_false(inst.get_node("Sprite2D").flip_h)
	inst.apply_facing(1)
	assert_true(inst.get_node("Sprite2D").flip_h)


func test_apply_facing_left_on_right_facing_asset_flips():
	# Sleepy art genuinely faces right, so moving LEFT must flip the
	# sprite (flip_h = true) — the inverse of the wizard rule.
	var inst := _instance_with_class(CharacterData.CharacterClass.SLEEPY_KITTEN)
	inst.apply_facing(-1)
	assert_true(inst.get_node("Sprite2D").flip_h,
		"right-facing asset moving left is flipped")


func test_apply_facing_right_on_right_facing_asset_no_flip():
	# Sleepy moving right matches the asset orientation → no flip.
	var inst := _instance_with_class(CharacterData.CharacterClass.SLEEPY_KITTEN)
	inst.apply_facing(1)
	assert_false(inst.get_node("Sprite2D").flip_h,
		"right-facing asset moving right stays unflipped")


func test_apply_facing_zero_is_no_op():
	# A zero sign — either an in-place peer (data.facing.x == 0) or a
	# packet from a pre-#330 sender (key missing → decoded as 0) — must
	# leave the existing flip state untouched. Confirms a stationary
	# teammate keeps its last facing rather than snapping to a default.
	var inst := _instance_with_class(CharacterData.CharacterClass.WIZARD_KITTEN)
	var sprite: Sprite2D = inst.get_node("Sprite2D")
	# Establish a known non-default state, then assert apply_facing(0)
	# does not mutate it back.
	inst.apply_facing(1)
	assert_true(sprite.flip_h, "precondition: kitten is currently flipped")
	inst.apply_facing(0)
	assert_true(sprite.flip_h, "facing_x = 0 must not change flip state")


func test_apply_facing_reverse_toggles_flip():
	# Direction reversal must flip back — same kitten, opposite signs,
	# back-to-back. Catches a hypothetical regression that only writes
	# the flip on the first call.
	var inst := _instance_with_class(CharacterData.CharacterClass.WIZARD_KITTEN)
	var sprite: Sprite2D = inst.get_node("Sprite2D")
	inst.apply_facing(1)
	assert_true(sprite.flip_h)
	inst.apply_facing(-1)
	assert_false(sprite.flip_h, "reverse direction unflips")
