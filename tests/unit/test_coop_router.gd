extends GutTest

# CoopRouter consolidates the former LocalDamageRouter + LocalReviveRouter
# into a single static class. Tests cover the shared target_for branching
# rule (solo vs. co-op vs. null-safety) plus the two thin call-site
# wrappers, apply_damage and revive. Sibling-shaped to KillRewardRouter:
# RefCounted, all-static, delegates to session.is_routing_ready().

# --- Test fixtures ----------------------------------------------------------

func _make_lobby(player_specs: Array) -> LobbyState:
	var ls := LobbyState.new("ABCDE")
	for spec in player_specs:
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

func _make_active_session(local_id: String = "u1") -> CoopSession:
	# Active session bound to local_id with one party member (L1 Mage).
	var lobby := _make_lobby([["u1", "A", "Mage"]])
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE, "k")
	c.level = 1
	c.xp = 0
	var session := CoopSession.new(lobby, {"u1": c}, null, local_id)
	session.start(_make_two_room_dungeon())
	return session

func _make_attacker(attack: int) -> EnemyData:
	# Minimal enemy attacker for damage routing tests. DamageResolver only
	# reads `attack: int` off attacker_stats; defense/hp on the attacker
	# are irrelevant for incoming-damage-to-player flows.
	var e := EnemyData.make_new(EnemyData.EnemyKind.SLIME)
	e.attack = attack
	return e

# PRD #85: DamageResolver gates damage behind HitResolver (15% miss floor).
# Routing tests need a deterministic hit, so we hand apply_damage a pre-
# seeded rng whose first randf is below 0.85 (forces hit). crit and
# evasion are 0/0.0 here, so the hit roll is the only rng consumer.
func _rng_force_hit() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	for s in range(1, 100000):
		rng.seed = s
		if rng.randf() < 0.85:
			rng.seed = s
			return rng
	return rng

# --- CoopRouter.target_for --------------------------------------------------

func test_target_for_solo_returns_character():
	# Solo path: target_for returns the input character itself. Player.gd's
	# `data` field holds real_stats in solo (real == effective), so events
	# land on the right block via the same CharacterData reference the
	# HUD reads from.
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE, "k")
	assert_eq(CoopRouter.target_for(null, c, "u1"), c)

func test_target_for_coop_returns_effective_stats():
	# Co-op happy path: target_for returns the local member's
	# effective_stats. Floor player gets a clone whose stats match
	# real_stats — but it's still the effective reference, not the input
	# character.
	var session := _make_active_session("u1")
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE, "k")
	var target := CoopRouter.target_for(session, c, "u1")
	var member := session.member_for("u1")
	assert_ne(target, c, "co-op route should not return the input character")
	assert_eq(target, member.effective_stats, "co-op route returns effective_stats")

func test_target_for_null_character_returns_null():
	# Null-safe: a caller with no character (test path / pre-spawn) gets
	# null back rather than a crash. apply_damage / revive use this to
	# short-circuit.
	assert_eq(CoopRouter.target_for(null, null, "u1"), null)

func test_target_for_empty_local_id_returns_character():
	# Active session but empty local id => routing-not-ready => character.
	# Pinned so a refactor that made the empty-id case return the first
	# member in the party (a tempting "default to head of list" shortcut)
	# breaks loud.
	var session := _make_active_session("u1")
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE, "k")
	assert_eq(CoopRouter.target_for(session, c, ""), c)

# --- CoopRouter.apply_damage ------------------------------------------------

func test_apply_damage_solo_hits_character():
	# Solo path end-to-end: damage lands on the character's hp.
	# DamageResolver mitigates via target.defense; Mage L1 has defense 0
	# so a 3-attack lands as 3 damage.
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE, "k")
	var hp_before := c.hp
	var attacker := _make_attacker(3)
	var dealt := CoopRouter.apply_damage(null, attacker, c, "", _rng_force_hit())
	assert_eq(dealt, 3)
	assert_eq(c.hp, hp_before - 3, "solo damage hits character.hp directly")

func test_apply_damage_coop_hits_effective_not_real():
	# The whole point of the router: in co-op, damage hits effective_stats
	# and leaves real_stats untouched. PartyMember.from_character makes
	# real_stats == input character (by reference) and effective_stats =
	# clone, so a damage call that mutated real_stats would visibly reduce
	# the input character's hp too.
	var session := _make_active_session("u1")
	var member := session.member_for("u1")
	var c := member.real_stats
	var real_hp_before := c.hp
	var eff_hp_before := member.effective_stats.hp
	var attacker := _make_attacker(3)
	var dealt := CoopRouter.apply_damage(session, attacker, c, "u1", _rng_force_hit())
	assert_eq(dealt, 3)
	assert_eq(c.hp, real_hp_before, "real_stats.hp untouched in co-op")
	assert_eq(member.effective_stats.hp, eff_hp_before - 3, "effective_stats.hp reduced")

func test_apply_damage_null_attacker_returns_zero():
	# Null-safe: a future kill source that doesn't pass attacker stats
	# (e.g. environmental hazard) degrades to no-op.
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE, "k")
	var hp_before := c.hp
	assert_eq(CoopRouter.apply_damage(null, null, c, ""), 0)
	assert_eq(c.hp, hp_before, "null attacker leaves character untouched")

