class_name ChestEntity
extends Node2D

# In-world wrapper around the pure-data Chest. Slice 1 (#218) introduced
# the open + linger + fade lifecycle and a single-ledger interact path.
# Slice 4 (PRD #217 / issue #221) layers per-player open state on top so
# co-op opens credit each client's own loot and the chest only fades once
# every present player has opened it. Solo behavior (no session / 1-player
# session) is unchanged from #218: the first open transitions to
# OPENED_LINGERING immediately.
#
# Drive the lifecycle via public methods (open / tick /
# should_offer_interact) so it stays testable without a SceneTree, mirroring
# the headless tick() pattern in HealingBox.

enum State { CLOSED, OPENED_LINGERING, FADING, FREED }

const LINGER_SECONDS: float = 1.5
const FADE_SECONDS: float = 3.5
const INTERACT_RADIUS: float = 40.0

const CLOSED_TEXTURE_PATH := "res://assets/sprites/chest_closed_sprite.png"
const OPEN_TEXTURE_PATH := "res://assets/sprites/chest_open_sprite.png"

# Fires on every successful per-player open with (player_id, ItemData|null).
# The wire bridge (slice 5 QA / future RPC slice) listens here and forwards
# (chest_id, player_id) to remote clients; remote clients apply the open
# through ChestEntity.open(player_id, ...) on their local entity matched
# by chest_id.
signal opened_by(player_id, item_drop)

var state: int = State.CLOSED
# Template Chest — only `kind` is consulted; per-player Chest instances are
# minted inside open() so each player rolls their own loot independently.
var chest: Chest = null
# Solo fallback ledger and also the convenient slot for the local client's
# ledger in co-op. _ledger_for() prefers `ledgers[player_id]` when set and
# falls through to this for the empty-dict case.
var ledger: CurrencyLedger = null
# Optional per-player ledger map (player_id -> CurrencyLedger). Production
# co-op typically populates only the local player's entry — remote players'
# ledgers live on their own clients and are credited there from the
# replayed open. Tests populate both so they can assert independent credit.
var ledgers: Dictionary = {}
# Optional CoopSession. When null, behaves like solo: any single open
# transitions to OPENED_LINGERING. When set, the chest stays CLOSED until
# every session.player_ids entry has opened it (user story 14: shared
# visual state).
var session: CoopSession = null
# Deterministic id from ChestSpawner — co-op clients use this to identify
# the same chest across the wire (slice 5 wires the actual RPC; slice 4
# just exposes the field).
var chest_id: String = ""
# Set true when the FADING countdown elapses and queue_free() fires. Public
# test seam — assert here instead of waiting for the node to drop out of
# the tree.
var freed: bool = false

# player_id -> true. Tracks who has already opened. Drives per-player
# idempotence and the all-present-have-opened check that gates the fade.
var _opened_set: Dictionary = {}
# player_id -> ItemData|null. Captures the per-player drop produced by the
# most recent successful open(), so the local interact path can announce
# loot (item + currency) through the same HUD pipeline boss kills use.
var _drops_by_player: Dictionary = {}
var _sprite: Sprite2D = null
var _linger_remaining: float = LINGER_SECONDS
var _fade_remaining: float = FADE_SECONDS


func _ready() -> void:
	z_index = -1
	_ensure_sprite()
	_refresh_sprite_texture()


func _physics_process(delta: float) -> void:
	tick(delta)
	_try_interact()


# Proximity + attack-key gate for the in-game interact path. Resolves the
# local player_id from the session (empty string = solo / no-session) and
# routes through the same public open() path the wire layer uses.
func _try_interact() -> void:
	if state != State.CLOSED:
		return
	var local_pid: String = _resolve_local_player_id()
	if not should_offer_interact(local_pid):
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
	var per_ledger: CurrencyLedger = _ledger_for(local_pid)
	var gold_before: int = 0
	var gem_before: int = 0
	if per_ledger != null:
		gold_before = per_ledger.balance(CurrencyLedger.Currency.GOLD)
		gem_before = per_ledger.balance(CurrencyLedger.Currency.GEM)
	if not open(local_pid, character, null):
		return
	_announce_local_loot(player, per_ledger, gold_before, gem_before, _drops_by_player.get(local_pid, null))


