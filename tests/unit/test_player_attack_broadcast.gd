extends GutTest

# Tests for Player → NakamaLobby.send_attack_async broadcast (PRD #328
# slice 4 / issue #332). The local swing trigger must fan to the lobby
# in co-op (so every peer's RemoteKitten can play the matching swing
# via the existing AttackChoreographer path) and stay silent in solo.

class SpyLobby:
	extends NakamaLobby
	var attacks: Array = []  # [direction, kind, spell_id] triples
	func send_attack_async(direction: Vector2,
		kind: String = NakamaLobby.ATTACK_KIND_WEAPON_SWING,
		spell_id: String = "") -> void:
		attacks.append([direction, kind, spell_id])


class FakeGameStateNoLobby:
	var local_player_id: String = "me"
	var coop_session = null
	var lobby = null
	var offline_xp_tracker = null
	var currency_ledger = null
	var meta_tracker = null
	var current_character: CharacterData = null
	var skill_tree = null
	var item_inventory: ItemInventory = ItemInventory.new()


class FakeGameStateWithLobby:
	var local_player_id: String = "me"
	var coop_session = null
	var lobby = null  # SpyLobby
	var offline_xp_tracker = null
	var currency_ledger = null
	var meta_tracker = null
	var current_character: CharacterData = null
	var skill_tree = null
	var item_inventory: ItemInventory = ItemInventory.new()


func _make_player(fake) -> Player:
	fake.current_character = CharacterData.make_new(CharacterData.CharacterClass.BATTLE_KITTEN)
	var scene := load("res://scenes/player.tscn") as PackedScene
	var p := scene.instantiate() as Player
	p._inject_game_state(fake)
	add_child_autofree(p)
	return p


func test_local_attack_broadcasts_op_attack_with_facing_direction():
	# Co-op active (lobby present): the local Player's swing trigger must
	# fire exactly one send_attack_async call with the player's current
	# facing as the direction. The receiver derives attack_type from the
	# already-broadcast PLAYER_INFO state — no attack_type on the wire.
	var fake := FakeGameStateWithLobby.new()
	var spy := SpyLobby.new()
	fake.lobby = spy
	var p := _make_player(fake)
	# Stamp a known facing so we can assert the direction matches.
	p.data.facing = Vector2.RIGHT
	p._try_attack()
	assert_eq(spy.attacks.size(), 1,
		"local swing must broadcast exactly one OP_ATTACK")
	assert_eq(spy.attacks[0][0], Vector2.RIGHT,
		"broadcast direction matches the player's current facing")


func test_solo_attack_does_not_broadcast():
	# Solo path (no lobby on game state): _try_attack must not call
	# send_attack_async. Confirms the co-op gate fires before the wire
	# touch so single-player runs put zero attack packets on the wire.
	var fake := FakeGameStateNoLobby.new()
	# fake.lobby intentionally null — solo path
	var p := _make_player(fake)
	p.data.facing = Vector2.RIGHT
	# No spy to assert on — the assertion is "no crash + no broadcast".
	# Reaching this assertion after _try_attack is itself the proof:
	# Player._broadcast_attack must null-check _lobby() and bail.
	p._try_attack()
	assert_true(true, "solo path completes _try_attack without a lobby")


func test_blocked_attack_does_not_broadcast():
	# Cooldown gate: a re-entrant _try_attack call inside the cooldown
	# window must NOT broadcast — only the successful swing fires the
	# wire. Without this, attack-spam would flood the wire even though
	# no animation played locally.
	var fake := FakeGameStateWithLobby.new()
	var spy := SpyLobby.new()
	fake.lobby = spy
	var p := _make_player(fake)
	p.data.facing = Vector2.RIGHT
	p._try_attack()
	assert_eq(spy.attacks.size(), 1, "first attack lands")
	p._try_attack()  # cooldown gate rejects this
	assert_eq(spy.attacks.size(), 1,
		"cooldown-gated re-attack must not put a second packet on the wire")


# ---- Slice 5 of PRD #328 (issue #333): kind discriminator. ----

