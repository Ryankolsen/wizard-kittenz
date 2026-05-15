class_name AttackController
extends RefCounted

var cooldown: float = 0.4
var last_attack_time: float = -1.0e9

func can_attack(now: float) -> bool:
	return now - last_attack_time >= cooldown

func try_attack(now: float) -> bool:
	if not can_attack(now):
		return false
	last_attack_time = now
	return true
