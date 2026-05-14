class_name HUD
extends CanvasLayer

signal next_room_requested

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
const MP_BAR_WIDTH: float = 96.0
const XP_BAR_WIDTH: float = 96.0

var _player: Player = null
var _hp_fill: ColorRect
var _mp_fill: ColorRect
var _xp_fill: ColorRect
var _room_clear: Control
var _you_died: Control
var _death_prompt: Label
var _revive_btn: Button
var _initial_enemies: int = 0
var _room_cleared: bool = false
var _next_room_btn: Button
var _room_clear_pause_btn: Button
var _pause_btn: Button
var _pause_menu: CanvasLayer = null
var _stat_points_badge: Label

const PAUSE_MENU_SCENE := preload("res://scenes/pause_menu.tscn")
const HOST_PAUSE_OVERLAY_SCENE := preload("res://scenes/host_pause_overlay.tscn")
const LOOT_PROMPT_SCENE := preload("res://scenes/loot_prompt.tscn")

var _loot_prompt: CanvasLayer = null

func _ready() -> void:
	_hp_fill = $StatsPanel/VBox/HPBar/Fill
	_mp_fill = $StatsPanel/VBox/MPBar/Fill
	_xp_fill = $StatsPanel/VBox/XPBar/Fill
	_room_clear = $RoomClear
	_next_room_btn = $RoomClear/NextRoom
	_next_room_btn.pressed.connect(_on_next_room_pressed)
	_room_clear_pause_btn = $RoomClear/RoomClearPause
	_room_clear_pause_btn.pressed.connect(_on_pause_pressed)
	_you_died = $YouDied
	_death_prompt = $YouDied/Panel/VBox/Prompt
	_revive_btn = $YouDied/Panel/VBox/Revive
	_room_clear.visible = false
	_you_died.visible = false
	_revive_btn.pressed.connect(_on_revive_pressed)
	var give_up: Button = $YouDied/Panel/VBox/GiveUp
	give_up.pressed.connect(_on_give_up_pressed)
	_pause_btn = $PauseButton
	_pause_btn.pressed.connect(_on_pause_pressed)
	_stat_points_badge = $StatPointsBadge
	_player = _find_player()
	_bind_player_item_drop()
	# Defer enemy count by one frame — main.tscn's enemy children may not
	# have run _ready() yet (and therefore haven't joined the "enemies"
	# group) when the HUD's _ready fires.
	call_deferred("_init_enemy_count")
	# Host-pause overlay (#43). Eagerly instanced so a remote host-pause
	# packet that arrives before the player presses their own pause button
	# still has a surface to render the "Host has paused" banner on. The
	# overlay self-suppresses on the host's client, so this is a no-op for
	# the host's HUD.
	_spawn_host_pause_overlay()

func _spawn_host_pause_overlay() -> void:
	var overlay := HOST_PAUSE_OVERLAY_SCENE.instantiate()
	add_child(overlay)

func _init_enemy_count() -> void:
	_initial_enemies = _count_enemies()

func _process(_dt: float) -> void:
	_update_hp_bar()
	_update_mp_bar()
	_update_xp_bar()
	_update_stat_points_badge()
	_check_room_clear()
	_check_player_dead()

# Polls player.data.skill_points each frame and toggles the badge. Same
# polling shape as the HP/XP bars — the badge updates within one frame of
# a level-up (which awards stat points) or a StatAllocator.allocate (which
# spends them). #58 AC: visible iff skill_points > 0.
func _update_stat_points_badge() -> void:
	if _stat_points_badge == null:
		return
	if _player == null or _player.data == null:
		_stat_points_badge.visible = false
		return
	var pts := _player.data.skill_points
	_stat_points_badge.visible = StatBadge.should_show(pts)
	if _stat_points_badge.visible:
		_stat_points_badge.text = "+%d stat pts" % pts

func _update_hp_bar() -> void:
	if _player == null or _player.data == null:
		_player = _find_player()
		_bind_player_item_drop()
		if _player == null or _player.data == null:
			return
	var d := _player.data
	var eff := _local_effective_hp_data()
	var eff_hp: int = eff.get("hp", -1)
	var eff_max: int = eff.get("max_hp", -1)
	_hp_fill.size.x = HP_BAR_WIDTH * hp_bar_ratio(d.hp, d.max_hp, eff_hp, eff_max)

