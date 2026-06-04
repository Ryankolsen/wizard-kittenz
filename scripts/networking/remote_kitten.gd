class_name RemoteKitten
extends Node2D

# Visual stand-in for a remote co-op player. One node per other player_id
# in the lobby; spawned and freed by CoopPlayerLayer as the lobby roster
# changes. Reads its position from NetworkSyncManager each frame so the
# already-tested interpolation contract drives the rendering, rather than
# duplicating the lerp here.
#
# Lifecycle:
#   1. CoopPlayerLayer instantiates the scene, assigns player_id /
#      kitten_name / network_sync / tint_color, and adds it as a child.
#   2. _ready hooks the placeholder polygon's modulate to tint_color and
#      the Label's text to kitten_name (also exposed at runtime so the
#      layer can update them mid-session if a future PLAYER_INFO packet
#      changes the name).
#   3. _process samples network_sync.get_display_position_at(player_id, now)
#      each frame; the interpolator handles "no sample yet" (returns
#      Vector2.ZERO so the kitten stays at origin until the first packet
#      lands) and "freshest sample only" (no lerp; kitten pops at first
#      known location).
#   4. CoopPlayerLayer calls queue_free on roster removal.

const _WeaponPivotScene = preload("res://scenes/weapon_pivot.tscn")

@export var player_id: String = ""
@export var kitten_name: String = ""
@export var tint_color: Color = Color(1, 1, 1, 1)
@export var character_class: CharacterData.CharacterClass = CharacterData.CharacterClass.WIZARD_KITTEN
# Untyped to avoid a script-level dependency on NetworkSyncManager — RefCounted
# refs round-trip through @export poorly. CoopPlayerLayer assigns this
# directly after instantiate(). Null is treated as "no sync source" and the
# kitten freezes at its current position rather than crashing.
var network_sync = null

# Slice 8 of PRD #328 (issue #336). Death-state flag; when true, _process
# skips the network_sync sample so the kitten freezes at its death pose
# regardless of subsequent interpolation. Flipped back via apply_revive
# when the next OP_POSITION packet arrives (CoopPlayerLayer drives the
# transparent revive at the position-routing edge).
var _is_dead: bool = false

# PRD #223 slice 4 (#227): receive-side weapon animation. play_attack(dir)
# drives the embedded WeaponPivot + AttackChoreographer with the same code
# path the local Player uses. Null for classes without a WeaponDefinition.
var weapon_pivot: WeaponPivot = null
var attack_choreographer: AttackChoreographer = null

@onready var _placeholder: Polygon2D = get_node_or_null("Placeholder")
@onready var _label: Label = get_node_or_null("Label")
@onready var _sprite: Sprite2D = get_node_or_null("Sprite2D")

func _ready() -> void:
	# Join the taunt-targets group so Enemy._select_taunt_target_by_id can
	# locate this remote kitten by player_id when a TAUNT is applied with a
	# matching taunt_source_id. The local Player joins the same group; both
	# expose a player_id field and a global_position, which is everything the
	# enemy's targeting path needs (contact damage no-ops on non-Player nodes).
	add_to_group("taunt_targets")
	if _placeholder != null:
		_placeholder.modulate = tint_color
	if _label != null:
		_label.text = kitten_name
	if _sprite != null:
		_sprite.texture = load(SpriteHelper.path_for_class(character_class))
	_init_weapon_pivot()

func _process(delta: float) -> void:
	if attack_choreographer != null:
		attack_choreographer.tick(delta)
	if _is_dead:
		return
	if network_sync == null or player_id == "":
		return
	var now := Time.get_ticks_msec() / 1000.0
	position = network_sync.get_display_position_at(player_id, now)

# Spawn a WeaponPivot + AttackChoreographer for the remote kitten's class.
# Mirrors player.gd._init_weapon_pivot; no-ops for classes without a
# WeaponDefinition (cat-tier etc.) so non-kitten remotes continue to render
# with the legacy placeholder sprite only.
func _init_weapon_pivot() -> void:
	var def := WeaponDefinition.for_class(character_class)
	if def == null:
		return
	weapon_pivot = _WeaponPivotScene.instantiate()
	add_child(weapon_pivot)
	weapon_pivot.set_definition(def)
	attack_choreographer = AttackChoreographer.new()
	attack_choreographer.definition = def
	attack_choreographer.weapon_pivot = weapon_pivot

# Receive-side entry point invoked when a peer broadcasts an attack/cast.
# Direction carries the peer's facing; the kitten's own character_class
# selects WeaponDefinition (and therefore attack_type), so no extra payload
# is needed on the wire beyond the facing vector.
# Slice 2 of PRD #328 (issue #330). Mirrors the local Player sprite-flip
# rule from player.gd: `flip_h = moving_left != SpriteHelper.faces_left(cc)`.
# facing_x is a sign — -1, 0, or +1. A zero (or absent on the wire) means
# "keep last known facing" so a stationary teammate doesn't snap to a
# default orientation between movement bursts.
func apply_facing(facing_x: int) -> void:
	if facing_x == 0 or _sprite == null:
		return
	var moving_left := facing_x < 0
	_sprite.flip_h = moving_left != SpriteHelper.faces_left(character_class)

