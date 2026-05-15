class_name Room
extends RefCounted

# A single node in the dungeon graph. Holds its id, type, the seeded contents
# (enemy / power-up), and the directed-edge connections to other room ids.
#
# Edges are directed so the boss room can be a true terminal node (no outgoing
# edges) while still being reachable from start. Connectivity (BFS test) walks
# only outgoing edges — see Dungeon.bfs_from_start().

const TYPE_START := "start"
const TYPE_STANDARD := "standard"
const TYPE_POWERUP := "powerup"
const TYPE_BOSS := "boss"

var id: int = 0
var type: String = TYPE_STANDARD
# Optional contents — populated by DungeonGenerator per-room. The room layer
# stores ids/strings rather than scene refs so the data layer stays unit-test
# friendly; the spawn/transition layer (lands with the room-transition step)
# resolves these into actual nodes.
var enemy_kind: int = -1
var power_up_type: String = ""
# Outgoing edges. A boss room has an empty connections list — that's the
# "terminal" invariant.
var connections: Array = []

static func make(room_id: int, room_type: String) -> Room:
	var r := Room.new()
	r.id = room_id
	r.type = room_type
	return r