func _update_mp_bar() -> void:
	if _player == null or _player.data == null:
		return
	var d := _player.data
	_mp_fill.size.x = MP_BAR_WIDTH * mp_bar_ratio(d.magic_points, d.max_mp)

static func mp_bar_ratio(mp: int, max_mp: int) -> float:
	if max_mp <= 0:
		return 0.0
	return clampf(float(mp) / float(max_mp), 0.0, 1.0)

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

# Pure-function fill ratio for the HP bar. Mirrors xp_bar_ratio: solo /
# no-session path passes the default sentinels and the math runs against
# the player's real_stats hp/max_hp; co-op scaled path passes the local
# member's effective_stats hp/max_hp so the bar fills against the scaled
# view (the actual fighting HP). The sentinel branch falls through to
# real values whenever effective_max <= 0 (uninitialized, default arg, or
# defensive against a zero from a half-built PartyMember).
static func hp_bar_ratio(hp: int, max_hp: int, effective_hp: int = -1, effective_max: int = -1) -> float:
	var actual_hp := hp
	var actual_max := max_hp
	if effective_max > 0 and effective_hp >= 0:
		actual_hp = effective_hp
		actual_max = effective_max
	if actual_max <= 0:
		return 0.0
	return clampf(float(actual_hp) / float(actual_max), 0.0, 1.0)

# Pure-function label string for the HP bar. Renders "HP 8/10" on the solo
# / no-session path (effective_max <= 0 sentinel) and "HP 5/10" with the
# scaled values on the co-op scaled path. Sibling to xp_bar_label: the XP
# bar already signals scaling via "Lv.X (Lv.Y)" so the HP bar doesn't
# repeat that — it just renders the active fighting HP. Closes the HP-
# routing display gap noted in a591f9e: damage routes to effective_stats
# when LocalDamageRouter wires up at the call site, and this label reads
# the same effective_stats so the bar tracks the actual damage flow.
static func hp_bar_label(hp: int, max_hp: int, effective_hp: int = -1, effective_max: int = -1) -> String:
	if effective_max <= 0 or effective_hp < 0:
		return "HP %d/%d" % [hp, max_hp]
	return "HP %d/%d" % [effective_hp, effective_max]

# Looks up the local PartyMember's effective_stats hp / max_hp from the
# active co-op session. Returns {"hp": -1, "max_hp": -1} (the "no scaling"
# sentinels for hp_bar_label / hp_bar_ratio) when:
#   - GameState autoload is missing (headless / test contexts)
#   - no active co-op session (solo path)
#   - no local_player_id set (pre-handshake / fresh-install)
#   - the local player is not in the session's party (defensive against a
#     wire-payload race where the local id doesn't match any member)
#   - the member's effective_stats is null (uninitialized; from_character
#     always sets it so this is a defense-in-depth)
# Returning -1 sentinels short-circuits the label/ratio helpers to the
# solo render so the wiring inherits existing solo behavior on every
# fall-through path. Same shape as _local_effective_level but returns a
# Dictionary because the HP view needs both hp and max_hp.
func _local_effective_hp_data() -> Dictionary:
	var fallback := {"hp": -1, "max_hp": -1}
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return fallback
	var session: CoopSession = gs.coop_session
	if session == null or not session.is_active():
		return fallback
	var pid: String = gs.local_player_id
	if pid == "":
		return fallback
	var member := session.member_for(pid)
	if member == null or member.effective_stats == null:
		return fallback
	return {"hp": member.effective_stats.hp, "max_hp": member.effective_stats.max_hp}

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
		_room_clear_pause_btn.visible = true

# Called by the scene orchestrator when DungeonRunController.room_cleared fires.
# Shows the banner and the "Next Room" button so the player can advance.
func show_next_room_prompt() -> void:
	_room_cleared = true
	_room_clear.visible = true
	_next_room_btn.visible = true
	_room_clear_pause_btn.visible = true

func _on_next_room_pressed() -> void:
	next_room_requested.emit()

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

# Death-screen presentation (post-#27, free-revive contract). Free revives
# are always available so the shape is fixed; the helper exists for a single
# call site to render labels + as a test seam that can be exercised without
# instancing the HUD scene tree.
static func death_screen_state() -> Dictionary:
	return {
		"can_revive": true,
		"prompt": "You Died",
	}

