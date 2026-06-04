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


# --- Slice 3 of PRD #328 (issue #331): equipped weapon visual ----------------

# A WeaponPivot's child weapon Sprite2D — same path Player walks in
# scripts/core/player.gd:_refresh_combat_weapon (line 193). Mirrors the
# helper from test_player_weapon_loadout._combat_weapon_sprite.
func _weapon_sprite(inst: RemoteKitten) -> Sprite2D:
	if inst.weapon_pivot == null:
		return null
	return inst.weapon_pivot.get_node_or_null("Sprite2D") as Sprite2D


func test_apply_equipped_weapon_swaps_sprite_to_resolved_texture():
	# Battle kitten holding a Slippery Mackerel → weapon sprite shows the
	# per-id mackerel texture, not a class-default. Mirrors the local
	# Player path in test_player_weapon_loadout.test_equipping_iron_sword.
	var inst := _instance_with_class(CharacterData.CharacterClass.BATTLE_KITTEN)
	inst.apply_equipped_weapon("iron_sword")
	var ws := _weapon_sprite(inst)
	assert_true(ws.visible, "armed remote kitten must show the weapon sprite")
	assert_not_null(ws.texture)
	assert_eq(ws.texture.resource_path,
		"res://assets/sprites/weapon_slippery_mackerel.png",
		"weapon sprite uses the per-id texture from HeldWeaponResolver")


func test_apply_equipped_weapon_uses_held_weapon_resolver_definition():
	# Definition routes through HeldWeaponResolver.resolve so the pose
	# matches whatever the local Player path produces for the same input.
	# Pin equality with the resolver to forbid a parallel co-op-only
	# weapon-resolution path.
	var inst := _instance_with_class(CharacterData.CharacterClass.BATTLE_KITTEN)
	inst.apply_equipped_weapon("iron_sword")
	var expected_def: WeaponDefinition = HeldWeaponResolver.resolve(
		ItemCatalog.find("iron_sword"),
		CharacterData.CharacterClass.BATTLE_KITTEN
	)[HeldWeaponResolver.DEFINITION_KEY]
	# WeaponDefinition.for_class returns a fresh Resource per call, so
	# direct equality on the instances fails. Comparing attack_type +
	# anchor_offset is enough to prove the resolver's per-weapon pose
	# routed through (vs a parallel co-op-only path picking a different
	# pose for the same iron_sword).
	assert_eq(inst.weapon_pivot.definition.attack_type, expected_def.attack_type,
		"definition.attack_type must match HeldWeaponResolver.resolve")
	assert_eq(inst.weapon_pivot.definition.anchor_offset, expected_def.anchor_offset,
		"definition.anchor_offset must match HeldWeaponResolver.resolve")


# Edge: empty equipped_weapon_id falls back to class-default WeaponDefinition
# and the weapon sprite stays hidden (matches solo behavior — Player's
# _refresh_combat_weapon hides the sprite when unarmed).
func test_apply_equipped_weapon_empty_falls_back_to_class_default_definition():
	var inst := _instance_with_class(CharacterData.CharacterClass.BATTLE_KITTEN)
	# First arm it so we can prove the empty call clears the sprite.
	inst.apply_equipped_weapon("iron_sword")
	var ws := _weapon_sprite(inst)
	assert_true(ws.visible, "precondition: weapon visible")
	# Then disarm.
	inst.apply_equipped_weapon("")
	var class_def := WeaponDefinition.for_class(CharacterData.CharacterClass.BATTLE_KITTEN)
	assert_eq(inst.weapon_pivot.definition.attack_type, class_def.attack_type,
		"empty equipped_weapon_id reverts the pose to class-default "
		+ "WeaponDefinition.for_class — same as the unarmed Player path")
	assert_eq(inst.weapon_pivot.definition.anchor_offset, class_def.anchor_offset,
		"class-default anchor restored on disarm")
	assert_false(ws.visible,
		"empty equipped_weapon_id hides the weapon sprite (matches "
		+ "Player._refresh_combat_weapon's unarmed branch)")


func test_apply_equipped_weapon_no_ops_for_class_without_weapon_definition():
	# Cat-tier classes have no WeaponDefinition, so _init_weapon_pivot
	# never spawned a pivot. apply_equipped_weapon must not crash.
	var inst := _instance_with_class(CharacterData.CharacterClass.BATTLE_CAT)
	assert_null(inst.weapon_pivot,
		"precondition: cat-tier has no weapon_pivot")
	inst.apply_equipped_weapon("iron_sword")
	assert_null(inst.weapon_pivot,
		"apply_equipped_weapon must not spawn a pivot on cat-tier")


# ---- Slice 5 of PRD #328 (issue #333): play_spell_cast receive path. ----

func test_play_spell_cast_drives_choreographer_off_idle():
	# Spell cast packets (wizard primary, quickbar) route through
	# play_spell_cast which must drive the same AttackChoreographer
	# play_attack uses — the cast pose IS the visible cast effect today.
	var inst := _instance_with_class(CharacterData.CharacterClass.WIZARD_KITTEN)
	assert_not_null(inst.attack_choreographer,
		"precondition: wizard has a choreographer")
	assert_eq(inst.attack_choreographer.phase, AttackChoreographer.Phase.IDLE)
	inst.play_spell_cast(Vector2.RIGHT, "fireball")
	assert_ne(inst.attack_choreographer.phase, AttackChoreographer.Phase.IDLE,
		"play_spell_cast must start the choreographer (cast pose)")


func test_play_spell_cast_empty_spell_id_still_plays_pose():
	# Wizard primary (empty spell_id by design) still plays the pose
	# — the pose comes from the choreographer's CAST attack_type, not
	# from a Spell lookup. Empty spell_id is NOT a no-op guard here.
	var inst := _instance_with_class(CharacterData.CharacterClass.WIZARD_KITTEN)
	inst.play_spell_cast(Vector2.RIGHT, "")
	assert_ne(inst.attack_choreographer.phase, AttackChoreographer.Phase.IDLE,
		"empty spell_id (wizard primary) still drives the cast pose")


func test_play_spell_cast_no_op_for_class_without_choreographer():
	# Cat-tier (no WeaponDefinition → no choreographer) must not crash.
	var inst := _instance_with_class(CharacterData.CharacterClass.BATTLE_CAT)
	assert_null(inst.attack_choreographer,
		"precondition: cat-tier has no choreographer")
	inst.play_spell_cast(Vector2.RIGHT, "fireball")
	assert_true(true, "no-crash on missing choreographer")
