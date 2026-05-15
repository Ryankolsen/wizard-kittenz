class_name Dungeon
extends RefCounted

# Container for a generated dungeon. Owns the rooms array and the start/boss
# ids. Provides the lookup + traversal helpers the tests assert against (BFS
# for connectivity, room_type_sequence for seed-variance comparisons).

var rooms: Array = []
var start_id: int = -1
var boss_id: int = -1

func add_room(room: Room) -> void:
	rooms.append(room)

func get_room(room_id: int) -> Room:
	for r in rooms:
		if r.id == room_id:
			return r
	return null

func size() -> int:
	return rooms.size()

# Walks outgoing edges from start_id in BFS order and returns the visited-set
# as a Dictionary keyed by room id. Connectivity test uses .size() against
# rooms.size() to assert "every room is reachable".
func bfs_from_start() -> Dictionary:
	var visited: Dictionary = {}
	if start_id < 0:
		return visited
	var queue: Array = [start_id]
	visited[start_id] = true
	while queue.size() > 0:
		var current_id: int = queue.pop_front()
		var current := get_room(current_id)
		if current == null:
			continue
		for next_id in current.connections:
			if visited.has(next_id):
				continue
			visited[next_id] = true
			queue.append(next_id)
	return visited

# Compact projection of room types in id order. Used by the seed-variance
# test: two distinct seeds should diverge somewhere in this sequence.
func room_type_sequence() -> Array:
	var seq: Array = []
	for r in rooms:
		seq.append(r.type)
	return seq

func boss_room() -> Room:
	return get_room(boss_id)

func start_room() -> Room:
	return get_room(start_id)
