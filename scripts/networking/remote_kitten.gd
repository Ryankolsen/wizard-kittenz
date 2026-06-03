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

func play_attack(direction: Vector2) -> void:
	if attack_choreographer == null:
		return
	attack_choreographer.start_attack(direction,
		attack_choreographer.definition.attack_type)
