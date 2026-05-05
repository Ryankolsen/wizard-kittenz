extends Node

var current_character: CharacterData = null

func set_character(c: CharacterData) -> void:
	current_character = c

func clear() -> void:
	current_character = null
