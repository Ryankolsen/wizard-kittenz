class_name Bartender
extends InteractableNPC

# In-dungeon bartender NPC. Refactored in #197 to compose with the new
# InteractableNPC base + SpeechBubble menu: pressing attack while in range
# now opens a bubble with [Shop, Exit] rather than emitting shop_requested
# straight away. The bartender still emits shop_requested — just from
# _handle_effect("open_shop") after the player picks Shop from the bubble —
# so BarRoom's existing overlay-mount wiring stays unchanged.
#
# Decisions:
# - Proximity gate, attack-input gate, bubble mount/teardown, and
#   option-dispatch live in the base class (InteractableNPC). The bartender
#   only declares its menu rows and reacts to the chosen effect_id. Future
#   NPCs follow the same pattern.
# - Sprite texture is still loaded at runtime (rather than as an ext_resource
#   in the .tscn) because bartender.png ships without a .import sidecar in
#   some checkouts; an ext_resource referencing a missing .import would error
#   scene load and break every test that instantiates bar_room.tscn.
# - "Get a beer" lands in #199 once the damage-multiplier buff exists (#198).
#   For this slice the menu is intentionally just Shop + Exit.

signal shop_requested()

const SPRITE_TEXTURE_PATH := "res://assets/sprites/bartender.png"


func _ready() -> void:
	super._ready()
	_apply_sprite_texture()


func _apply_sprite_texture() -> void:
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite == null:
		return
	if not ResourceLoader.exists(SPRITE_TEXTURE_PATH):
		return
	var tex := load(SPRITE_TEXTURE_PATH) as Texture2D
	if tex != null:
		sprite.texture = tex


func _build_option_list() -> NPCOptionList:
	return NPCOptionList.make([
		NPCOption.make("Shop", "open_shop"),
		NPCOption.make("Exit", "close"),
	] as Array[NPCOption])


func _handle_effect(effect_id: String) -> void:
	match effect_id:
		"open_shop":
			# Tear the bubble down so the shop overlay sits cleanly on top.
			# BarRoom._on_shop_closed re-opens the menu when the overlay closes
			# so the player lands back on the bubble for a follow-up choice.
			_close_bubble()
			shop_requested.emit()
		"close":
			_close_bubble()
