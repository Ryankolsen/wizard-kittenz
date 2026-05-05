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
const XP_BAR_WIDTH: float = 96.0

var _player: Player = null
var _hp_fill: ColorRect
var _hp_label: Label
var _xp_fill: ColorRect
var _xp_label: Label
var _room_clear: Control
var _you_died: Control
var _death_prompt: Label
var _use_revive_btn: Button
var _buy_more_btn: Button
var _initial_enemies: int = 0
var _room_cleared: bool = false

func _ready() -> void:
	_hp_fill = $HPBar/Fill
	_hp_label = $HPBar/Label
	_xp_fill = $XPBar/Fill
	_xp_label = $XPBar/Label
	_room_clear = $RoomClear
	_you_died = $YouDied
	_death_prompt = $YouDied/Panel/VBox/Prompt
	_use_revive_btn = $YouDied/Panel/VBox/UseRevive
	_buy_more_btn = $YouDied/Panel/VBox/BuyMore
	_room_clear.visible = false
	_you_died.visible = false
	_use_revive_btn.pressed.connect(_on_use_revive_pressed)
	_buy_more_btn.pressed.connect(_on_buy_more_pressed)
	var give_up: Button = $YouDied/Panel/VBox/GiveUp
	give_up.pressed.connect(_on_give_up_pressed)
	_player = _find_player()
	# Defer enemy count by one frame — main.tscn's enemy children may not
	# have run _ready() yet (and therefore haven't joined the "enemies"
	# group) when the HUD's _ready fires.
	call_deferred("_init_enemy_count")

func _init_enemy_count() -> void:
	_initial_enemies = _count_enemies()

func _process(_dt: float) -> void:
	_update_hp_bar()
	_update_xp_bar()
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

# Polls the player's xp / level each frame and refills the XP bar.
# After a level-up ProgressionSystem.add_xp resets `c.xp` to the carry-over
# remainder, so the bar visually empties on level-up without a special-case
# edge — same rationale as polling HP each frame instead of subscribing.
func _update_xp_bar() -> void:
	if _player == null or _player.data == null:
		return
	var d := _player.data
	var threshold := ProgressionSystem.xp_to_next_level(d.level)
	var ratio := xp_bar_ratio(d.level, d.xp)
	_xp_fill.size.x = XP_BAR_WIDTH * ratio
	_xp_label.text = xp_bar_label(d.level, d.xp, threshold, _local_effective_level())

# Pure-function fill ratio for the XP bar. Public + static so the test suite
# can drive it directly without spinning up a Player or HUD scene tree.
# Same shape as DamageResolver / PartyScaler — separate the math from the
# Node so the level-up "bar resets" invariant is testable in isolation.
static func xp_bar_ratio(level: int, xp: int) -> float:
	var threshold := ProgressionSystem.xp_to_next_level(level)
	if threshold <= 0:
		return 0.0
	return clampf(float(xp) / float(threshold), 0.0, 1.0)

# Pure-function label string for the XP bar. Renders "Lv.10 — 5/50" when not
# scaled (effective_level <= 0 sentinel for solo, or effective_level == level
# for a party member at or above the floor) and "Lv.10 (Lv.3) — 5/50" when
# scaled (member's effective_stats.level differs from real_stats.level).
# Closes #18 AC#4 by wiring a single label render that branches on the local
# member's scaling state. Prefix matches PartyScaler.format_hud_level's "Lv.X
# (Lv.Y)" shape exactly so a refactor of one drifts both in lockstep.
static func xp_bar_label(level: int, xp: int, threshold: int, effective_level: int = -1) -> String:
	if effective_level <= 0 or effective_level == level:
		return "Lv.%d — %d/%d" % [level, xp, threshold]
	return "Lv.%d (Lv.%d) — %d/%d" % [level, effective_level, xp, threshold]

# Looks up the local PartyMember's effective_stats.level from the active co-op
# session. Returns -1 (the "no scaling" sentinel for xp_bar_label) when:
#   - GameState autoload is missing (headless / test contexts)
#   - no active co-op session (solo path)
#   - no local_player_id set (pre-handshake / fresh-install)
#   - the local player is not in the session's party (defensive against a
#     wire-payload race where the local id doesn't match any member)
# Returning -1 short-circuits xp_bar_label to the solo render so the wiring
# inherits the existing solo behavior on every fall-through path.
func _local_effective_level() -> int:
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return -1
	var session: CoopSession = gs.coop_session
	if session == null or not session.is_active():
		return -1
	var pid: String = gs.local_player_id
	if pid == "":
		return -1
	var member := session.member_for(pid)
	if member == null or member.effective_stats == null:
		return -1
	return member.effective_stats.level

func _check_room_clear() -> void:
	if _room_cleared or _initial_enemies <= 0:
		return
	if _count_enemies() == 0:
		_room_cleared = true
		_room_clear.visible = true

func _check_player_dead() -> void:
	if _player == null or _player.data == null:
		return
	var dead := _player.data.hp <= 0
	# Edge-trigger: only re-render the death panel on the alive->dead
	# transition. After a successful revive, hp goes back > 0 and the
	# panel hides; if the kitten dies again, the polling re-fires this
	# branch and refreshes the token count from a possibly-changed
	# inventory.
	if dead and not _you_died.visible:
		_refresh_death_screen()
		_you_died.visible = true

# Maps token count to the death-screen presentation. Public + static so the
# test suite drives it directly without instancing the HUD scene tree —
# same shape as xp_bar_ratio. The "prompt" string is what the player sees;
# "can_revive" tells the HUD which of the Use/Buy buttons to surface.
static func death_screen_state(token_count: int) -> Dictionary:
	if token_count > 0:
		return {
			"can_revive": true,
			"prompt": "Use a Revive Token? (%d)" % token_count,
		}
	return {
		"can_revive": false,
		"prompt": "No Revive Tokens",
	}

func _refresh_death_screen() -> void:
	var inv := _get_token_inventory()
	var count := 0
	if inv != null:
		count = inv.count
	var state := death_screen_state(count)
	_death_prompt.text = state["prompt"]
	_use_revive_btn.visible = state["can_revive"]
	_buy_more_btn.visible = not state["can_revive"]

# GameState is an autoload; lookup is null-safe so headless / test contexts
# without the singleton don't crash the HUD.
func _get_token_inventory() -> TokenInventory:
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return null
	return gs.token_inventory

func _on_use_revive_pressed() -> void:
	if _player == null or _player.data == null:
		return
	var inv := _get_token_inventory()
	if ReviveSystem.try_consume_revive(_player.data, inv):
		_you_died.visible = false

# Stub for the IAP "Buy More" path. The Google Play Billing integration is
# tracked separately (#19, HITL); when it lands the success callback calls
# GameState.token_inventory.grant(5) and the player can hit Use Revive on
# the next death. Today the button is visible but no-ops so the UI shape
# is locked in for the future wiring.
func _on_buy_more_pressed() -> void:
	pass

func _on_give_up_pressed() -> void:
	get_tree().reload_current_scene()

func _count_enemies() -> int:
	return get_tree().get_nodes_in_group("enemies").size()

func _find_player() -> Player:
	var nodes := get_tree().get_nodes_in_group("player")
	for n in nodes:
		if n is Player:
			return n
	return null
