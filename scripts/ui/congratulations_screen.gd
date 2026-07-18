class_name CongratulationsScreen
extends CanvasLayer

# PRD #132 / issue #135 — overlay shown on dungeon floor clear in place
# of the previous direct-to-pause-menu jump. Owns no game state: the
# caller (main_scene) builds the FloorRunSummary and headline string,
# then calls populate() and connects the three button signals to its
# own handlers.
#
# CanvasLayer so the dungeon stays visible behind the panel and the
# screen doesn't disrupt the scene tree mid-completion. Buttons emit
# typed signals rather than acting directly — handler wiring lives in
# main_scene per the slice split (#135 Next Floor, #136 Update Character,
# #137 Save & Exit).

signal next_floor_pressed
signal update_character_pressed
signal save_and_exit_pressed

# #416 — panel width is capped to whichever is smaller: the panel's own
# unconstrained ("natural") width, or the viewport width minus a small edge
# gutter. Capping at the natural width means wide desktop windows never
# grow the panel past its normal appearance; capping at the viewport width
# is what keeps it from overflowing narrow phone screens. DESKTOP_MAX_WIDTH
# is a hard ceiling on top of that in case a future theme change makes the
# natural width itself unreasonably large.
const DESKTOP_MAX_WIDTH := 480.0
const VIEWPORT_EDGE_MARGIN := 32.0

var _headline: Label
var _floor_label: Label
var _enemies_label: Label
var _xp_label: Label
var _gold_label: Label
var _next_floor_button: Button
var _waiting_label: Label
var _panel: PanelContainer
var _vbox: VBoxContainer
var _stats: VBoxContainer
var _button_row: HFlowContainer
var _natural_panel_width: float = 0.0
var _panel_margins: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = $Backdrop/Center/Panel
	_vbox = $Backdrop/Center/Panel/VBox
	_stats = $Backdrop/Center/Panel/VBox/Stats
	_button_row = $Backdrop/Center/Panel/VBox/ButtonRow
	_headline = $Backdrop/Center/Panel/VBox/Headline
	_floor_label = $Backdrop/Center/Panel/VBox/Stats/FloorLabel
	_enemies_label = $Backdrop/Center/Panel/VBox/Stats/EnemiesLabel
	_xp_label = $Backdrop/Center/Panel/VBox/Stats/XPLabel
	_gold_label = $Backdrop/Center/Panel/VBox/Stats/GoldLabel
	_next_floor_button = $Backdrop/Center/Panel/VBox/ButtonRow/NextFloor
	_waiting_label = $Backdrop/Center/Panel/VBox/ButtonRow/WaitingLabel
	var update_btn: Button = $Backdrop/Center/Panel/VBox/ButtonRow/UpdateCharacter
	var exit_btn: Button = $Backdrop/Center/Panel/VBox/ButtonRow/SaveAndExit
	_next_floor_button.pressed.connect(_on_next_floor_pressed)
	update_btn.pressed.connect(_on_update_character_pressed)
	exit_btn.pressed.connect(_on_save_and_exit_pressed)
	get_viewport().size_changed.connect(_update_panel_width)
	await get_tree().process_frame
	_natural_panel_width = _compute_natural_panel_width()
	_update_panel_width()

# ButtonRow is an HFlowContainer so it CAN wrap to a small width — its own
# reported minimum size is just the widest single button, not what it looks
# like laid out on one row. To know the panel's true "natural" (unwrapped)
# width we sum the button widths ourselves rather than trust the flow
# container's minimum size.
func _compute_natural_panel_width() -> float:
	var button_row_width := 0.0
	var visible_count := 0
	for child in _button_row.get_children():
		if child is Control and child.visible:
			button_row_width += child.get_combined_minimum_size().x
			visible_count += 1
	if visible_count > 1:
		button_row_width += _button_row.get_theme_constant("h_separation") * (visible_count - 1)
	var content_width: float = maxf(button_row_width, _stats.get_combined_minimum_size().x)
	_panel_margins = 0.0
	var panel_style := _panel.get_theme_stylebox("panel")
	if panel_style is StyleBoxFlat:
		_panel_margins = panel_style.content_margin_left + panel_style.content_margin_right
	return content_width + _panel_margins

# Deferred one frame past _ready because the panel's theme-driven minimum
# size (button fonts etc.) isn't fully resolved until the first layout pass.
# vp_width_override lets tests simulate a narrow viewport directly — the
# headless test runner's fixed project stretch resolution means resizing
# the real viewport doesn't take effect, so this is the reliable seam.
func _update_panel_width(vp_width_override: float = -1.0) -> void:
	if _vbox == null or _natural_panel_width <= 0.0:
		return
	var vp_width := vp_width_override
	if vp_width < 0.0:
		vp_width = get_viewport().get_visible_rect().size.x
	var cap: float = minf(_natural_panel_width, DESKTOP_MAX_WIDTH)
	var target_panel_width: float = minf(vp_width - VIEWPORT_EDGE_MARGIN, cap)
	_vbox.custom_minimum_size.x = maxf(target_panel_width - _panel_margins, 0.0)

# PRD #348 / issue #350 — `is_leader` defaults true so solo (and every
# pre-#350 caller) keeps the active "Next Floor" button. Co-op peers
# pass false and get the passive "Waiting for the party leader…" label
# instead; the button is hidden AND disabled so a stray pressed.emit()
# (Godot still fires the signal on hidden buttons) drops at the source.
func populate(summary: FloorRunSummary, message: String, is_leader: bool = true) -> void:
	if _headline == null:
		return
	_headline.text = message
	_floor_label.text = "Floor: %d" % summary.floor_number
	_enemies_label.text = "Enemies Slain: %d" % summary.enemies_slain
	_xp_label.text = "XP Earned: %d" % summary.xp_earned
	_gold_label.text = "Gold Earned: %d" % summary.gold_earned
	_next_floor_button.visible = is_leader
	_next_floor_button.disabled = not is_leader
	_waiting_label.visible = not is_leader

func _on_next_floor_pressed() -> void:
	# Defense-in-depth: a disabled button shouldn't fire pressed in Godot,
	# but pin the no-emit contract here so a future style refactor that
	# leaves the button enabled-but-hidden can't silently re-open the
	# peer-press path.
	if _next_floor_button != null and _next_floor_button.disabled:
		return
	next_floor_pressed.emit()

func _on_update_character_pressed() -> void:
	update_character_pressed.emit()

func _on_save_and_exit_pressed() -> void:
	save_and_exit_pressed.emit()