func test_apply_damage_null_character_returns_zero():
	# Null-safe: pre-spawn / test path with no character data.
	var attacker := _make_attacker(3)
	assert_eq(CoopRouter.apply_damage(null, attacker, null, ""), 0)

func test_apply_damage_zero_attack_no_op():
	# DamageResolver returns 0 when attacker.attack <= 0 (it's the only
	# path that lets damage be 0 — defense floor is 1). Pin the routing
	# pass-through: the router must not paper over the zero with a
	# 1-damage minimum of its own.
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE, "k")
	var hp_before := c.hp
	var attacker := _make_attacker(0)
	assert_eq(CoopRouter.apply_damage(null, attacker, c, ""), 0)
	assert_eq(c.hp, hp_before)

func test_apply_damage_defense_mitigates_to_floor_one():
	# DamageResolver's defense floor is 1 (no zero-damage hits when
	# attacker has any positive attack). Pin that the router inherits
	# the contract: an attack of 1 against a defense-3 target still
	# lands for 1 damage in solo.
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE, "k")
	c.defense = 3
	var hp_before := c.hp
	var attacker := _make_attacker(1)
	var dealt := CoopRouter.apply_damage(null, attacker, c, "", _rng_force_hit())
	assert_eq(dealt, 1, "defense floor of 1")
	assert_eq(c.hp, hp_before - 1)

func test_apply_damage_after_end_routes_to_character():
	# Post-end() session: end() restores scaling (real == effective) and
	# drops managers. A late-arriving damage event must route to the
	# character (the solo target) so it lands on real_stats — the right
	# block once scaling is gone.
	var session := _make_active_session("u1")
	var member := session.member_for("u1")
	var c := member.real_stats
	session.end()
	var hp_before := c.hp
	var attacker := _make_attacker(2)
	var dealt := CoopRouter.apply_damage(session, attacker, c, "u1", _rng_force_hit())
	assert_eq(dealt, 2, "post-end damage still applies, routed to character")
	assert_eq(c.hp, hp_before - 2)

func test_apply_damage_floor_player_routes_to_effective_not_real():
	# Floor player: scale_stats returns a CLONE of real_stats with
	# identical numbers. The clone is still a separate Resource — damage
	# to effective_stats must not leak into real_stats.
	var lobby := _make_lobby([["u1", "A", "Mage"]])
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE, "k")
	var session := CoopSession.new(lobby, {"u1": c}, null, "u1")
	session.start(_make_two_room_dungeon())
	var member := session.member_for("u1")
	assert_eq(member.real_stats.level, member.effective_stats.level)
	assert_ne(member.real_stats, member.effective_stats,
		"PartyScaler.clone_stats produces a separate reference even at floor")
	var real_hp_before := c.hp
	var attacker := _make_attacker(2)
	CoopRouter.apply_damage(session, attacker, c, "u1", _rng_force_hit())
	assert_eq(c.hp, real_hp_before, "floor-player real_stats untouched")
	assert_eq(member.effective_stats.hp, member.effective_stats.max_hp - 2,
		"floor-player effective_stats took the hit")

func test_apply_damage_scaled_player_uses_lower_max_hp():
	# Scaled player end-to-end: a L10 player in a party with a L3
	# floor-mate has effective_stats.max_hp set to the L3 baseline.
	# Damage routes to the smaller pool.
	var lobby := _make_lobby([
		["u1", "Big",   "Mage"],
		["u2", "Small", "Mage"],
	])
	var c1 := CharacterData.make_new(CharacterData.CharacterClass.MAGE, "Big")
	c1.level = 10
	c1.max_hp = CharacterData.base_max_hp_for(CharacterData.CharacterClass.MAGE, 10)
	c1.hp = c1.max_hp
	var c2 := CharacterData.make_new(CharacterData.CharacterClass.MAGE, "Small")
	c2.level = 3
	c2.max_hp = CharacterData.base_max_hp_for(CharacterData.CharacterClass.MAGE, 3)
	c2.hp = c2.max_hp
	var session := CoopSession.new(lobby, {"u1": c1, "u2": c2}, null, "u1")
	session.start(_make_two_room_dungeon())
	var member := session.member_for("u1")
	# Mage L10: max_hp = 8 + 9*2 = 26. L3 (floor): 8 + 2*2 = 12.
	assert_eq(c1.max_hp, 26, "real_stats max_hp at L10")
	assert_eq(member.effective_stats.max_hp, 12, "effective_stats max_hp at floor L3")
	var attacker := _make_attacker(5)
	CoopRouter.apply_damage(session, attacker, c1, "u1", _rng_force_hit())
	assert_eq(c1.hp, 26, "real_stats hp untouched")
	assert_eq(member.effective_stats.hp, 7, "effective_stats took 5 dmg from 12")

# --- CoopRouter.revive ------------------------------------------------------

