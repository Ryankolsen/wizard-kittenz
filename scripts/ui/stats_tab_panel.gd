class_name StatsTabPanel
extends VBoxContainer

# Stats tab inside the pause menu's Character submenu (PRD #52 / #60).
# Programmatically builds one row per allocatable stat plus an unspent-
# points header, and routes "+" presses through StatAllocator.allocate.
# The set of stats is taken from StatAllocator.INT_INCREMENTS /
# FLOAT_INCREMENTS so adding a new allocatable stat is a one-line dict
# entry there, not a UI edit here.
#
# Legacy node names (LevelLabel, HPLabel, MPLabel, ATKLabel, DEFLabel,
# SPDLabel) are preserved on the per-stat value labels so the older
# Stats-panel tests from #47 keep finding them by name.

signal allocated(stat: String)
# Fires when the player presses the Continue button (only visible in the
# dungeon-transition flow, PRD #52 / #61). The pause menu re-emits this so
# main_scene can resume dungeon loading.
signal continue_pressed

# Display rows in the order the issue lists them. Each entry maps a stat
# key (matching StatAllocator) to a display name, the value-formatter
# kind, and the legacy node name so existing tests keep resolving it.
const STAT_ROWS := [
	{"key": "max_hp", "label": "HP", "kind": "hp_pair", "node": "HPLabel"},
	{"key": "max_mp", "label": "MP", "kind": "mp_pair", "node": "MPLabel"},
	{"key": "attack", "label": "Attack", "kind": "int", "node": "ATKLabel"},
	{"key": "magic_attack", "label": "Magic Attack", "kind": "int", "node": "MagicAttackLabel"},
	{"key": "defense", "label": "Defense", "kind": "int", "node": "DEFLabel"},
	{"key": "magic_resistance", "label": "Magic Resistance", "kind": "int", "node": "MagicResistanceLabel"},
	{"key": "speed", "label": "Speed", "kind": "speed", "node": "SPDLabel"},
	{"key": "dexterity", "label": "Dexterity", "kind": "int", "node": "DexterityLabel"},
	{"key": "evasion", "label": "Evasion", "kind": "percent", "node": "EvasionLabel"},
	{"key": "crit_chance", "label": "Crit Chance", "kind": "percent", "node": "CritChanceLabel"},
	{"key": "luck", "label": "Luck", "kind": "int", "node": "LuckLabel"},
	{"key": "regeneration", "label": "Regeneration", "kind": "int", "node": "RegenerationLabel"},
]

var _character: CharacterData = null
var _unspent_label: Label = null
var _level_label: Label = null
var _legend: HBoxContainer = null
var _stat_labels := {}
var _name_labels := {}
var _cost_labels := {}
var _plus_buttons := {}
var _continue_button: Button = null
var _built := false

# Display strings + modulate colors per tier (PRD #316 / issue #320; recolor
# #352). Tiers are surfaced by coloring each stat's name rather than spelling
# out the tier in text — the legend built from this table is the key. Kept
# co-located with the panel rather than on ClassStatTiers so the data module
# stays presentation-free.
const _TIER_DISPLAY := {
	ClassStatTiers.Tier.PRIMARY: {"text": "Primary", "color": Color(1.0, 0.85, 0.2)},
	ClassStatTiers.Tier.SECONDARY: {"text": "Secondary", "color": Color(0.8, 0.95, 1.0)},
	ClassStatTiers.Tier.OFF_STAT: {"text": "Off-stat", "color": Color(1.0, 0.65, 0.35)},
	ClassStatTiers.Tier.FORBIDDEN: {"text": "Forbidden", "color": Color(0.55, 0.55, 0.55)},
}

# Legend order, top to bottom of the stat sheet's usefulness.
const _TIER_LEGEND_ORDER := [
	ClassStatTiers.Tier.PRIMARY,
	ClassStatTiers.Tier.SECONDARY,
	ClassStatTiers.Tier.OFF_STAT,
	ClassStatTiers.Tier.FORBIDDEN,
]

func _init() -> void:
	_build()

func _ready() -> void:
	_build()

func _build() -> void:
	if _built:
		return
	_built = true
	_unspent_label = Label.new()
	_unspent_label.name = "UnspentLabel"
	_unspent_label.text = "Unspent points: 0"
	_unspent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_unspent_label)
	_level_label = Label.new()
	_level_label.name = "LevelLabel"
	_level_label.text = "Lv —"
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_level_label)
	_legend = _make_legend()
	add_child(_legend)
	for s in STAT_ROWS:
		add_child(_make_row(s))
	_continue_button = Button.new()
	_continue_button.name = "ContinueButton"
	_continue_button.text = "Continue"
	_continue_button.visible = false
	_continue_button.pressed.connect(_on_continue_pressed)
	add_child(_continue_button)

# Color key shown once above the rows: one swatch+name per tier so the
# row name colors are self-documenting (issue #352). Centered, wraps as a
# single horizontal strip.
func _make_legend() -> HBoxContainer:
	var box := HBoxContainer.new()
	box.name = "TierLegend"
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 16)
	for tier in _TIER_LEGEND_ORDER:
		var display: Dictionary = _TIER_DISPLAY[tier]
		var lbl := Label.new()
		lbl.name = "Legend_%d" % tier
		lbl.text = "%s %s" % [String.chr(0x25CF), display.text]
		lbl.modulate = display.color
		box.add_child(lbl)
	return box

