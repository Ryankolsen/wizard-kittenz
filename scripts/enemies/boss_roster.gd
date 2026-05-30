class_name BossRoster
extends RefCounted

# Pure-data module that answers "which boss for floor N?" with deterministic
# per-floor assignment plus a scaling tier that increments every 10 floors.
# No Godot scene/node deps — testable directly. See PRD #297, slice #298.
#
# The roster is 10 long. boss_for_floor(n) for n > 10 loops back to entry 1
# with scaling_tier bumped: floors 1..10 = tier 1, 11..20 = tier 2, …
#
# Sprite paths are hard-coded to their eventual assets/sprites/ locations.
# Slice 3 (#300) produces the left/right PNGs; this module ships ahead of
# those files. The Vacuum is the existing single-sprite boss — both
# directions point at the same vacuum_boss.png, which is the PRD's documented
# single-sprite fallback.

class BossInfo extends RefCounted:
	var kind: int = 0
	var display_name: String = ""
	var sprite_left_path: String = ""
	var sprite_right_path: String = ""
	var scaling_tier: int = 1

const _ROSTER_SIZE := 10

static func roster_size() -> int:
	return _ROSTER_SIZE

static func boss_for_floor(floor_number: int) -> BossInfo:
	var n := maxi(1, floor_number)
	var index := ((n - 1) % _ROSTER_SIZE)
	var tier := ((n - 1) / _ROSTER_SIZE) + 1
	var info := BossInfo.new()
	info.scaling_tier = tier
	match index:
		0:
			info.kind = EnemyData.EnemyKind.ROGUE_ROOMBA
			info.display_name = "Vacuum"
			info.sprite_left_path = "res://assets/sprites/vacuum_boss.png"
			info.sprite_right_path = "res://assets/sprites/vacuum_boss.png"
		1:
			info.kind = EnemyData.EnemyKind.SIR_PICKLETON
			info.display_name = "Sir Pickleton"
			info.sprite_left_path = "res://assets/sprites/sir_pickleton_left.png"
			info.sprite_right_path = "res://assets/sprites/sir_pickleton_right.png"
		2:
			info.kind = EnemyData.EnemyKind.OLD_LADY_PEARL
			info.display_name = "Old Lady Pearl"
			info.sprite_left_path = "res://assets/sprites/old_lady_pearl_left.png"
			info.sprite_right_path = "res://assets/sprites/old_lady_pearl_right.png"
		3:
			info.kind = EnemyData.EnemyKind.TRASH_PANDA_TYRONE
			info.display_name = "Trash Panda Tyrone"
			info.sprite_left_path = "res://assets/sprites/trash_panda_tyrone_left.png"
			info.sprite_right_path = "res://assets/sprites/trash_panda_tyrone_right.png"
		4:
			info.kind = EnemyData.EnemyKind.BIG_BRUISER_BUSTER
			info.display_name = "Big Bruiser Buster"
			info.sprite_left_path = "res://assets/sprites/big_bruiser_buster_left.png"
			info.sprite_right_path = "res://assets/sprites/big_bruiser_buster_right.png"
		5:
			info.kind = EnemyData.EnemyKind.LAST_CALL_LARRY
			info.display_name = "Last Call Larry"
			info.sprite_left_path = "res://assets/sprites/last_call_larry_left.png"
			info.sprite_right_path = "res://assets/sprites/last_call_larry_right.png"
		6:
			info.kind = EnemyData.EnemyKind.THE_BOUNCER
			info.display_name = "The Bouncer"
			info.sprite_left_path = "res://assets/sprites/the_bouncer_left.png"
			info.sprite_right_path = "res://assets/sprites/the_bouncer_right.png"
		7:
			info.kind = EnemyData.EnemyKind.DJ_DUBSTEP
			info.display_name = "DJ Dubstep"
			info.sprite_left_path = "res://assets/sprites/dj_dubstep_left.png"
			info.sprite_right_path = "res://assets/sprites/dj_dubstep_right.png"
		8:
			info.kind = EnemyData.EnemyKind.KARAOKE_KAREN
			info.display_name = "Karaoke Karen"
			info.sprite_left_path = "res://assets/sprites/karaoke_karen_left.png"
			info.sprite_right_path = "res://assets/sprites/karaoke_karen_right.png"
		9:
			info.kind = EnemyData.EnemyKind.WARDEN_WRETCHED
			info.display_name = "Warden Wretched"
			info.sprite_left_path = "res://assets/sprites/warden_wretched_left.png"
			info.sprite_right_path = "res://assets/sprites/warden_wretched_right.png"
	return info
