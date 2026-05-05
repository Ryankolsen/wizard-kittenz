class_name HUD
extends CanvasLayer

# Single-room HUD orchestrator. Polls each frame:
# - HP bar reads player.data.hp/max_hp
# - Room Clear banner shows when the initial enemy count drops to zero
# - You Died panel shows when player.data.hp <= 0; Restart reloads the scene
#
# Polling (vs. signal subscription) keeps the wiring trivial — the HUD
# doesn't need to find every enemy at startup, just count the "enemies"
# group each frame. Future iterations can switch to signals when the
# enemy count grows large enough to make per-frame counting wasteful.

const HP_BAR_WIDTH: float = 96.0

var _player: Player = null
var _hp_fill: ColorRect
var _hp_label: Label
var _room_clear: Control
var _you_died: Control
var _initial_enemies: int = 0
var _room_cleared: bool = false

func _ready() -> void:
	_hp_fill = $HPBar/Fill
	_hp_label = $HPBar/Label
	_room_clear = $RoomClear
	_you_died = $YouDied
	_room_clear.visible = false
	_you_died.visible = false
	var restart: Button = $YouDied/Panel/VBox/Restart
	restart.pressed.connect(_on_restart_pressed)
	_player = _find_player()
	# Defer enemy count by one frame — main.tscn's enemy children may not
	# have run _ready() yet (and therefore haven't joined the "enemies"
	# group) when the HUD's _ready fires.
	call_deferred("_init_enemy_count")

func _init_enemy_count() -> void:
	_initial_enemies = _count_enemies()

func _process(_dt: float) -> void:
	_update_hp_bar()
	_check_room_clear()
	_check_player_dead()

func _update_hp_bar() -> void:
	if _player == null or _player.data == null:
		_player = _find_player()
		if _player == null or _player.data == null:
			return
	var d := _player.data
	var ratio := 0.0
	if d.max_hp > 0:
		ratio = clampf(float(d.hp) / float(d.max_hp), 0.0, 1.0)
	_hp_fill.size.x = HP_BAR_WIDTH * ratio
	_hp_label.text = "HP %d/%d" % [d.hp, d.max_hp]

func _check_room_clear() -> void:
	if _room_cleared or _initial_enemies <= 0:
		return
	if _count_enemies() == 0:
		_room_cleared = true
		_room_clear.visible = true

func _check_player_dead() -> void:
	if _player == null or _player.data == null:
		return
	if _player.data.hp <= 0:
		_you_died.visible = true

func _count_enemies() -> int:
	return get_tree().get_nodes_in_group("enemies").size()

func _find_player() -> Player:
	var nodes := get_tree().get_nodes_in_group("player")
	for n in nodes:
		if n is Player:
			return n
	return null

func _on_restart_pressed() -> void:
	get_tree().reload_current_scene()