func test_revive_solo_revives_character():
	# Solo path end-to-end: sets character.hp to half max_hp. Mage default
	# max_hp=10 => revive at 5. Free revive (post-#27) — no inventory.
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE, "k")
	c.max_hp = 10
	c.hp = 0
	var ok := CoopRouter.revive(null, c, "")
	assert_true(ok)
	assert_eq(c.hp, 5, "character.hp restored to 50% of max_hp")

func test_revive_coop_revives_effective_not_real():
	# Co-op: revive lands on effective_stats and leaves real_stats
	# untouched. Pin both sides.
	var session := _make_active_session("u1")
	var member := session.member_for("u1")
	var c := member.real_stats
	# Simulate the death state: damage routed to effective_stats has
	# zeroed it; real_stats stays at full because CoopRouter.apply_damage
	# never touches it in co-op.
	member.effective_stats.hp = 0
	var real_hp_before := c.hp
	var ok := CoopRouter.revive(session, c, "u1")
	assert_true(ok)
	assert_eq(c.hp, real_hp_before, "real_stats.hp untouched in co-op revive")
	# Mage L1 effective_stats.max_hp = 8 (base 8 + (1-1)*2) => round(4.0) = 4.
	assert_eq(member.effective_stats.hp, 4, "effective_stats.hp restored to 50%")

func test_revive_null_character_no_op():
	# Null-safe: pre-spawn / test path with no character data. Must not
	# crash; returns false so the caller's death-screen branch can stay
	# a single unconditional call site.
	assert_false(CoopRouter.revive(null, null, ""))

func test_revive_after_end_revives_character():
	# Post-end() session: end() restored scaling (real == effective) and
	# dropped managers. A revive that fires from the death-screen during
	# the same teardown frame routes to character (the solo target).
	var session := _make_active_session("u1")
	var member := session.member_for("u1")
	var c := member.real_stats
	c.hp = 0
	session.end()
	var ok := CoopRouter.revive(session, c, "u1")
	assert_true(ok)
	assert_eq(c.hp, 4, "post-end revive lands on character (real_stats)")

func test_revive_floor_player_revives_effective_not_real():
	# Floor player: scale_stats returns a CLONE of real_stats. Revive on
	# effective_stats must not leak into real_stats.
	var lobby := _make_lobby([["u1", "A", "Mage"]])
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE, "k")
	var session := CoopSession.new(lobby, {"u1": c}, null, "u1")
	session.start(_make_two_room_dungeon())
	var member := session.member_for("u1")
	assert_eq(member.real_stats.max_hp, member.effective_stats.max_hp)
	assert_ne(member.real_stats, member.effective_stats,
		"PartyScaler.clone_stats produces a separate reference even at floor")
	member.effective_stats.hp = 0
	var real_hp_before := c.hp
	CoopRouter.revive(session, c, "u1")
	assert_eq(c.hp, real_hp_before, "floor-player real_stats untouched on revive")
	assert_eq(member.effective_stats.hp, 4,
		"floor-player effective_stats restored to half max")

func test_revive_scaled_player_uses_lower_max_hp():
	# Scaled player: a L10 player in a party with a L3 floor-mate has
	# effective_stats.max_hp = L3 baseline (12). Revive routes to
	# effective_stats so the revive HP is half of 12 = 6, NOT half of
	# the unscaled 26 = 13.
	var lobby := _make_lobby([
		["u1", "Big",   "Mage"],
		["u2", "Small", "Mage"],
	])
	var c1 := CharacterData.make_new(CharacterData.CharacterClass.MAGE, "Big")
	c1.level = 10
	c1.max_hp = CharacterData.base_max_hp_for(CharacterData.CharacterClass.MAGE, 10)
	c1.hp = c1.max_hp
	var c2 := CharacterData.make_new(CharacterData.CharacterClass.MAGE, "Small")
	c2.level = 3
	c2.max_hp = CharacterData.base_max_hp_for(CharacterData.CharacterClass.MAGE, 3)
	c2.hp = c2.max_hp
	var session := CoopSession.new(lobby, {"u1": c1, "u2": c2}, null, "u1")
	session.start(_make_two_room_dungeon())
	var member := session.member_for("u1")
	assert_eq(c1.max_hp, 26)
	assert_eq(member.effective_stats.max_hp, 12)
	member.effective_stats.hp = 0
	var ok := CoopRouter.revive(session, c1, "u1")
	assert_true(ok)
	assert_eq(c1.hp, 26, "real_stats hp untouched")
	# round(12 * 0.5) = 6, above the minimum-1 floor.
	assert_eq(member.effective_stats.hp, 6,
		"effective_stats revived to half of scaled max_hp (12), NOT half of real (26)")

func test_revive_min_one_hp_floor_inherits_through_router():
	# ReviveSystem's min-1 floor (max_hp=1 must not revive at 0) inherits
	# through the router unchanged.
	var c := CharacterData.make_new(CharacterData.CharacterClass.MAGE, "k")
	c.max_hp = 1
	c.hp = 0
	var ok := CoopRouter.revive(null, c, "")
	assert_true(ok)
	assert_eq(c.hp, 1, "min-1 floor survives the router pass-through")