func _make_row(s: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Row_%s" % s.key
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	var name_lbl := Label.new()
	name_lbl.name = "NameLabel_%s" % s.key
	name_lbl.text = s.label
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_lbl)
	_name_labels[s.key] = name_lbl
	var val_lbl := Label.new()
	val_lbl.name = s.node
	val_lbl.text = "—"
	row.add_child(val_lbl)
	_stat_labels[s.key] = val_lbl
	var cost_lbl := Label.new()
	cost_lbl.name = "CostLabel_%s" % s.key
	cost_lbl.text = ""
	row.add_child(cost_lbl)
	_cost_labels[s.key] = cost_lbl
	var btn := Button.new()
	btn.name = "PlusButton_%s" % s.key
	btn.text = "+"
	btn.disabled = true
	var stat_key: String = s.key
	btn.pressed.connect(func(): _on_plus_pressed(stat_key))
	row.add_child(btn)
	_plus_buttons[s.key] = btn
	# Right-side scrollbar clearance is provided once by the TabPadding
	# MarginContainer wrapping TabContent in pause_menu.tscn — applies
	# to Stats / Skills / Inventory uniformly.
	return row

# Renders `c` into the rows. Safe with c == null (pre-character-creation
# / cleared GameState) — labels fall back to em-dash placeholders and
# every "+" button disables, matching the existing _refresh_character_stats
# null-character contract.
func refresh(c: CharacterData) -> void:
	_build()
	_character = c
	if c == null:
		_unspent_label.text = "Unspent points: 0"
		_level_label.text = "Lv —"
		for key in _stat_labels.keys():
			(_stat_labels[key] as Label).text = "—"
			(_name_labels[key] as Label).modulate = Color.WHITE
			(_cost_labels[key] as Label).text = ""
			(_plus_buttons[key] as Button).disabled = true
		return
	_unspent_label.text = "Unspent points: %d" % c.skill_points
	_level_label.text = "Lv %d" % c.level
	for s in STAT_ROWS:
		(_stat_labels[s.key] as Label).text = _format_stat(c, s)
		_apply_tier_ui(c, s.key)

# Drives name color / cost label / + button enabled-state for one row.
# Rules (PRD #316 / issue #320; recolor #352): the stat name is tinted with
# its tier color (decoded via the legend) instead of a spelled-out tier;
# Forbidden disables the button and zeroes cost; Off-stat shows 2 SP;
# cap-reached and insufficient-SP both disable with a tooltip explaining why
# so the player never sees a silent reject.
func _apply_tier_ui(c: CharacterData, key: String) -> void:
	var tier: int = ClassStatTiers.get_tier(c.character_class, key)
	var display: Dictionary = _TIER_DISPLAY[tier]
	var name_lbl := _name_labels[key] as Label
	name_lbl.modulate = display.color
	name_lbl.tooltip_text = display.text
	var cost := ClassStatTiers.get_sp_cost(c.character_class, key)
	var cap := ClassStatTiers.get_cap(c.character_class, key)
	var allocated: int = int(c.allocated_points.get(key, 0))
	var cost_lbl := _cost_labels[key] as Label
	var btn := _plus_buttons[key] as Button
	if tier == ClassStatTiers.Tier.FORBIDDEN:
		cost_lbl.text = "—"
		btn.visible = true
		btn.disabled = true
		btn.tooltip_text = "%s is Forbidden for this class." % key
		return
	cost_lbl.text = "%d SP" % cost
	btn.visible = true
	if allocated >= cap:
		btn.disabled = true
		btn.tooltip_text = "%s is at its allocation cap (+%d)." % [key, cap]
	elif c.skill_points < cost:
		btn.disabled = true
		btn.tooltip_text = "Needs %d SP (you have %d)." % [cost, c.skill_points]
	else:
		btn.disabled = false
		btn.tooltip_text = "Spend %d SP to raise %s." % [cost, key]

func _format_stat(c: CharacterData, s: Dictionary) -> String:
	match s.kind:
		"hp_pair":
			return "%d/%d" % [c.hp, c.max_hp]
		"mp_pair":
			return "%d/%d" % [c.magic_points, c.max_mp]
		"percent":
			# Stored as [0.0, 1.0]; display as integer percent so a player
			# allocating 1 point reads "1%" rather than "0.01".
			return "%d%%" % int(round(float(c.get(s.key)) * 100.0))
		"speed":
			return "%d" % int(round(c.speed))
		_:
			return "%d" % int(c.get(s.key))

func _on_plus_pressed(stat_key: String) -> void:
	if _character == null:
		return
	var ok := CharacterMutator.new(_character).allocate_stat_points({stat_key: 1})
	if not ok:
		return
	refresh(_character)
	allocated.emit(stat_key)

func _on_continue_pressed() -> void:
	continue_pressed.emit()

# Toggles the Continue button used by the dungeon-transition flow
# (PRD #52 / #61). Hidden by default — only shown when the pause menu
# is opened via open_for_dungeon_transition(). Always enabled
# regardless of skill_points so a player with zero unspent points can
# dismiss the screen immediately.
func set_continue_visible(vis: bool) -> void:
	_build()
	_continue_button.visible = vis

func get_continue_button() -> Button:
	_build()
	return _continue_button

func get_unspent_label_text() -> String:
	_build()
	return _unspent_label.text

func get_plus_button(stat_key: String) -> Button:
	_build()
	return _plus_buttons.get(stat_key)

func get_stat_label(stat_key: String) -> Label:
	_build()
	return _stat_labels.get(stat_key)

func get_name_label(stat_key: String) -> Label:
	_build()
	return _name_labels.get(stat_key)

func get_legend() -> HBoxContainer:
	_build()
	return _legend

func get_cost_label(stat_key: String) -> Label:
	_build()
	return _cost_labels.get(stat_key)
