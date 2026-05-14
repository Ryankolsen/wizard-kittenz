class_name LootPrompt
extends CanvasLayer

# Modal equip-or-bag dialog (PRD #73 / issue #80). Surfaces when a kill
# or chest open produces an ItemData. HUD owns the lifecycle: it
# instantiates the prompt on demand, calls show_for(item), and reacts
# to `choice_made(item, equip)`.
#
# process_mode = PROCESS_MODE_ALWAYS so the dialog still receives input
# when the rest of the tree is paused (matches PauseMenu's pattern —
# avoids the "frozen menu" trap where pausing freezes the buttons too).

signal choice_made(item: ItemData, equip: bool)

const RARITY_NAMES := {
	ItemData.Rarity.COMMON: "Common",
	ItemData.Rarity.RARE: "Rare",
	ItemData.Rarity.EPIC: "Epic",
}

var _item: ItemData = null
var _name_label: Label
var _rarity_label: Label
var _equip_btn: Button
var _bag_btn: Button

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_name_label = $Backdrop/Center/Panel/VBox/ItemName
	_rarity_label = $Backdrop/Center/Panel/VBox/Rarity
	_equip_btn = $Backdrop/Center/Panel/VBox/ButtonRow/Equip
	_bag_btn = $Backdrop/Center/Panel/VBox/ButtonRow/Bag
	_equip_btn.pressed.connect(_on_equip_pressed)
	_bag_btn.pressed.connect(_on_bag_pressed)
	visible = false

func show_for(item: ItemData) -> void:
	if item == null:
		return
	_item = item
	if _name_label != null:
		_name_label.text = item.display_name
	if _rarity_label != null:
		_rarity_label.text = RARITY_NAMES.get(item.rarity, "Common")
	visible = true

func _on_equip_pressed() -> void:
	_resolve(true)

func _on_bag_pressed() -> void:
	_resolve(false)

func _resolve(equip: bool) -> void:
	var item := _item
	_item = null
	visible = false
	choice_made.emit(item, equip)