# Slice 3 of PRD #328 (issue #331). Receive-side weapon visual: takes the
# peer's currently-equipped weapon id (an ItemData.id, e.g. "iron_sword")
# and routes it through HeldWeaponResolver — the same single-source-of-
# truth Player._refresh_combat_weapon walks (scripts/core/player.gd:192).
# Reusing the resolver is what makes the local Player and the remote
# RemoteKitten render the same weapon by construction.
#
# Empty weapon_id is the "unarmed / class-default" sentinel: pose reverts
# to WeaponDefinition.for_class so the choreographer keeps working for
# unarmed-melee animations, but the weapon sprite is hidden — matches
# Player's _refresh_combat_weapon unarmed branch (player.gd:194-199).
# An unknown id (catalog miss) behaves the same as empty, defensively.
#
# No-op for classes whose _init_weapon_pivot returned early (cat-tier);
# weapon_pivot is null in that case so the call falls through cleanly.
func apply_equipped_weapon(weapon_id: String) -> void:
	if weapon_pivot == null:
		return
	var weapon_sprite := weapon_pivot.get_node_or_null("Sprite2D") as Sprite2D
	var item: ItemData = null
	if weapon_id != "":
		item = ItemCatalog.find(weapon_id)
	var resolved := HeldWeaponResolver.resolve(item, character_class)
	if not resolved[HeldWeaponResolver.ARMED_KEY]:
		# Unarmed: revert pose to class-default so the choreographer still
		# has a valid definition to drive, then hide the weapon sprite.
		var class_def := WeaponDefinition.for_class(character_class)
		if class_def != null:
			weapon_pivot.set_definition(class_def)
			if attack_choreographer != null:
				attack_choreographer.definition = class_def
		if weapon_sprite != null:
			weapon_sprite.visible = false
			weapon_sprite.texture = null
		return
	var def: WeaponDefinition = resolved[HeldWeaponResolver.DEFINITION_KEY]
	if def != null:
		weapon_pivot.set_definition(def)
		if attack_choreographer != null:
			attack_choreographer.definition = def
	var tex_path: String = resolved[HeldWeaponResolver.TEXTURE_KEY]
	if weapon_sprite != null:
		if tex_path != "":
			weapon_sprite.texture = load(tex_path)
			weapon_sprite.visible = true
		else:
			weapon_sprite.visible = false
			weapon_sprite.texture = null


func play_attack(direction: Vector2) -> void:
	if attack_choreographer == null:
		return
	attack_choreographer.start_attack(direction,
		attack_choreographer.definition.attack_type)


# Slice 5 of PRD #328 (issue #333). Receive-side entry point for spell
# casts — both wizard primary (kind=spell_cast) and quickbar hotkey
# (kind=quickbar_cast). Routes through the same AttackChoreographer
# play_attack drives so the visible "cast pose" is the choreographer's
# CAST animation (for classes whose WeaponDefinition.attack_type is
# CAST) or the class-default attack pose otherwise. spell_id is carried
# for future per-spell visual differentiation (projectile / AoE spawn)
# but is informational today — the wire is forward-compatible. Empty /
# unknown spell_id is NOT a guard here: the choreographer pose is the
# baseline render and must fire regardless. The wire-side quickbar_cast
# guard (NakamaLobby._route_attack) drops empty-spell_id quickbar casts
# defensively, so reaching this method with an empty spell_id implies
# the wizard-primary path which intentionally carries no spell_id.
func play_spell_cast(direction: Vector2, _spell_id: String) -> void:
	if attack_choreographer == null:
		return
	attack_choreographer.start_attack(direction,
		attack_choreographer.definition.attack_type)


# Slice 7 of PRD #328 (issue #335). Receive-side hit reaction — drives a
# white-flash modulate + a short knockback offset on the sprite when a
# peer broadcasts that they just took damage. The reaction is sprite-
# local (not position-based) because RemoteKitten.position is overwritten
# every frame by network_sync; mutating _sprite.position keeps the
# visual offset independent of the network-interpolated body position,
# same dual-rail _apply_ale_wobble uses on Player. Knockback direction
# points the kitten AWAY from source_position so a hit from the left
# pushes the kitten to the right. Damage value is currently informational
# (no per-amount magnitude scaling) but pinned on the wire so a future
# slice can scale flash intensity / knockback distance per-hit without a
# protocol break.
const HIT_FLASH_COLOR := Color(2.0, 2.0, 2.0, 1.0)
const HIT_FLASH_DURATION := 0.12
const KNOCKBACK_DISTANCE := 6.0
const KNOCKBACK_DURATION := 0.15

# Slice 8 of PRD #328 (issue #336). Receive-side death visual — modulates
# the sprite to DEAD_TINT (persistent, not tweened) and flips the
# _is_dead flag so _process stops sampling network_sync (the kitten
# freezes at its death pose). The revive path is driven from
# CoopPlayerLayer: when an OP_POSITION packet arrives for this peer,
# apply_revive clears the flag and restores the sprite modulate. Solo
# Player has no equivalent visual today; the slice introduces this dim
# tint as the shared death-pose marker so the remote view has a
# distinguishable "dead teammate" state. No-op when _sprite is null
# (cat-tier / fixture instances without the scene tree fully assembled).
const DEAD_TINT := Color(0.4, 0.4, 0.4, 0.6)

func is_dead() -> bool:
	return _is_dead

func apply_death() -> void:
	_is_dead = true
	if _sprite != null:
		_sprite.modulate = DEAD_TINT

func apply_revive() -> void:
	if not _is_dead:
		return
	_is_dead = false
	if _sprite != null:
		_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)


func apply_hit_reaction(damage: int, source_position: Vector2) -> void:
	if damage <= 0 or _sprite == null:
		return
	_sprite.modulate = HIT_FLASH_COLOR
	var dir := (global_position - source_position).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	_sprite.position = dir * KNOCKBACK_DISTANCE
	var tween := create_tween()
	tween.parallel().tween_property(_sprite, "modulate",
		Color(1.0, 1.0, 1.0, 1.0), HIT_FLASH_DURATION)
	tween.parallel().tween_property(_sprite, "position",
		Vector2.ZERO, KNOCKBACK_DURATION)