func test_battle_attack_broadcasts_kind_weapon_swing():
	# Non-cast attack (battle / chonk / sleepy) reads as weapon_swing
	# on the wire. spell_id stays empty.
	var fake := FakeGameStateWithLobby.new()
	var spy := SpyLobby.new()
	fake.lobby = spy
	var p := _make_player(fake)
	p.data.facing = Vector2.RIGHT
	p._try_attack()
	assert_eq(spy.attacks.size(), 1)
	assert_eq(spy.attacks[0][1], NakamaLobby.ATTACK_KIND_WEAPON_SWING,
		"battle class swings — kind must be weapon_swing")
	assert_eq(spy.attacks[0][2], "", "weapon_swing carries no spell_id")


func test_wizard_cast_attack_broadcasts_kind_spell_cast():
	# Wizard's primary basic attack uses WeaponDefinition.CAST
	# attack_type → reads as spell_cast on the wire so the receiver can
	# pick the cast-render path instead of a swing. spell_id stays empty
	# because the wizard primary isn't backed by a Spell object.
	# Sets up the choreographer directly with a CAST WeaponDefinition
	# rather than equipping a wand item — the broadcast-kind selection
	# lives in _try_attack and reads only from the choreographer's
	# definition.attack_type, so the test isolates that branch.
	var fake := FakeGameStateWithLobby.new()
	var spy := SpyLobby.new()
	fake.lobby = spy
	var p := _make_player(fake)
	var cast_def := WeaponDefinition.wizard()
	var choreo := AttackChoreographer.new()
	choreo.definition = cast_def
	p._attack_choreographer = choreo
	p.data.facing = Vector2.RIGHT
	p._try_attack()
	assert_eq(spy.attacks.size(), 1)
	assert_eq(spy.attacks[0][1], NakamaLobby.ATTACK_KIND_SPELL_CAST,
		"CAST attack_type (wizard primary) must broadcast as spell_cast")
	assert_eq(spy.attacks[0][2], "",
		"wizard primary carries no spell_id — pose comes from choreographer CAST")


func test_quickbar_slot_fire_broadcasts_kind_quickbar_cast_with_spell_id():
	# Slice 5 of PRD #328 (issue #333): a successful quickbar fire (the
	# slot_fired → _on_slot_fired path) must broadcast kind=quickbar_cast
	# with the bound Spell.id so every peer's RemoteKitten can mirror the
	# cast pose. Direction is the player's facing at the trigger moment.
	var fake := FakeGameStateWithLobby.new()
	var spy := SpyLobby.new()
	fake.lobby = spy
	var p := _make_player(fake)
	p.data.facing = Vector2.RIGHT
	# Drop a known spell into slot 1 directly so the test doesn't depend
	# on spell-tree seeding order.
	var qb = p.get_quickbar()
	var spell := Spell.make("fireball", "Fireball", Spell.EffectKind.DAMAGE, 5)
	qb.assign(1, spell)
	p._on_slot_fired(1)
	assert_eq(spy.attacks.size(), 1,
		"quickbar fire must broadcast exactly one OP_ATTACK packet")
	assert_eq(spy.attacks[0][1], NakamaLobby.ATTACK_KIND_QUICKBAR_CAST)
	assert_eq(spy.attacks[0][2], "fireball",
		"spell_id on the wire matches the bound slot's Spell.id")


func test_quickbar_slot_fire_solo_does_not_broadcast():
	# Solo path (no lobby) must not put a quickbar_cast packet on the
	# wire. Mirrors the slice-4 solo guard for weapon swings.
	var fake := FakeGameStateNoLobby.new()
	var p := _make_player(fake)
	var qb = p.get_quickbar()
	var spell := Spell.make("fireball", "Fireball", Spell.EffectKind.DAMAGE, 5)
	qb.assign(1, spell)
	p._on_slot_fired(1)
	assert_true(true, "solo _on_slot_fired completes without a lobby")


func test_quickbar_slot_fire_empty_slot_no_broadcast():
	# An _on_slot_fired call against an empty slot is a no-op — the
	# null-spell guard short-circuits before the broadcast hook.
	var fake := FakeGameStateWithLobby.new()
	var spy := SpyLobby.new()
	fake.lobby = spy
	var p := _make_player(fake)
	p._on_slot_fired(1)  # slot 1 was never assigned
	assert_eq(spy.attacks.size(), 0,
		"empty slot must not generate a quickbar_cast packet")
