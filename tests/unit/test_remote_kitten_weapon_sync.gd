extends GutTest

# Slice 4 of PRD #223 / issue #227. RemoteKitten gains a WeaponPivot +
# AttackChoreographer so peers see each other's swings/casts. The receive
# side is driven by a single play_attack(direction) entry point that
# carries no payload beyond the facing direction — the kitten's own
# character_class selects the WeaponDefinition (and therefore attack_type).

const REMOTE_KITTEN_PATH := "res://scenes/remote_kitten.tscn"

func _instance_with_class(cc: int) -> RemoteKitten:
	var scene: PackedScene = load(REMOTE_KITTEN_PATH)
	var inst: RemoteKitten = scene.instantiate()
	inst.character_class = cc
	add_child_autofree(inst)
	return inst

# Test 1 — remote-attack signal drives the embedded choreographer into WINDUP.
func test_play_attack_drives_choreographer_into_windup() -> void:
	var inst := _instance_with_class(CharacterData.CharacterClass.BATTLE_KITTEN)
	inst.play_attack(Vector2.RIGHT)
	assert_not_null(inst.attack_choreographer,
		"RemoteKitten exposes attack_choreographer after init")
	assert_eq(inst.attack_choreographer.phase,
		AttackChoreographer.Phase.WINDUP,
		"play_attack enters WINDUP phase")

# Test 2 — wizard class is wired to a CAST WeaponDefinition.
func test_wizard_remote_uses_cast_attack_type() -> void:
	var inst := _instance_with_class(CharacterData.CharacterClass.WIZARD_KITTEN)
	inst.play_attack(Vector2.RIGHT)
	assert_eq(inst.attack_choreographer.definition.attack_type,
		WeaponDefinition.AttackType.CAST,
		"wizard remote kitten uses CAST attack_type")

# Test 3 — facing direction propagates through to the pivot's mirror state.
# Left-facing attacks mirror pivot.position.x + sprite pixels and negate
# the rotation arc so the chop reads downward on both sides. Putting
# scale.x = -1 on the pivot would invert the rotation's y-component
# (Godot applies scale before rotation), so the mirror lives on sprite +
# position + rotation-sign, not on pivot.scale.
func test_facing_direction_propagates_to_pivot_mirror() -> void:
	var inst := _instance_with_class(CharacterData.CharacterClass.BATTLE_KITTEN)
	inst.play_attack(Vector2.LEFT)
	assert_eq(inst.weapon_pivot.scale.x, 1.0,
		"pivot.scale.x stays 1 — see weapon_pivot.gd for the why")
	var def: WeaponDefinition = inst.weapon_pivot.definition
	assert_eq(inst.weapon_pivot.position.x, def.anchor_offset.x * -1.0,
		"pivot.position.x mirrors so the weapon rests on the left flank")
	inst.weapon_pivot.tick(def.windup_duration + def.strike_duration - 0.001)
	var strike_rot: float = (def.idle_rotation + def.swing_arc) * -1.0
	assert_almost_eq(inst.weapon_pivot.rotation, strike_rot, 0.05,
		"left-facing strike rotation is the negation of right-facing strike")

# Test 4 — play_attack accepts only direction (no extra payload required),
# so existing position/state packets don't need new fields to drive it.
func test_play_attack_requires_only_direction() -> void:
	var inst := _instance_with_class(CharacterData.CharacterClass.BATTLE_KITTEN)
	# A direction is the entire API surface. If this signature gains fields
	# later, the multiplayer wire format will also need to grow — this test
	# pins that contract.
	inst.play_attack(Vector2.RIGHT)
	assert_eq(inst.attack_choreographer.phase,
		AttackChoreographer.Phase.WINDUP)

# Edge — classes without a WeaponDefinition (e.g. cat-tier) no-op cleanly
# rather than crashing. Mirrors player.gd's null-guard in _init_weapon_pivot.
func test_play_attack_no_ops_for_class_without_weapon_definition() -> void:
	# Use a non-kitten class that for_class returns null for. Any value
	# outside the four kitten classes works; pick one explicitly.
	var inst := _instance_with_class(CharacterData.CharacterClass.BATTLE_CAT)
	inst.play_attack(Vector2.RIGHT)
	assert_null(inst.attack_choreographer,
		"no choreographer is spawned for classes without a WeaponDefinition")
