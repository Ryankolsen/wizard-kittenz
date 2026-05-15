extends GutTest

# Tests for PRD #52 power-up pickup XP. Player.collect_power_up awards
# Player.POWERUP_XP on every pickup; co-op fans through the party-split
# broadcaster (each member receives floor(POWERUP_XP / party_size)).
# Solo applies directly to data via ProgressionSystem.add_xp.

func _make_character(level: int = 1) -> CharacterData:
	var c := CharacterData.make_new(CharacterData.CharacterClass.WIZARD_KITTEN, "k")
	c.level = level
	return c

func _make_lobby(specs: Array) -> LobbyState:
	var ls := LobbyState.new("ABCDE")
	for spec in specs:
		ls.add_player(LobbyPlayer.make(spec[0], spec[1], spec[2], false))
	return ls

func _make_two_room_dungeon() -> Dungeon:
	var d := Dungeon.new()
	var start := Room.make(0, Room.TYPE_START)
	start.connections = [1]
	d.add_room(start)
	d.start_id = 0
	var boss := Room.make(1, Room.TYPE_BOSS)
	boss.enemy_kind = EnemyData.EnemyKind.RAT
	d.add_room(boss)
	d.boss_id = 1
	return d

func _make_player_with_data(c: CharacterData) -> Player:
	var p := Player.new()
	p.data = c
	add_child_autofree(p)
	return p

# --- POWERUP_XP constant ----------------------------------------------------

func test_powerup_xp_constant_is_positive():
	# AC: POWERUP_XP is the tunable knob for power-up pickup reward.
	assert_gt(Player.POWERUP_XP, 0,
		"POWERUP_XP must be positive so pickup actually rewards")

# --- solo path --------------------------------------------------------------

func test_solo_power_up_pickup_awards_xp():
	# AC: Player.collect_power_up awards POWERUP_XP on pickup (solo).
	var c := _make_character(1)
	var xp_before := c.xp
	# Apply the same award helper Player.collect_power_up uses to avoid
	# booting GameState autoloads for a pure-data check.
	ProgressionSystem.add_xp(c, Player.POWERUP_XP)
	assert_eq(c.xp - xp_before, Player.POWERUP_XP,
		"solo power-up adds POWERUP_XP to character.xp")

func test_solo_power_up_pickup_scene_path_awards_xp():
	# End-to-end: a Player node in the scene, collect_power_up called
	# directly. Solo path (no co-op session) hits ProgressionSystem.add_xp.
	var c := _make_character(1)
	var p := _make_player_with_data(c)
	# _ready already ran (add_child fires it). Confirm clean baseline.
	var xp_before := p.data.xp
	p.collect_power_up(PowerUpEffect.TYPE_CATNIP)
	assert_eq(p.data.xp - xp_before, Player.POWERUP_XP,
		"collect_power_up path awarded POWERUP_XP")

# --- co-op path -------------------------------------------------------------

func test_coop_power_up_pickup_splits_xp_across_party():
	# AC: power-up XP splits by party size in co-op. 2-player party
	# → each gets floor(POWERUP_XP / 2).
	var lobby := _make_lobby([
		["u1", "A", "Mage"],
		["u2", "B", "Ninja"],
	])
	var c := _make_character(1)
	var session := CoopSession.new(lobby, {"u1": c, "u2": _make_character(1)}, null, "u1")
	session.start(_make_two_room_dungeon())
	# Snapshot + install onto GameState so collect_power_up's session
	# lookup returns this session.
	var saved_session := GameState.coop_session
	var saved_local_id := GameState.local_player_id
	GameState.coop_session = session
	GameState.local_player_id = "u1"
	var emissions: Array = []
	session.xp_broadcaster.xp_awarded.connect(func(pid, amt): emissions.append([pid, amt]))
	var p := _make_player_with_data(c)
	p.collect_power_up(PowerUpEffect.TYPE_CATNIP)
	assert_eq(emissions.size(), 2, "broadcaster fired for both party members")
	var expected_per_player := Player.POWERUP_XP / 2
	for e in emissions:
		assert_eq(e[1], expected_per_player, "floor(POWERUP_XP / 2) per member")
	# Restore.
	GameState.coop_session = saved_session
	GameState.local_player_id = saved_local_id

func test_coop_single_player_keeps_full_powerup_xp():
	# 1-player co-op session: full POWERUP_XP, no split.
	var lobby := _make_lobby([["u1", "A", "Mage"]])
	var c := _make_character(1)
	var session := CoopSession.new(lobby, {"u1": c}, null, "u1")
	session.start(_make_two_room_dungeon())
	var saved_session := GameState.coop_session
	var saved_local_id := GameState.local_player_id
	GameState.coop_session = session
	GameState.local_player_id = "u1"
	var p := _make_player_with_data(c)
	var xp_before := c.xp
	p.collect_power_up(PowerUpEffect.TYPE_CATNIP)
	# The CoopXPSubscriber wired by session.start routes the per-player
	# emission to c.real_stats.
	assert_eq(c.xp - xp_before, Player.POWERUP_XP,
		"1-player coop keeps full reward")
	GameState.coop_session = saved_session
	GameState.local_player_id = saved_local_id
