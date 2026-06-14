class_name DungeonGenerator
extends RefCounted

# Procedural dungeon layout. Stateless: `generate(seed)` returns a fresh
# Dungeon every call. Same seed -> same layout (so seed variance / replay
# semantics work); seed=0 means "pick a fresh random seed each call" so
# unseeded `generate()` calls diverge.
#
# Algorithm (random spanning tree with terminal boss + guaranteed bar):
#   1. Pick room count N in [MIN_ROOMS, MAX_ROOMS] from the RNG.
#   2. Room 0 is the start.
#   3. Pick a bar slot bar_id in [2, N-4] and two distinct bar-child slots
#      from [bar_id+1, N-2]. The bar gets exactly those two outgoing edges.
#   4. For i in 1..N-2: attach room i as a child of either the bar (if it
#      is one of the two pre-picked bar children) or a random existing room
#      excluding the bar. j gets `connections.append(i)`. This keeps the
#      bar at exactly two outgoing edges while the rest stays a tree rooted
#      at 0 (so BFS-from-0 reaches every node).
#   5. The last room (id N-1) is the boss. Its parent is also picked
#      excluding the bar, so the boss is never adjacent to the bar.
#   6. Exactly one power-up room per type ({catnip, ale, mushrooms}) is
#      guaranteed: the three types are shuffled, then three distinct middle-room
#      slots (excluding the bar slot) are chosen at random. All remaining
#      middle rooms are standard combat rooms.
#   7. Each combat room (standard + boss) seeds an enemy kind. Boss and
#      standard rooms both draw from the full 5-kind roster today (per PRD
#      #151). Boss "difficulty" comes from the RoomSpawnPlanner boss stat
#      multipliers, not from a separate stronger pool. A future per-dungeon
#      data-driven enemy config will replace the constants below.

const MIN_ROOMS := 100
const MAX_ROOMS := 150

# Standard rooms still draw a random kind from the full 5-kind roster
# (PRD #151). All kinds share equal base stats this phase; per-room
# differentiation is a future PRD. The boss room's kind is no longer drawn
# from a pool — it's a deterministic per-floor lookup via BossRoster
# (PRD #297, slice #301), so BOSS_ENEMY_KINDS is gone.
const STANDARD_ENEMY_KINDS := [
	EnemyData.EnemyKind.ANGRY_PIGEON,
	EnemyData.EnemyKind.ROGUE_ROOMBA,
	EnemyData.EnemyKind.DOG_KNIGHT,
	EnemyData.EnemyKind.CATNIP_DEALER,
	EnemyData.EnemyKind.HAUNTED_SPRAY_BOTTLE,
]

const POWER_UP_TYPES := ["catnip", "ale", "mushrooms"]

