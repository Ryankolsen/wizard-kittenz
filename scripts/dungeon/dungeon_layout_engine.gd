class_name DungeonLayoutEngine
extends RefCounted

# Pure-data: turn a Dungeon graph into a DungeonLayout with grid positions
# and corridor edges. No scene tree, no side effects, deterministic for a
# fixed input dungeon (required for co-op: each peer computes the same
# layout from the synced seed -> same room placements).
#
# Algorithm:
#   1. Place start at (0, 0).
#   2. BFS the directed tree from start. For each non-boss child, place it
#      at the first free cell spiraling outward from its parent in the
#      cardinal order right/down/left/up. Cardinal order is fixed, so the
#      layout is a deterministic function of the dungeon graph.
#   3. Place boss *last* at the first free cell along +x past the current
#      max manhattan distance — this enforces the "boss is furthest from
#      start" invariant regardless of where the boss attaches in the tree
#      (the generator picks the boss's parent randomly, so boss is not
#      always the deepest tree node).
#   4. Corridors mirror the directed edges of the dungeon graph one-for-one.

const DIRECTIONS := [
	Vector2i(1, 0),
	Vector2i(0, 1),
	Vector2i(-1, 0),
	Vector2i(0, -1),
]

func compute(dungeon: Dungeon) -> DungeonLayout:
	var layout := DungeonLayout.new()
	if dungeon == null or dungeon.start_id < 0:
		return layout

	var positions: Dictionary = {}
	var occupied: Dictionary = {}

	positions[dungeon.start_id] = Vector2i(0, 0)
	occupied[Vector2i(0, 0)] = dungeon.start_id

	# BFS the tree from start, skipping the boss — boss is placed in a
	# dedicated pass so we can guarantee it's at the furthest grid distance.
	var queue: Array = [dungeon.start_id]
	while queue.size() > 0:
		var rid: int = queue.pop_front()
		var room := dungeon.get_room(rid)
		if room == null:
			continue
		var parent_pos: Vector2i = positions[rid]
		for cid in room.connections:
			if cid == dungeon.boss_id:
				continue
			if positions.has(cid):
				continue
			var child_pos := _find_free_cell(parent_pos, occupied)
			positions[cid] = child_pos
			occupied[child_pos] = cid
			queue.append(cid)

	# Boss placement: furthest manhattan distance from origin. Walk +x past
	# the current max distance, then nudge forward until we find a free cell.
	if dungeon.boss_id >= 0 and not positions.has(dungeon.boss_id):
		var max_dist: int = 0
		for p in positions.values():
			var d: int = abs(p.x) + abs(p.y)
			if d > max_dist:
				max_dist = d
		var boss_pos := Vector2i(max_dist + 1, 0)
		while occupied.has(boss_pos):
			boss_pos.x += 1
		positions[dungeon.boss_id] = boss_pos
		occupied[boss_pos] = dungeon.boss_id

	layout.room_positions = positions

	# Corridors mirror the directed edges of the dungeon graph one-for-one.
	var corridors: Array = []
	for r in dungeon.rooms:
		for cid in r.connections:
			corridors.append([r.id, cid])
	layout.corridors = corridors

	return layout

# Deterministic spiral search: try each cardinal direction at distance 1,
# then 2, etc. The cardinal order (right/down/left/up) is fixed so the same
# parent_pos + occupied-set always yields the same chosen cell.
func _find_free_cell(parent_pos: Vector2i, occupied: Dictionary) -> Vector2i:
	for dist in range(1, 100):
		for dir in DIRECTIONS:
			var cand: Vector2i = parent_pos + dir * dist
			if not occupied.has(cand):
				return cand
	# Fallback: 5..10 rooms can't fill a 100-radius region. Returning
	# parent_pos here would collide, but it's unreachable in practice.
	return parent_pos
