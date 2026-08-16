class_name HealingBox
extends Node2D

const HP_PER_SEC: float = 2.0
const MP_PER_SEC: float = 1.0
const RADIUS: float = 40.0

var _hp_accum: float = 0.0
var _mp_accum: float = 0.0
var _hooman_hp_accum: float = 0.0

func _ready() -> void:
	z_index = -1
	var sprite := Sprite2D.new()
	sprite.texture = load("res://assets/sprites/healing_box_sprite.png")
	add_child(sprite)
	queue_redraw()

func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS, Color(1.0, 0.8, 0.2, 0.12))

func _physics_process(_delta: float) -> void:
	var target = _find_overlapping_player()
	tick(_delta, target)
	tick_hooman(_delta, _find_overlapping_hooman())

# Public so tests can drive healing without a SceneTree. hp_data is the
# CharacterData block HP healing lands on; null resolves it via _hp_data_for
# (effective_stats in co-op, the node's own data in solo). MP always heals the
# node's own data — MP is tracked on real_stats in both modes (the HUD MP bar
# and spell costs read target.data.magic_points).
func tick(delta: float, target = null, hp_data = null) -> void:
	if target == null or target.data == null:
		_hp_accum = 0.0
		_mp_accum = 0.0
		return

	if hp_data == null:
		hp_data = _hp_data_for(target)
	var mp_data = target.data

	_hp_accum += HP_PER_SEC * delta
	var hp_whole := int(_hp_accum)
	if hp_whole > 0:
		_hp_accum -= float(hp_whole)
		var healed: int = hp_data.heal(hp_whole)
		if healed > 0 and is_inside_tree():
			FloatingText.spawn(target as Node, "+" + str(healed), Color(0.2, 1.0, 0.4))

	if mp_data.max_mp <= 0:
		return
	_mp_accum += MP_PER_SEC * delta
	var mp_whole := int(_mp_accum)
	if mp_whole > 0:
		_mp_accum -= float(mp_whole)
		var mp_gap: int = mp_data.max_mp - mp_data.magic_points
		var mp_healed := mini(mp_whole, mp_gap)
		if mp_healed > 0:
			mp_data.magic_points += mp_healed
			if is_inside_tree():
				FloatingText.spawn(target as Node, "+" + str(mp_healed) + " MP", Color(0.7, 0.4, 1.0))

# Resolves the CharacterData block HP healing should land on. Reads the active
# co-op session from GameState and defers to CoopRouter.target_for so the box
# heals the same block damage / death / the HUD HP bar all use. Tree-guarded so
# the headless tick() tests (the box is never added to the tree) fall straight
# through to the node's own data.
func _hp_data_for(target):
	if not is_inside_tree():
		return resolve_hp_data(target, null, "")
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return resolve_hp_data(target, null, "")
	return resolve_hp_data(target, gs.coop_session, gs.local_player_id)

# Static so the solo/co-op routing is unit-testable without a SceneTree.
# session == null (solo / no co-op) heals the node's real_stats; an active
# co-op session heals the local member's effective_stats — the block incoming
# damage lands on (CoopRouter.target_for). Healing real_stats in co-op tops up
# a block nobody fights with, which is why the box appeared to do nothing in
# multiplayer.
static func resolve_hp_data(target, session, local_player_id: String):
	if target == null or target.data == null:
		return null
	if session == null:
		return target.data
	return CoopRouter.target_for(session, target.data, local_player_id)

# Additive Hooman-aware branch (issue #504) — the hooman is not in the
# "player" group (that group is read by several unrelated systems per PRD
# #502's decision), so it gets its own entry point rather than flowing
# through tick()/_find_overlapping_player. Heals hooman.hp directly (it has
# no .data wrapper) via the same whole-HP-accumulator pattern, and no MP
# heal is attempted since a hooman has no magic_points field. Gated on
# hooman.is_active() so an idle/unpaid hooman standing in the zone isn't
# healed.
func tick_hooman(delta: float, hooman) -> void:
	if hooman == null or not hooman.is_active():
		_hooman_hp_accum = 0.0
		return

	_hooman_hp_accum += HP_PER_SEC * delta
	var hp_whole := int(_hooman_hp_accum)
	if hp_whole > 0:
		_hooman_hp_accum -= float(hp_whole)
		var healed: int = hooman.heal(hp_whole)
		if healed > 0 and is_inside_tree():
			FloatingText.spawn(hooman as Node, "+" + str(healed), Color(0.2, 1.0, 0.4))


func _find_overlapping_player():
	var tree := get_tree()
	if tree == null:
		return null
	var r2 := RADIUS * RADIUS
	for node in tree.get_nodes_in_group("player"):
		if node is Node2D and (node as Node2D).global_position.distance_squared_to(global_position) <= r2:
			return node
	return null


# Mirrors _find_overlapping_player but scans "hooman" (issue #504) — the
# hooman is deliberately not added to "player" per PRD #502's decision.
func _find_overlapping_hooman():
	var tree := get_tree()
	if tree == null:
		return null
	var r2 := RADIUS * RADIUS
	for node in tree.get_nodes_in_group("hooman"):
		if node is Node2D and (node as Node2D).global_position.distance_squared_to(global_position) <= r2:
			return node
	return null
