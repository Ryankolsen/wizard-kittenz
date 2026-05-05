class_name CharacterCreation
extends Control

@export var main_scene_path: String = "res://scenes/main.tscn"

@onready var _mage_button: Button = $Panel/VBox/Buttons/MageButton
@onready var _thief_button: Button = $Panel/VBox/Buttons/ThiefButton
@onready var _ninja_button: Button = $Panel/VBox/Buttons/NinjaButton

func _ready() -> void:
	_mage_button.pressed.connect(_on_class_pressed.bind(CharacterData.CharacterClass.MAGE))
	_thief_button.pressed.connect(_on_class_pressed.bind(CharacterData.CharacterClass.THIEF))
	_ninja_button.pressed.connect(_on_class_pressed.bind(CharacterData.CharacterClass.NINJA))

func _on_class_pressed(klass: CharacterData.CharacterClass) -> void:
	var data := select_class(klass)
	GameState.set_character(data)
	get_tree().change_scene_to_file(main_scene_path)

static func select_class(klass: CharacterData.CharacterClass, character_name: String = "Kitten") -> CharacterData:
	return CharacterData.make_new(klass, character_name)
