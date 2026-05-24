class_name ChestEntity
extends Node2D

# In-world wrapper around the pure-data Chest (PRD #217 / issue #218,
# slice 1). Owns the closed/open sprite swap, the post-open linger →
# fade → free lifecycle, and a proximity gate that callers (Player input
# handler, or main_scene tick loop) use to decide whether to surface the
# interact prompt. Driven through public methods (open/tick/
# should_offer_interact) so the lifecycle is testable without a
# SceneTree, mirroring the headless tick() pattern in HealingBox.

enum State { CLOSED, OPENED_LINGERING, FADING, FREED }

const LINGER_SECONDS: float = 1.5
const FADE_SECONDS: float = 3.5
const INTERACT_RADIUS: float = 40.0

const CLOSED_TEXTURE_PATH := "res://assets/sprites/chest_closed_sprite.png"
const OPEN_TEXTURE_PATH := "res://assets/sprites/chest_open_sprite.png"

# Emits once on the first successful open() with the rolled ItemData (or
# null when the drop roll missed). Later VFX layers (PRD #217 user story
# 20) can connect here without ChestEntity knowing about them.
signal opened(item_drop)

var state: int = State.CLOSED
var chest: Chest = null
var ledger: CurrencyLedger = null
# Set true when the FADING countdown elapses and the entity has called
# queue_free(). Public test seam — assert on this instead of waiting for
# the node to actually drop out of the tree.
var freed: bool = false

var _sprite: Sprite2D = null
var _linger_remaining: float = LINGER_SECONDS
var _fade_remaining: float = FADE_SECONDS


func _ready() -> void:
	_ensure_sprite()
	_refresh_sprite_texture()


func _physics_process(delta: float) -> void:
	tick(delta)
	_try_interact()


# Proximity + attack-key gate for the in-game interact path. Mirrors the
# HealingBox proximity probe and the InteractableNPC attack-key wiring
# without inheriting either — chests are not NPCs and don't need a
# speech bubble. The character used for the item-drop roll is resolved
# through the GameState autoload at open-time so the wiring is the same
# as Bartender.
func _try_interact() -> void:
	if state != State.CLOSED:
		return
	var player := _find_nearby_player()
	if player == null:
		return
	if not Input.is_action_just_pressed("attack"):
		return
	var gs := get_node_or_null("/root/GameState")
	var character: CharacterData = null
	if gs != null:
		character = gs.current_character
		if ledger == null:
			ledger = gs.currency_ledger
	open(character, null)


func _find_nearby_player() -> Node2D:
	var tree := get_tree()
	if tree == null:
		return null
	var r2 := INTERACT_RADIUS * INTERACT_RADIUS
	for node in tree.get_nodes_in_group("player"):
		if node is Node2D and (node as Node2D).global_position.distance_squared_to(global_position) <= r2:
			return node
	return null


# Public so tests can drive the state machine without a SceneTree.
func tick(delta: float) -> void:
	match state:
		State.OPENED_LINGERING:
			_linger_remaining -= delta
			if _linger_remaining <= 0.0:
				state = State.FADING
		State.FADING:
			_fade_remaining -= delta
			var alpha: float = clampf(_fade_remaining / FADE_SECONDS, 0.0, 1.0)
			modulate.a = alpha
			if _fade_remaining <= 0.0:
				state = State.FREED
				freed = true
				if is_inside_tree():
					queue_free()
		_:
			pass


# Returns true while the chest is still openable. Callers (player input
# handler / proximity prompt UI) use this to gate prompt rendering so
# walking near a fading chest does not re-offer the interact (PRD user
# story 9).
func should_offer_interact() -> bool:
	return state == State.CLOSED


# Routes to the underlying Chest.open(). On the first successful call,
# transitions to OPENED_LINGERING, swaps the sprite, and emits opened
# with the rolled item drop (which may be null). Returns false on every
# later call so the lifecycle is single-shot.
func open(character: CharacterData = null, rng: RandomNumberGenerator = null) -> bool:
	if state != State.CLOSED:
		return false
	if chest == null or ledger == null:
		return false
	var ok: bool = chest.open(ledger, character, rng)
	if not ok:
		return false
	state = State.OPENED_LINGERING
	_linger_remaining = LINGER_SECONDS
	_fade_remaining = FADE_SECONDS
	_ensure_sprite()
	_refresh_sprite_texture()
	opened.emit(chest.last_item_drop)
	return true


func current_sprite_texture_path() -> String:
	if _sprite == null or _sprite.texture == null:
		return ""
	return _sprite.texture.resource_path


func _ensure_sprite() -> void:
	if _sprite != null and is_instance_valid(_sprite):
		return
	_sprite = get_node_or_null("Sprite2D") as Sprite2D
	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.name = "Sprite2D"
		add_child(_sprite)


func _refresh_sprite_texture() -> void:
	if _sprite == null:
		return
	var path: String = OPEN_TEXTURE_PATH if state != State.CLOSED else CLOSED_TEXTURE_PATH
	if ResourceLoader.exists(path):
		_sprite.texture = load(path)
