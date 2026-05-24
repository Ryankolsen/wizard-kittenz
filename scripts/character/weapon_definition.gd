class_name WeaponDefinition
extends Resource

# Per-class weapon data driving WeaponPivot animation + AttackChoreographer
# phase timings. Slice 1 of PRD #223 — only the battle preset is wired in;
# wizard / sleepy / chonk presets land in slices 2 and 3.

enum AttackType { SWING, THRUST, CAST }

@export var texture_path: String = ""
@export var attack_type: AttackType = AttackType.SWING
@export var swing_arc: float = 2.0
@export var anchor_offset: Vector2 = Vector2.ZERO
@export var weapon_offset: Vector2 = Vector2.ZERO
@export var windup_duration: float = 0.08
@export var strike_duration: float = 0.12
@export var recovery_duration: float = 0.15
@export var idle_rotation: float = 0.0

func total_duration() -> float:
	return windup_duration + strike_duration + recovery_duration

# Battle kitten preset — sword in ~120° arc. Held grip-left, idle tilted down
# so the sword rests against the paw; swing rotates upward through the arc on
# strike. The anchor_offset puts the pivot at the kitten's paw position
# relative to the player center.
static func battle() -> WeaponDefinition:
	var d := WeaponDefinition.new()
	d.texture_path = "res://assets/sprites/weapon_sword_sprite.png"
	d.attack_type = AttackType.SWING
	d.swing_arc = 2.1
	d.anchor_offset = Vector2(2, 4)
	d.weapon_offset = Vector2.ZERO
	d.windup_duration = 0.08
	d.strike_duration = 0.12
	d.recovery_duration = 0.15
	d.idle_rotation = 0.4
	return d

# Lookup hook for SpriteHelper / player.gd. Slice 1 covers battle only;
# other classes return null so callers can fall through to the legacy
# _play_attack_flash path.
static func for_class(cc: int) -> WeaponDefinition:
	if cc == CharacterData.CharacterClass.BATTLE_KITTEN:
		return battle()
	return null
