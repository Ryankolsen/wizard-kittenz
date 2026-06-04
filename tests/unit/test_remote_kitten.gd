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


# ---- Slice 7 of PRD #328 (issue #335): apply_hit_reaction. ----

func test_apply_hit_reaction_flashes_sprite_modulate_white():
	# Hit reaction immediately sets the sprite modulate to the flash
	# color (the tween restores it; we sample before the tween runs).
	var inst := _instance_with_class(CharacterData.CharacterClass.BATTLE_KITTEN)
	inst.global_position = Vector2(100.0, 0.0)
	inst.apply_hit_reaction(5, Vector2.ZERO)
	var sprite: Sprite2D = inst.get_node("Sprite2D")
	assert_almost_eq(sprite.modulate.r, RemoteKitten.HIT_FLASH_COLOR.r, 0.01)
	assert_almost_eq(sprite.modulate.g, RemoteKitten.HIT_FLASH_COLOR.g, 0.01)
	assert_almost_eq(sprite.modulate.b, RemoteKitten.HIT_FLASH_COLOR.b, 0.01)


func test_apply_hit_reaction_knockback_points_away_from_source():
	# Source at (0, 0), kitten at (100, 0) -> knockback offset must
	# point in the +X direction (away from source).
	var inst := _instance_with_class(CharacterData.CharacterClass.BATTLE_KITTEN)
	inst.global_position = Vector2(100.0, 0.0)
	inst.apply_hit_reaction(5, Vector2.ZERO)
	var sprite: Sprite2D = inst.get_node("Sprite2D")
	assert_gt(sprite.position.x, 0.0,
		"knockback offset must push away from a source on the left")
	assert_almost_eq(sprite.position.y, 0.0, 0.01,
		"horizontal source means no vertical knockback component")


func test_apply_hit_reaction_knockback_other_direction():
	# Source at (200, 0), kitten at (100, 0) -> knockback in -X.
	# Pins that the direction sign correctly tracks source_position rather
	# than always defaulting to RIGHT.
	var inst := _instance_with_class(CharacterData.CharacterClass.BATTLE_KITTEN)
	inst.global_position = Vector2(100.0, 0.0)
	inst.apply_hit_reaction(5, Vector2(200.0, 0.0))
	var sprite: Sprite2D = inst.get_node("Sprite2D")
	assert_lt(sprite.position.x, 0.0,
		"knockback offset must push away from a source on the right")


func test_apply_hit_reaction_non_positive_damage_no_op():
	# A "Miss" pulse on the wire (defense-in-depth — should be dropped at
	# the route layer already) is a no-op at the visual layer too.
	var inst := _instance_with_class(CharacterData.CharacterClass.BATTLE_KITTEN)
	var sprite: Sprite2D = inst.get_node("Sprite2D")
	var pre_modulate := sprite.modulate
	inst.apply_hit_reaction(0, Vector2.ZERO)
	assert_eq(sprite.modulate, pre_modulate,
		"zero-damage hit must not flash the sprite")
	inst.apply_hit_reaction(-3, Vector2.ZERO)
	assert_eq(sprite.modulate, pre_modulate,
		"negative-damage hit must not flash the sprite")


func test_apply_hit_reaction_zero_distance_defaults_to_right():
	# Defensive: when source_position equals the kitten's position
	# (zero-length direction vector) the knockback falls back to
	# Vector2.RIGHT rather than NaN-ing out the position.
	var inst := _instance_with_class(CharacterData.CharacterClass.BATTLE_KITTEN)
	inst.global_position = Vector2(100.0, 0.0)
	inst.apply_hit_reaction(5, Vector2(100.0, 0.0))
	var sprite: Sprite2D = inst.get_node("Sprite2D")
	assert_gt(sprite.position.x, 0.0,
		"zero-length direction defaults to RIGHT so the offset is still finite")


# ---- Slice 8 of PRD #328 (issue #336): apply_death + revive. ----

# Stub network_sync that returns a configurable position on demand so the
# _process freeze can be observed independently of NetworkSyncManager's
# interpolation rules.
class _FakeSync:
	extends RefCounted
	var current_position: Vector2 = Vector2.ZERO
	var sample_count: int = 0
	func get_display_position_at(_pid: String, _now: float) -> Vector2:
		sample_count += 1
		return current_position


func test_apply_death_sets_is_dead_flag():
	# Death state is observable via is_dead() so the layer / revive path
	# can branch on it.
	var inst := _instance_with_class(CharacterData.CharacterClass.BATTLE_KITTEN)
	assert_false(inst.is_dead(), "fresh kitten is alive")
	inst.apply_death()
	assert_true(inst.is_dead(), "apply_death flips the is_dead flag")


func test_apply_death_modulates_sprite_to_dead_tint():
	# The death visual is a sprite modulate shift to the DEAD_TINT so the
	# kitten reads as visually inert. Same shape as apply_hit_reaction's
	# modulate change but persistent (no tween back to white).
	var inst := _instance_with_class(CharacterData.CharacterClass.BATTLE_KITTEN)
	inst.apply_death()
	var sprite: Sprite2D = inst.get_node("Sprite2D")
	assert_eq(sprite.modulate, RemoteKitten.DEAD_TINT,
		"sprite modulate must shift to DEAD_TINT on death")


func test_apply_death_freezes_position_sampling():
	# After apply_death, _process must NOT consult network_sync for a new
	# position — the kitten stays frozen at the death pose. Pinned via a
	# sample-counter stub.
	var inst := _instance_with_class(CharacterData.CharacterClass.BATTLE_KITTEN)
	var sync := _FakeSync.new()
	sync.current_position = Vector2(50.0, 50.0)
	inst.network_sync = sync
	inst.player_id = "alice"
	# Pre-death tick samples normally.
	inst._process(0.016)
	assert_eq(sync.sample_count, 1, "live kitten samples each frame")
	inst.apply_death()
	var frozen_at := inst.position
	# Advance the "remote" position to confirm the freeze doesn't follow.
	sync.current_position = Vector2(999.0, 999.0)
	inst._process(0.016)
	assert_eq(sync.sample_count, 1,
		"dead kitten must NOT sample network_sync")
	assert_eq(inst.position, frozen_at,
		"dead kitten's position must stay frozen at the death pose")


func test_apply_revive_resumes_position_sampling():
	# Slice 8 AC: when an OP_POSITION packet arrives for a previously-dead
	# kitten, apply_revive resumes the normal sampling loop. The dead-
	# state freeze is purely visual; it doesn't gate inbound packets.
	var inst := _instance_with_class(CharacterData.CharacterClass.BATTLE_KITTEN)
	var sync := _FakeSync.new()
	sync.current_position = Vector2(50.0, 50.0)
	inst.network_sync = sync
	inst.player_id = "alice"
	inst.apply_death()
	inst._process(0.016)  # frozen — no sample
	assert_eq(sync.sample_count, 0)
	inst.apply_revive()
	assert_false(inst.is_dead(), "revive clears the dead flag")
	inst._process(0.016)
	assert_eq(sync.sample_count, 1,
		"post-revive _process resumes network_sync sampling")
	var sprite: Sprite2D = inst.get_node("Sprite2D")
	assert_eq(sprite.modulate, Color(1.0, 1.0, 1.0, 1.0),
		"revive restores the sprite modulate to white")
