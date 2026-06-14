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
#   3. Place boss *last*. Re-point its single incoming edge at a grid-aware
#      anchor — the room furthest from start whose south footprint is clear — and
#      drop the boss one cell south of it. That yields a one-step vertical
#      corridor entering the boss's north wall (exit door on the south wall).
#      (Earlier this teleported the boss to the furthest grid cell while its
#      corridor still anchored to a possibly-near parent, so the L-shaped corridor
#      spanned the whole map — the "crazy long hallway" bug. The generator's boss
#      parent is provisional, only there to keep the graph connected.)
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

	# Boss placement: pick a grid-aware anchor (a far room with open space to its
	# south), re-point the boss's incoming edge at it, and drop the boss one cell
	# south. North-wall invariant: boss is strictly south of its parent so the
	# exit door always sits on the boss room's south wall.
	if dungeon.boss_id >= 0 and not positions.has(dungeon.boss_id):
		var anchor_id: int = _pick_boss_anchor(dungeon, positions, occupied)
		if anchor_id >= 0:
			# Re-point the boss's single incoming edge at the anchor. Idempotent:
			# repeated compute() on the same dungeon re-picks the same anchor and
			# re-attaches the already-attached boss, so the graph is unchanged.
			for r in dungeon.rooms:
				r.connections.erase(dungeon.boss_id)
			dungeon.get_room(anchor_id).connections.append(dungeon.boss_id)

			var anchor_pos: Vector2i = positions[anchor_id]
			var boss_pos := Vector2i(anchor_pos.x, anchor_pos.y + 1)
			positions[dungeon.boss_id] = boss_pos
			occupied[boss_pos] = dungeon.boss_id

	layout.room_positions = positions
	layout.boss_id = dungeon.boss_id

	# Corridors mirror the directed edges of the dungeon graph one-for-one.
	var corridors: Array = []
	for r in dungeon.rooms:
		for cid in r.connections:
			corridors.append([r.id, cid])
	layout.corridors = corridors

	return layout

# Picks the room the boss should hang off: the room furthest (manhattan) from
# start whose cell-to-the-south has a clear boss footprint, so the boss drops one
# cell south with a one-step corridor and no overlap. The southmost room always
# qualifies, so an anchor always exists. The bar is excluded (#180: boss must not
# be bar-adjacent). Ties break to the lowest id — deterministic regardless of the
# positions-dict iteration order, so co-op peers and repeated compute() agree.
func _pick_boss_anchor(dungeon: Dungeon, positions: Dictionary, occupied: Dictionary) -> int:
	var best_id: int = -1
	var best_dist: int = -1
	for rid in positions:
		if rid == dungeon.boss_id:
			continue
		var room := dungeon.get_room(rid)
		if room != null and room.type == Room.TYPE_BAR:
			continue
		var pos: Vector2i = positions[rid]
		if not _boss_footprint_clear(Vector2i(pos.x, pos.y + 1), occupied):
			continue
		var dist: int = abs(pos.x) + abs(pos.y)
		if dist > best_dist or (dist == best_dist and rid < best_id):
			best_dist = dist
			best_id = rid
	return best_id

# The boss room spans BOSS_ROOM_TILES (~1.4 grid steps), so it bleeds into the
# +x and +y neighbour cells. All four cells of its 2x2 grid footprint must be
# free or the boss room would visually overlap an adjacent room.
func _boss_footprint_clear(boss_pos: Vector2i, occupied: Dictionary) -> bool:
	for dy in range(2):
		for dx in range(2):
			if occupied.has(boss_pos + Vector2i(dx, dy)):
				return false
	return true

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
