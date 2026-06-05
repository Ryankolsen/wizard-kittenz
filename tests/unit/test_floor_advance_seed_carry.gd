extends GutTest

# Issue #349 — pins the determinism contract that closes PRD #348's
# "synced maps in co-op" pillar end-to-end: the seed the leader mints +
# broadcasts on OP_ADVANCE_FLOOR, once applied via
# DungeonSeedSync.apply_remote_seed on a receiver, produces an identical
# Dungeon graph to what the leader's own DungeonGenerator.generate(seed)
# produces. If this test ever drifts (e.g. someone adds a non-seeded RNG
# pull inside the generator), every client's next dungeon diverges and
# every existing co-op slice — kitten spawns, exit door, chest contents —
# desyncs silently. Sibling of tests/unit/test_dungeon_generator.gd.

func _structurally_equal(a: Dungeon, b: Dungeon) -> bool:
	if a.rooms.size() != b.rooms.size():
		return false
	if a.start_id != b.start_id:
		return false
	if a.boss_id != b.boss_id:
		return false
	for i in range(a.rooms.size()):
		var ra: Room = a.rooms[i]
		var rb: Room = b.rooms[i]
		if ra.id != rb.id or ra.type != rb.type:
			return false
		if ra.connections.size() != rb.connections.size():
			return false
		for j in range(ra.connections.size()):
			if ra.connections[j] != rb.connections[j]:
				return false
	return true

func test_host_mint_returns_non_negative_seed():
	# The minted seed is what's about to ride OP_ADVANCE_FLOOR; if it ever
	# comes back negative, _route_advance_floor's defensive guard would
	# drop the packet and the party would freeze on the congrats screen.
	var sync := DungeonSeedSync.new()
	var seed: int = sync.host_mint()
	assert_gte(seed, 0, "host_mint must produce a non-negative seed")

func test_applied_remote_seed_generates_identical_dungeon():
	# End-to-end determinism: leader mints, peer applies, both generate.
	# The two Dungeon graphs must be structurally identical — same room
	# count, per-room type / connections, same start_id and boss_id —
	# otherwise the synced-maps pillar of PRD #348 doesn't hold.
	var host_sync := DungeonSeedSync.new()
	var seed: int = host_sync.host_mint()
	var peer_sync := DungeonSeedSync.new()
	assert_true(peer_sync.apply_remote_seed(seed),
		"apply_remote_seed must accept a fresh non-negative seed")
	assert_eq(peer_sync.current_seed(), host_sync.current_seed(),
		"both sides converge on the same seed")
	var host_dungeon := DungeonGenerator.generate(host_sync.current_seed())
	var peer_dungeon := DungeonGenerator.generate(peer_sync.current_seed())
	assert_true(_structurally_equal(host_dungeon, peer_dungeon),
		"generated dungeons must be structurally identical across clients")

func test_seed_carry_survives_reset_cycle():
	# The leader's per-advance flow is reset() then host_mint(): a stale
	# previous-floor seed must not poison the next-floor mint. Pin that
	# the post-reset mint still threads cleanly to the peer's apply +
	# identical generator output.
	var host_sync := DungeonSeedSync.new()
	var _stale: int = host_sync.host_mint()
	host_sync.reset()
	var fresh_seed: int = host_sync.host_mint()
	assert_gte(fresh_seed, 0)
	var peer_sync := DungeonSeedSync.new()
	assert_true(peer_sync.apply_remote_seed(fresh_seed))
	var host_d := DungeonGenerator.generate(fresh_seed)
	var peer_d := DungeonGenerator.generate(peer_sync.current_seed())
	assert_true(_structurally_equal(host_d, peer_d))
