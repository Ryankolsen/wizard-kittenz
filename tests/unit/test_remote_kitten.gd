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
