class_name HitResolver
extends RefCounted

# Pure hit-chance math for physical attacks.
# Formula: 0.85 base + 0.02 per dexterity + 0.005 per luck, clamped to [0.85, 0.98].
# Accepts either two ints (dex, luck) or a duck-typed attacker with optional
# `dexterity` / `luck` properties — missing fields default to 0 so enemies and
# minimal stat objects can call through without crashing.

const BASE: float = 0.85
const CAP: float = 0.98
const DEX_WEIGHT: float = 0.02
const LUCK_WEIGHT: float = 0.005

static func hit_chance(dex_or_attacker, luck: int = 0) -> float:
	var dex_val: int = 0
	var luck_val: int = 0
	if typeof(dex_or_attacker) == TYPE_OBJECT:
		if dex_or_attacker != null:
			if "dexterity" in dex_or_attacker:
				dex_val = int(dex_or_attacker.dexterity)
			if "luck" in dex_or_attacker:
				luck_val = int(dex_or_attacker.luck)
	else:
		dex_val = int(dex_or_attacker)
		luck_val = int(luck)
	var raw: float = BASE + dex_val * DEX_WEIGHT + luck_val * LUCK_WEIGHT
	return clamp(raw, BASE, CAP)

static func roll_hit(dex_or_attacker, luck: int = 0) -> bool:
	return randf() < hit_chance(dex_or_attacker, luck)
