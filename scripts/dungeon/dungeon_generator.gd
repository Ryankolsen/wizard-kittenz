class_name DungeonGenerator
extends RefCounted

# Procedural dungeon layout. Stateless: `generate(seed)` returns a fresh
# Dungeon every call. Same seed -> same layout (so seed variance / replay
# semantics work); seed=0 means "pick a fresh random seed each call" so
# unseeded `generate()` calls diverge.
#
# Algorithm (random spanning tree with terminal boss):
#   1. Pick room count N in [MIN_ROOMS, MAX_ROOMS] from the RNG.
#   2. Room 0 is the start.
#   3. For i in 1..N-1: attach room i as a child of a random already-existing
#      room j in [0, i-1]. j gets `connections.append(i)`. This guarantees the
#      graph is a tree rooted at 0 (so BFS-from-0 reaches every node).
#   4. The last room (id N-1) is the boss. By construction it's added last
#      and is never picked as a parent, so its `connections` array stays
#      empty -> terminal-boss invariant.
#   5. Exactly one power-up room per type ({catnip, ale, mushrooms}) is
#      guaranteed: the three types are shuffled, then three distinct middle-room
#      slots are chosen at random to receive them. All remaining middle rooms
#      are standard combat rooms.
#   6. Each combat room (standard + boss) seeds an enemy kind. Boss draws
#      from BOSS_ENEMY_KINDS (currently {RAT}, the highest-stat existing
#      kind) — that's the "harder enemy variant" criterion. Standard rooms
#      draw from STANDARD_ENEMY_KINDS ({SLIME, BAT}).

const MIN_ROOMS := 5
const MAX_ROOMS := 10

# Standard rooms get the lower-stat enemies; boss draws from the harder pool.
# Boss-vs-standard separation is the "harder enemy variant" acceptance
# criterion. EnemyKind values: SLIME=0, BAT=1, RAT=2 (RAT has the highest
# base hp/attack/defense).
const STANDARD_ENEMY_KINDS := [
	EnemyData.EnemyKind.SLIME,
	EnemyData.EnemyKind.BAT,
]
const BOSS_ENEMY_KINDS := [
	EnemyData.EnemyKind.RAT,
]

const POWER_UP_TYPES := ["catnip", "ale", "mushrooms"]

# `seed < 0` -> draw a fresh random seed each call. Any non-negative seed
# (including 0) is deterministic — RandomNumberGenerator treats 0 as a real
# seed, so we use -1 as the "randomize" sentinel rather than overloading 0.
static func generate(seed: int = -1) -> Dungeon:
	var rng := RandomNumberGenerator.new()
	if seed < 0:
		rng.randomize()
	else:
		rng.seed = seed

	var room_count := rng.randi_range(MIN_ROOMS, MAX_ROOMS)
	var dungeon := Dungeon.new()

	# Room 0: start.
	var start := Room.make(0, Room.TYPE_START)
	dungeon.add_room(start)
	dungeon.start_id = 0

	# Guarantee exactly one power-up room per type by shuffling the type list
	# and randomly selecting that many distinct slots from the middle rooms.
	var middle_count := room_count - 2
	var shuffled_types := POWER_UP_TYPES.duplicate()
	_shuffle(shuffled_types, rng)

	var middle_offsets: Array = []
	for k in range(middle_count):
		middle_offsets.append(k)
	_shuffle(middle_offsets, rng)

	# powerup_room_ids maps room id -> power_up_type for the chosen slots.
	var powerup_room_ids: Dictionary = {}
	for j in range(min(shuffled_types.size(), middle_count)):
		powerup_room_ids[1 + middle_offsets[j]] = shuffled_types[j]

	# Rooms 1..N-2: power-up or standard, attached to a random existing room.
	for i in range(1, room_count - 1):
		var room: Room
		if powerup_room_ids.has(i):
			room = Room.make(i, Room.TYPE_POWERUP)
			room.power_up_type = powerup_room_ids[i]
		else:
			room = Room.make(i, Room.TYPE_STANDARD)
			room.enemy_kind = STANDARD_ENEMY_KINDS[rng.randi_range(0, STANDARD_ENEMY_KINDS.size() - 1)]
		var parent_idx := rng.randi_range(0, i - 1)
		dungeon.rooms[parent_idx].connections.append(i)
		dungeon.add_room(room)

	# Last room: boss. Always terminal (we never assign it as a parent because
	# the loop above only runs through i = room_count - 2).
	var boss_id := room_count - 1
	var boss := Room.make(boss_id, Room.TYPE_BOSS)
	boss.enemy_kind = BOSS_ENEMY_KINDS[rng.randi_range(0, BOSS_ENEMY_KINDS.size() - 1)]
	var boss_parent_idx := rng.randi_range(0, boss_id - 1)
	dungeon.rooms[boss_parent_idx].connections.append(boss_id)
	dungeon.add_room(boss)
	dungeon.boss_id = boss_id

	return dungeon

# Fisher-Yates shuffle using the generator's RNG for determinism.
static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