# Routes chest loot through the same HUD pipeline a boss kill uses
# (Player.item_dropped + Player.gold_dropped → hud._spawn_drop_text). Gems
# don't have a Player signal today, so they go straight to FloatingText.
func _announce_local_loot(player: Node2D, per_ledger: CurrencyLedger, gold_before: int, gem_before: int, item_drop: ItemData) -> void:
	if player == null:
		return
	if item_drop != null and player.has_signal("item_dropped"):
		player.item_dropped.emit(item_drop)
	if per_ledger != null:
		var gold_gain: int = per_ledger.balance(CurrencyLedger.Currency.GOLD) - gold_before
		if gold_gain > 0 and player.has_signal("gold_dropped"):
			player.gold_dropped.emit(gold_gain)
		var gem_gain: int = per_ledger.balance(CurrencyLedger.Currency.GEM) - gem_before
		if gem_gain > 0:
			FloatingText.spawn(player, "+%d Gems" % gem_gain, Color(0.7, 0.4, 1.0))


func _resolve_local_player_id() -> String:
	if session != null and session.local_player_id != "":
		return session.local_player_id
	return ""


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


# Returns true while this chest is still openable for `player_id`. The
# default empty-string player_id keeps callers that don't track identity
# (older single-player UI / tests) working by only checking state. Co-op
# callers pass the local player_id so a player who has already opened
# this chest does not see the prompt again (user story 15).
func should_offer_interact(player_id: String = "") -> bool:
	if state != State.CLOSED:
		return false
	if player_id != "" and _opened_set.has(player_id):
		return false
	return true


# Per-player open. Mints a fresh Chest instance for this player, credits
# their ledger, marks them opened, and transitions to OPENED_LINGERING
# only once every present player (per session) has opened. Returns false
# if the chest is no longer CLOSED, this player already opened it, or the
# required wiring (chest / ledger) is missing.
func open(player_id: String, character: CharacterData = null, rng: RandomNumberGenerator = null) -> bool:
	if state != State.CLOSED:
		return false
	if _opened_set.has(player_id):
		return false
	if chest == null:
		return false
	var per_ledger: CurrencyLedger = _ledger_for(player_id)
	if per_ledger == null:
		return false
	# Fresh per-player Chest instance — each player rolls their own loot
	# rather than sharing one Chest's already-consumed roll. The template
	# `chest` on the entity contributes only its `kind`.
	var per_chest: Chest = Chest.make(chest.kind, chest.depth)
	var ok: bool = per_chest.open(per_ledger, character, rng)
	if not ok:
		return false
	_opened_set[player_id] = true
	_drops_by_player[player_id] = per_chest.last_item_drop
	opened_by.emit(player_id, per_chest.last_item_drop)
	if _all_present_players_have_opened():
		state = State.OPENED_LINGERING
		_linger_remaining = LINGER_SECONDS
		_fade_remaining = FADE_SECONDS
		_ensure_sprite()
		_refresh_sprite_texture()
	return true


# True once every present player (per session.player_ids) has opened, or
# unconditionally true when no session is wired (solo / older callers).
# The solo fallback preserves #218 behavior: first open → linger → fade.
func _all_present_players_have_opened() -> bool:
	if session == null:
		return not _opened_set.is_empty()
	for pid in session.player_ids:
		if not _opened_set.has(pid):
			return false
	return true


func _ledger_for(player_id: String) -> CurrencyLedger:
	if ledgers.has(player_id):
		return ledgers[player_id]
	return ledger


# Test seam: lets `test_chest_entity.gd` assert which player_ids have
# already credited without poking the private dict directly.
func has_opened(player_id: String) -> bool:
	return _opened_set.has(player_id)


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
