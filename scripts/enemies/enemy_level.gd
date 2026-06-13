class_name EnemyLevel
extends RefCounted

# Pure-function module that computes a standard mob's level from its kind +
# floor (PRD #376 / issue #377). Level is the canonical stat driver in later
# slices; this tracer just threads the value through data → planner → UI so
# the readout lands first.
#
# Formula: level = floor_baseline + per-kind offset.
#   floor_baseline = FLOOR_BASELINE_BASE + FLOOR_BASELINE_STEP * (floor - 1)
#   floor 1 → baseline 0; floor 2 → +FLOOR_BASELINE_STEP; etc.
# Per-kind offsets pin the floor-1 spread: Angry Pigeon 1, Rogue Roomba 2,
# Catnip Dealer 2, Haunted Spray Bottle 3, Dog Knight 4. Tunable constants
# below — designer iteration on exact levels is a body edit.

const FLOOR_BASELINE_BASE: int = 0
const FLOOR_BASELINE_STEP: int = 2

const OFFSET_ANGRY_PIGEON: int = 1
const OFFSET_ROGUE_ROOMBA: int = 2
const OFFSET_CATNIP_DEALER: int = 2
const OFFSET_HAUNTED_SPRAY_BOTTLE: int = 3
const OFFSET_DOG_KNIGHT: int = 4

static func kind_offset(kind: int) -> int:
	match kind:
		EnemyData.EnemyKind.ANGRY_PIGEON: return OFFSET_ANGRY_PIGEON
		EnemyData.EnemyKind.ROGUE_ROOMBA: return OFFSET_ROGUE_ROOMBA
		EnemyData.EnemyKind.CATNIP_DEALER: return OFFSET_CATNIP_DEALER
		EnemyData.EnemyKind.HAUNTED_SPRAY_BOTTLE: return OFFSET_HAUNTED_SPRAY_BOTTLE
		EnemyData.EnemyKind.DOG_KNIGHT: return OFFSET_DOG_KNIGHT
	return OFFSET_ANGRY_PIGEON

static func floor_baseline(floor_number: int) -> int:
	var f: int = maxi(1, floor_number)
	return FLOOR_BASELINE_BASE + FLOOR_BASELINE_STEP * (f - 1)

static func compute_level(kind: int, floor_number: int) -> int:
	return floor_baseline(floor_number) + kind_offset(kind)