# `seed < 0` -> draw a fresh random seed each call. Any non-negative seed
# (including 0) is deterministic — RandomNumberGenerator treats 0 as a real
# seed, so we use -1 as the "randomize" sentinel rather than overloading 0.
static func generate(seed: int = -1, floor_number: int = 1) -> Dungeon:
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

	# Pick the bar slot. Constraints (#180):
	#   - not the start (id 0) or boss (id room_count - 1)
	#   - not adjacent to the boss (boss's parent must not be the bar)
	#   - has exactly 2 outgoing edges -> need at least 2 later non-boss
	#     slots to attach as bar children, so bar_id <= room_count - 4.
	# bar_id >= 2 keeps the bar's own parent choice from collapsing to {0}.
	var bar_id := rng.randi_range(2, room_count - 4)
	var child_candidates: Array = []
	for k in range(bar_id + 1, room_count - 1):
		child_candidates.append(k)
	_shuffle(child_candidates, rng)
	var bar_child_a: int = child_candidates[0]
	var bar_child_b: int = child_candidates[1]

	# Guarantee exactly one power-up room per type by shuffling the type list
	# and randomly selecting that many distinct slots from the middle rooms.
	# The bar slot is excluded so it can never double as a power-up.
	var middle_count := room_count - 2
	var shuffled_types := POWER_UP_TYPES.duplicate()
	_shuffle(shuffled_types, rng)

	var middle_offsets: Array = []
	for k in range(middle_count):
		if 1 + k == bar_id:
			continue
		middle_offsets.append(k)
	_shuffle(middle_offsets, rng)

	# powerup_room_ids maps room id -> power_up_type for the chosen slots.
	var powerup_room_ids: Dictionary = {}
	for j in range(min(shuffled_types.size(), middle_offsets.size())):
		powerup_room_ids[1 + middle_offsets[j]] = shuffled_types[j]

	# Rooms 1..N-2: bar, power-up, or standard, attached per the bar plan.
	for i in range(1, room_count - 1):
		var room: Room
		if i == bar_id:
			room = Room.make(i, Room.TYPE_BAR)
		elif powerup_room_ids.has(i):
			room = Room.make(i, Room.TYPE_POWERUP)
			room.power_up_type = powerup_room_ids[i]
		else:
			room = Room.make(i, Room.TYPE_STANDARD)
			var pop: Dictionary = RoomPopulationPlanner.plan_full_for_room_type(rng, Room.TYPE_STANDARD)
			room.enemy_kinds = pop["kinds"]
			room.enemy_elites = pop["elites"]
			room.enemy_elite_bonuses = pop["elite_bonuses"]
			room.enemy_kind = room.enemy_kinds[0]
		var parent_idx: int
		if i == bar_child_a or i == bar_child_b:
			parent_idx = bar_id
		else:
			parent_idx = _pick_parent_excluding(rng, i, bar_id)
		dungeon.rooms[parent_idx].connections.append(i)
		dungeon.add_room(room)

	# Last room: boss. Always terminal (we never assign it as a parent because
	# the loop above only runs through i = room_count - 2). Boss's parent must
	# not be the bar — that would make them adjacent.
	var boss_id := room_count - 1
	var boss := Room.make(boss_id, Room.TYPE_BOSS)
	# Boss kind + sprite paths are a deterministic per-floor lookup so each
	# floor's boss feels distinct without re-rolling on retry / save-restore.
	# Stamping the sprite paths onto the room (rather than re-querying at
	# spawn time) lets the spawn layer + Enemy node stay floor-agnostic —
	# they just read what's on the data they were handed.
	var boss_info := BossRoster.boss_for_floor(floor_number)
	boss.enemy_kind = boss_info.kind
	boss.enemy_kinds = [boss_info.kind]
	boss.boss_sprite_left_path = boss_info.sprite_left_path
	boss.boss_sprite_right_path = boss_info.sprite_right_path
	boss.boss_display_name = boss_info.display_name
	# Attach the boss so the graph stays connected (BFS-from-start reaches it).
	# This parent is provisional: the layout engine re-points the boss's incoming
	# edge at a grid-aware anchor (a far room with open space to its south) so the
	# boss corridor is one short step instead of a map-spanning hallway. Excluded
	# from the bar (#180: boss must not be bar-adjacent).
	var boss_parent_idx := _pick_parent_excluding(rng, boss_id, bar_id)
	dungeon.rooms[boss_parent_idx].connections.append(boss_id)
	dungeon.add_room(boss)
	dungeon.boss_id = boss_id

	# Ease the player into a crawl: rooms directly connected to the start are
	# the first encounters, so trim each start-adjacent standard room down to a
	# single mob. Done as a post-pass (rather than during population) so it
	# doesn't perturb the RNG stream — the multi-mob roll still happens, we just
	# discard the extras for these specific rooms. Non-standard neighbours
	# (powerup/bar) carry no enemies and are skipped.
	_ease_start_adjacent_rooms(dungeon)

	return dungeon

# Trims every standard room directly connected to the start down to one mob,
# keeping the parallel enemy arrays consistent.
static func _ease_start_adjacent_rooms(dungeon: Dungeon) -> void:
	var start := dungeon.get_room(dungeon.start_id)
	if start == null:
		return
	for child_id in start.connections:
		var child: Room = dungeon.get_room(child_id)
		if child == null or child.type != Room.TYPE_STANDARD:
			continue
		if child.enemy_kinds.size() <= 1:
			continue
		child.enemy_kinds = [child.enemy_kinds[0]]
		child.enemy_elites = [child.enemy_elites[0]]
		child.enemy_elite_bonuses = [child.enemy_elite_bonuses[0]]
		child.enemy_kind = child.enemy_kinds[0]

# Picks a random parent in [0, child_id - 1] that is not `excluded_id`.
# child_id >= 1 and excluded_id may be -1 (no exclusion) or a value in range.
static func _pick_parent_excluding(rng: RandomNumberGenerator, child_id: int, excluded_id: int) -> int:
	# child_id == 1 guarantees parent == 0; we never set excluded_id to 0
	# (bar_id >= 2), so no infinite-loop risk.
	while true:
		var p := rng.randi_range(0, child_id - 1)
		if p != excluded_id:
			return p
	return 0

# Fisher-Yates shuffle using the generator's RNG for determinism.
static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
