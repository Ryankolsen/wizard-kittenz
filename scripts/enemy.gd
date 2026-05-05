class_name Enemy
extends CharacterBody2D

@export var data: EnemyData

func _ready() -> void:
	if data == null:
		data = EnemyData.make_new(EnemyData.EnemyKind.SLIME)
