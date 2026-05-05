extends Node

var current_character: CharacterData = null

func _ready() -> void:
	_try_load_save()

func _try_load_save() -> void:
	var save_data := SaveManager.load()
	if save_data == null:
		return
	var c := CharacterData.new()
	save_data.apply_to(c)
	current_character = c

func set_character(c: CharacterData) -> void:
	current_character = c

func clear() -> void:
	current_character = null