func _refresh_death_screen() -> void:
	var state := death_screen_state()
	_death_prompt.text = state["prompt"]
	_revive_btn.visible = state["can_revive"]

func _on_revive_pressed() -> void:
	if _player == null or _player.data == null:
		return
	var gs := get_node_or_null("/root/GameState")
	var session: CoopSession = null
	var pid := ""
	if gs != null:
		session = gs.coop_session
		pid = gs.local_player_id
	if LocalReviveRouter.revive(session, _player.data, pid):
		_you_died.visible = false

func _on_give_up_pressed() -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.clear()
	get_tree().change_scene_to_file("res://scenes/character_creation.tscn")

# Lazy-instantiates a PauseMenu under the HUD and routes the button to its
# open(). Adding the overlay under the HUD CanvasLayer keeps the wiring
# scene-local — no need to touch main.tscn or hand a reference around.
# The PauseMenu sets its own process_mode = ALWAYS so it stays responsive
# while solo play freezes the rest of the tree.
func _on_pause_pressed() -> void:
	_ensure_pause_menu().open()

func _ensure_pause_menu() -> CanvasLayer:
	if _pause_menu == null:
		_pause_menu = PAUSE_MENU_SCENE.instantiate()
		add_child(_pause_menu)
	return _pause_menu

# Lazy-instantiates the PauseMenu (mirroring _on_pause_pressed) and opens
# it in dungeon-transition mode (PRD #52 / #61). Returns the menu so the
# caller can wire its transition_continued signal. Kept on HUD because
# the menu lives under the HUD CanvasLayer — main_scene asks for it
# rather than instancing its own copy.
func open_pause_menu_for_transition() -> CanvasLayer:
	var pm := _ensure_pause_menu()
	pm.open_for_dungeon_transition()
	return pm

func _count_enemies() -> int:
	return get_tree().get_nodes_in_group("enemies").size()

func _find_player() -> Player:
	var nodes := get_tree().get_nodes_in_group("player")
	for n in nodes:
		if n is Player:
			return n
	return null

# Loot prompt (PRD #73 / issue #80). Player emits item_dropped after the
# kill-reward router returns a non-null ItemData; HUD owns the modal
# dialog. Disabling _physics_process on the player while the prompt is
# open is what enforces "movement/attacks blocked" without touching the
# tree-wide pause flag (which would also freeze coop peers).
func _bind_player_item_drop() -> void:
	if _player == null:
		return
	if not _player.item_dropped.is_connected(_on_player_item_dropped):
		_player.item_dropped.connect(_on_player_item_dropped)

func _on_player_item_dropped(item: ItemData) -> void:
	if item == null:
		return
	var prompt := _ensure_loot_prompt()
	if _player != null:
		_player.set_physics_process(false)
	prompt.show_for(item)

func _ensure_loot_prompt() -> CanvasLayer:
	if _loot_prompt == null:
		_loot_prompt = LOOT_PROMPT_SCENE.instantiate()
		add_child(_loot_prompt)
		_loot_prompt.choice_made.connect(_on_loot_choice_made)
	return _loot_prompt

func _on_loot_choice_made(item: ItemData, equip: bool) -> void:
	if _player != null:
		_player.set_physics_process(true)
	if item == null:
		return
	var gs := get_node_or_null("/root/GameState")
	if gs == null or gs.item_inventory == null:
		return
	var inventory: ItemInventory = gs.item_inventory
	if equip:
		# Subtract the displaced item's bonus before swap so the new
		# bonus replaces (not stacks on top of) the old. ItemInventory.equip
		# moves the displaced item into the bag.
		var prev: ItemData = inventory.equipped_in(item.slot)
		if prev != null and prev.stat_name != "" and _player != null and _player.data != null:
			var cur: Variant = _player.data.get(prev.stat_name)
			if cur != null:
				_player.data.set(prev.stat_name, cur - prev.stat_bonus)
		inventory.equip(item)
		if _player != null and _player.data != null and item.stat_name != "":
			var cur2: Variant = _player.data.get(item.stat_name)
			if cur2 != null:
				_player.data.set(item.stat_name, cur2 + item.stat_bonus)
	else:
		inventory.add_to_bag(item)
