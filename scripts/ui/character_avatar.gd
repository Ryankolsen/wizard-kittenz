class_name CharacterAvatar
extends Control

# Visual avatar for the Items (Inventory) tab (PRD #268 / issue #270).
# Composites the player's class kitten sprite with the equipped weapon,
# updating live as items are equipped/unequipped.
#
# Weapon pose: a real WeaponPivot instance owns the resting transform
# (anchor_offset / weapon_offset / idle_rotation / sprite_scale) so the
# weapon reads as "held" exactly like in combat — no duplicated pose math.
#
# Weapon texture: sourced via ItemImageResolver.texture_path_for_item()
# so this control honors the single-source-of-truth contract from #269.
# WeaponPivot.set_definition would also load WeaponDefinition.texture_path
# for the same path in practice; we overwrite from the resolver afterward
# so that if the resolver's mapping ever diverges, the UI follows the
# resolver, not the combat preset.

const _WEAPON_PIVOT_SCENE := preload("res://scenes/weapon_pivot.tscn")
const _AVATAR_SIZE := Vector2(96, 96)

var _body: Sprite2D = null
var _weapon_pivot: WeaponPivot = null
var _character_class: int = -1
var _inventory: ItemInventory = null

func _ready() -> void:
	_ensure_built()

# Idempotent build of the body sprite + weapon pivot. Called from _ready
# and from every public setter so set_loadout/bind work on a fresh
# CharacterAvatar.new() before it's been added to a parent (the tests
# add_child_autofree then call set_loadout — _ready may or may not have
# run depending on Godot's ordering, so we don't rely on it).
func _ensure_built() -> void:
	if _body != null and _weapon_pivot != null:
		return
	custom_minimum_size = _AVATAR_SIZE
	var anchor := Node2D.new()
	anchor.name = "Anchor"
	anchor.position = _AVATAR_SIZE * 0.5
	add_child(anchor)
	_body = Sprite2D.new()
	_body.name = "Body"
	anchor.add_child(_body)
	_weapon_pivot = _WEAPON_PIVOT_SCENE.instantiate()
	_weapon_pivot.name = "WeaponPivot"
	anchor.add_child(_weapon_pivot)

# Direct render path. Used by tests and by bind()'s refresh loop.
# A null weapon_item leaves the body in place and hides the weapon sprite —
# kitten standing empty-handed.
func set_loadout(character_class: int, weapon_item: ItemData) -> void:
	_ensure_built()
	_character_class = character_class
	_body.texture = load(SpriteHelper.path_for_class(character_class))
	var weapon_sprite := _weapon_pivot.get_node_or_null("Sprite2D") as Sprite2D
	if weapon_item == null:
		if weapon_sprite != null:
			weapon_sprite.visible = false
			weapon_sprite.texture = null
		return
	var def: WeaponDefinition = null
	if not weapon_item.allowed_classes.is_empty():
		def = WeaponDefinition.for_class(weapon_item.allowed_classes[0])
	if def != null:
		_weapon_pivot.set_definition(def)
	var tex_path := ItemImageResolver.texture_path_for_item(weapon_item)
	if weapon_sprite == null:
		return
	if tex_path == "":
		weapon_sprite.visible = false
		weapon_sprite.texture = null
		return
	weapon_sprite.texture = load(tex_path)
	weapon_sprite.visible = true

# Subscribes to the inventory's loadout_changed so the avatar refreshes
# whenever a weapon is equipped/unequipped (PRD user story 10). Disconnects
# any prior binding so rebinding to a new inventory doesn't leave a stale
# signal subscription pointing at a freed RefCounted.
func bind(character_class: int, inventory: ItemInventory) -> void:
	_ensure_built()
	if _inventory != null and _inventory != inventory:
		if _inventory.loadout_changed.is_connected(_on_loadout_changed):
			_inventory.loadout_changed.disconnect(_on_loadout_changed)
	_character_class = character_class
	_inventory = inventory
	if _inventory != null and not _inventory.loadout_changed.is_connected(_on_loadout_changed):
		_inventory.loadout_changed.connect(_on_loadout_changed)
	_refresh_from_inventory()

func _on_loadout_changed() -> void:
	_refresh_from_inventory()

func _refresh_from_inventory() -> void:
	var item: ItemData = null
	if _inventory != null:
		item = _inventory.equipped_in(ItemData.Slot.WEAPON)
	set_loadout(_character_class, item)
