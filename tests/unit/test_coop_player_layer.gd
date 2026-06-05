extends GutTest

# Tests for CoopPlayerLayer added in #35. The layer renders one RemoteKitten
# per remote player_id in the active lobby and reconciles spawns/frees as
# the lobby roster changes. The local player_id is always skipped — the
# local Player node renders that one.
#
# Tests use reconcile() directly rather than relying on signal timing so
# the assertions don't depend on a CoopSession round-trip through Nakama.

const REMOTE_KITTEN_PATH := "res://scenes/remote_kitten.tscn"

func _make_lobby_with_players(local_id: String, ids: Array) -> NakamaLobby:
	var nl := NakamaLobby.new()
	nl.local_player_id = local_id
	var ls := LobbyState.new("ABCDE")
	for id in ids:
		ls.add_player(LobbyPlayer.make(id, "k_%s" % id, "Mage"))
	nl.lobby_state = ls
	return nl

func _make_session_with_party(party_ids: Array) -> CoopSession:
	# A minimal session whose network_sync the layer can hand off to
	# RemoteKitten instances. We don't need to call start() — the
	# layer only reads coop_session.network_sync, which we set directly.
	var session := CoopSession.new()
	session.network_sync = NetworkSyncManager.new()
	# party_ids registered for parity with the real flow, but the layer
	# reads roster from the lobby, not the session.
	for pid in party_ids:
		session.network_sync.apply_remote_state(pid, Vector2.ZERO, 0.0)
	return session

func before_each():
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.set_lobby(null)
		gs.coop_session = null
		gs.local_player_id = ""

func after_each():
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		gs.set_lobby(null)
		gs.coop_session = null
		gs.local_player_id = ""

func test_reconcile_spawns_one_remote_kitten_per_remote_player():
	# Issue acceptance criterion: applying a lobby state with two remote
	# players produces two RemoteKitten children.
	var gs := get_node("/root/GameState")
	gs.set_lobby(_make_lobby_with_players("me", ["me", "alice", "bob"]))
	gs.coop_session = _make_session_with_party(["alice", "bob"])
	var layer := CoopPlayerLayer.new()
	add_child_autofree(layer)
	# _ready already reconciled once; assert end state.
	assert_eq(layer.remote_kitten_count(), 2,
		"two remote players => two RemoteKitten children")
	assert_not_null(layer.remote_kitten_for("alice"))
	assert_not_null(layer.remote_kitten_for("bob"))

func test_reconcile_skips_local_player_id():
	# Issue acceptance criterion: the local player_id never produces a
	# RemoteKitten child — the local Player node already renders that one.
	var gs := get_node("/root/GameState")
	gs.set_lobby(_make_lobby_with_players("me", ["me", "alice"]))
	gs.coop_session = _make_session_with_party(["alice"])
	var layer := CoopPlayerLayer.new()
	add_child_autofree(layer)
	assert_eq(layer.remote_kitten_count(), 1)
	assert_null(layer.remote_kitten_for("me"),
		"local kitten never rendered through this layer")

func test_reconcile_frees_kitten_when_player_removed():
	# Issue acceptance criterion: removing one player from the lobby frees
	# exactly that child and leaves the other.
	var gs := get_node("/root/GameState")
	var lobby := _make_lobby_with_players("me", ["me", "alice", "bob"])
	gs.set_lobby(lobby)
	gs.coop_session = _make_session_with_party(["alice", "bob"])
	var layer := CoopPlayerLayer.new()
	add_child_autofree(layer)
	assert_eq(layer.remote_kitten_count(), 2)
	# Remove alice from the roster.
	lobby.lobby_state.remove_player("alice")
	layer.reconcile()
	assert_eq(layer.remote_kitten_count(), 1, "alice freed, bob retained")
	assert_null(layer.remote_kitten_for("alice"))
	assert_not_null(layer.remote_kitten_for("bob"))

func test_reconcile_is_idempotent():
	# Issue acceptance criterion: re-applying the same lobby state is
	# idempotent — no duplicate nodes spawned. Without this, every
	# lobby_updated emission (which can fire on any roster mutation, even
	# unrelated ones like a ready-toggle) would double the child count.
	var gs := get_node("/root/GameState")
	gs.set_lobby(_make_lobby_with_players("me", ["me", "alice", "bob"]))
	gs.coop_session = _make_session_with_party(["alice", "bob"])
	var layer := CoopPlayerLayer.new()
	add_child_autofree(layer)
	var alice_first := layer.remote_kitten_for("alice")
	layer.reconcile()
	layer.reconcile()
	layer.reconcile()
	assert_eq(layer.remote_kitten_count(), 2, "still two after repeated reconciles")
	assert_eq(layer.remote_kitten_for("alice"), alice_first,
		"existing child instance reused, not respawned")

func test_reconcile_clears_all_when_lobby_cleared():
	# Defensive: if GameState.lobby is set to null mid-session (e.g. host
	# leaves), the layer must drop its kittens rather than holding stale
	# remote players that can't receive position updates anymore.
	var gs := get_node("/root/GameState")
	gs.set_lobby(_make_lobby_with_players("me", ["me", "alice"]))
	gs.coop_session = _make_session_with_party(["alice"])
	var layer := CoopPlayerLayer.new()
	add_child_autofree(layer)
	assert_eq(layer.remote_kitten_count(), 1)
	gs.set_lobby(null)
	layer.reconcile()
	assert_eq(layer.remote_kitten_count(), 0, "no lobby => no remote kittens")

func test_reconcile_clears_all_when_session_cleared():
	# Same defensive: session ended but lobby still around (multi-run
	# match between dungeons). No session == no network_sync to drive
	# remote kitten interpolation, so render nothing rather than freeze
	# them at their last position with no incoming updates.
	var gs := get_node("/root/GameState")
	gs.set_lobby(_make_lobby_with_players("me", ["me", "alice"]))
	gs.coop_session = _make_session_with_party(["alice"])
	var layer := CoopPlayerLayer.new()
	add_child_autofree(layer)
	assert_eq(layer.remote_kitten_count(), 1)
	gs.coop_session = null
	layer.reconcile()
	assert_eq(layer.remote_kitten_count(), 0, "no session => no remote kittens")

func test_reconcile_assigns_distinct_tints_per_slot():
	# Acceptance criterion #4: remote kittens are visually distinct from
	# the local player. Different remote players get different tints from
	# CoopPlayerLayer.TINTS, indexed by lobby slot.
	var gs := get_node("/root/GameState")
	gs.set_lobby(_make_lobby_with_players("me", ["me", "alice", "bob"]))
	gs.coop_session = _make_session_with_party(["alice", "bob"])
	var layer := CoopPlayerLayer.new()
	add_child_autofree(layer)
	var alice := layer.remote_kitten_for("alice")
	var bob := layer.remote_kitten_for("bob")
	assert_ne(alice.tint_color, bob.tint_color,
		"two remote players get distinct tints")

func test_lobby_updated_signal_triggers_reconcile():
	# Acceptance criterion #6/#7: a new player joining mid-session shows
	# up without a manual reconcile call. The layer subscribes to
	# lobby_updated in _ready, so emitting it after a roster change must
	# spawn the new kitten.
	var gs := get_node("/root/GameState")
	var lobby := _make_lobby_with_players("me", ["me", "alice"])
	gs.set_lobby(lobby)
	gs.coop_session = _make_session_with_party(["alice"])
	var layer := CoopPlayerLayer.new()
	add_child_autofree(layer)
	assert_eq(layer.remote_kitten_count(), 1)
	# bob joins after the layer is in the tree.
	lobby.lobby_state.add_player(LobbyPlayer.make("bob", "k_bob", "Mage"))
	lobby.lobby_updated.emit(lobby.lobby_state)
	assert_eq(layer.remote_kitten_count(), 2,
		"lobby_updated emission spawned bob without manual reconcile")

func test_remote_kitten_joins_taunt_targets_group():
	# PRD #124 cross-client TAUNT: a remote caster is rendered as a
	# RemoteKitten on this client, not a Player node. Enemy._select_taunt
	# _target_by_id walks the "taunt_targets" group looking for a
	# player_id match — RemoteKitten must register itself there.
	var scene: PackedScene = load(REMOTE_KITTEN_PATH)
	var inst: RemoteKitten = scene.instantiate()
	inst.player_id = "p_remote"
	add_child_autofree(inst)
	assert_true(inst.is_in_group("taunt_targets"),
		"RemoteKitten._ready must add the node to the taunt_targets group")
	assert_eq(inst.player_id, "p_remote",
		"player_id is preserved for the id-match resolver")

func test_remote_kitten_scene_loads():
	# Smoke: the .tscn parses cleanly, root node is a RemoteKitten with
	# the placeholder + label children the script expects.
	var scene: PackedScene = load(REMOTE_KITTEN_PATH)
	assert_not_null(scene, "remote_kitten.tscn must be loadable")
	var inst: Node = scene.instantiate()
	assert_not_null(inst, "must instantiate")
	assert_true(inst is RemoteKitten,
		"root node must be bound to RemoteKitten script")
	assert_not_null(inst.get_node_or_null("Placeholder"))
	assert_not_null(inst.get_node_or_null("Label"))
	inst.free()

func test_spawn_sets_character_class_on_remote_kitten():
	# Issue #170 acceptance: CoopPlayerLayer._spawn must propagate the
	# LobbyPlayer.character_class_int into the new RemoteKitten so the
	# remote sprite is class-correct on first render.
	var gs := get_node("/root/GameState")
	var nl := NakamaLobby.new()
	nl.local_player_id = "me"
	var ls := LobbyState.new("ABCDE")
	var alice := LobbyPlayer.make("alice", "k_alice", "Battle Kitten")
	alice.character_class_int = CharacterData.CharacterClass.BATTLE_KITTEN
	ls.add_player(LobbyPlayer.make("me", "k_me", "Wizard Kitten"))
	ls.add_player(alice)
	nl.lobby_state = ls
	gs.set_lobby(nl)
	gs.coop_session = _make_session_with_party(["alice"])
	var layer := CoopPlayerLayer.new()
	add_child_autofree(layer)
	var rk: RemoteKitten = layer.remote_kitten_for("alice")
	assert_not_null(rk)
	assert_eq(rk.character_class, CharacterData.CharacterClass.BATTLE_KITTEN,
		"spawn must carry character_class_int through to the kitten")

func test_reconcile_updates_character_class_on_existing_kitten():
	# Issue #170 acceptance: a late PLAYER_INFO must update character_class
	# on the already-spawned RemoteKitten (and refresh its sprite).
	var gs := get_node("/root/GameState")
	var nl := NakamaLobby.new()
	nl.local_player_id = "me"
	var ls := LobbyState.new("ABCDE")
	var alice := LobbyPlayer.make("alice", "k_alice", "Wizard Kitten")
	alice.character_class_int = CharacterData.CharacterClass.WIZARD_KITTEN
	ls.add_player(LobbyPlayer.make("me", "k_me", "Wizard Kitten"))
	ls.add_player(alice)
	nl.lobby_state = ls
	gs.set_lobby(nl)
	gs.coop_session = _make_session_with_party(["alice"])
	var layer := CoopPlayerLayer.new()
	add_child_autofree(layer)
	var rk: RemoteKitten = layer.remote_kitten_for("alice")
	assert_eq(rk.character_class, CharacterData.CharacterClass.WIZARD_KITTEN)
	# Late PLAYER_INFO lands: alice is actually Sleepy Kitten.
	alice.character_class_int = CharacterData.CharacterClass.SLEEPY_KITTEN
	layer.reconcile()
	assert_eq(layer.remote_kitten_for("alice"), rk,
		"reconcile reuses the existing node, no respawn")
	assert_eq(rk.character_class, CharacterData.CharacterClass.SLEEPY_KITTEN,
		"reconcile must refresh character_class on existing kittens")

func test_kittens_spawned_before_session_started_get_network_sync_on_start():
	# Regression: in the live scene, CoopPlayerLayer._ready (child) runs
	# before main_scene._ready (parent), which is where coop_session.start()
	# is called. So the first reconcile spawns remote kittens with
	# coop_session.network_sync still null, and RemoteKitten._process
	# early-returns on null sync — the kitten freezes at (0, 0). Once
	# session.start() builds network_sync, the layer must refresh the
	# already-spawned kittens' refs (via session_started → reconcile) or
	# the teammate appears stuck in place forever.
	var gs := get_node("/root/GameState")
	gs.set_lobby(_make_lobby_with_players("me", ["me", "alice"]))
	# Construct session WITHOUT network_sync (mimics post-_init / pre-start
	# lifetime that lobby._on_match_started leaves before scene change).
	var session := CoopSession.new()
	gs.coop_session = session
	var layer := CoopPlayerLayer.new()
	add_child_autofree(layer)
	var alice: RemoteKitten = layer.remote_kitten_for("alice")
	assert_not_null(alice, "spawned even with null sync — placeholder is visible")
	assert_null(alice.network_sync,
		"sanity: spawn captured the null sync that was current at _ready time")
	# Simulate coop_session.start() building network_sync and emitting
	# session_started — the lifecycle hook on the live path.
	session.network_sync = NetworkSyncManager.new()
	session.session_started.emit()
	assert_eq(alice.network_sync, session.network_sync,
		"session_started must trigger a reconcile that patches in the new sync")

# Slice 2 of PRD #328 (issue #330). CoopPlayerLayer subscribes to
# lobby.position_received and fans the facing_x sign to the matching
# RemoteKitten — the seam GameState's handler intentionally skips so the
# autoload doesn't need a CoopPlayerLayer reference.

func test_position_received_forwards_facing_to_matching_kitten():
	var gs := get_node("/root/GameState")
	var lobby := _make_lobby_with_players("me", ["me", "alice"])
	gs.set_lobby(lobby)
	gs.coop_session = _make_session_with_party(["alice"])
	var layer := CoopPlayerLayer.new()
	add_child_autofree(layer)
	var alice: RemoteKitten = layer.remote_kitten_for("alice")
	# Wizard kitten asset faces left → moving right must flip.
	lobby.position_received.emit("alice", Vector2.ZERO, 0.0, 1)
	assert_true(alice.get_node("Sprite2D").flip_h,
		"facing fans to the matching kitten and applies the flip")

func test_position_received_ignores_unknown_player_id():
	# A packet for an id with no spawned kitten (mid-roster-update,
	# stale packet from a departed peer) is a silent no-op rather than
	# a crash.
	var gs := get_node("/root/GameState")
	var lobby := _make_lobby_with_players("me", ["me", "alice"])
	gs.set_lobby(lobby)
	gs.coop_session = _make_session_with_party(["alice"])
	var layer := CoopPlayerLayer.new()
	add_child_autofree(layer)
	# No assertion needed beyond not crashing — the handler's null guard
	# is what we're exercising here.
	lobby.position_received.emit("ghost", Vector2.ZERO, 0.0, 1)
	assert_true(true)

func test_main_scene_includes_coop_player_layer():
	# Regression guard parallel to test_main_scene_includes_touch_controls:
	# main.tscn must contain a CoopPlayerLayer or remote players never
	# render in the dungeon.
	var scene: PackedScene = load("res://scenes/main.tscn")
	assert_not_null(scene)
	var inst: Node = scene.instantiate()
	var layer: Node = inst.get_node_or_null("CoopPlayerLayer")
	assert_not_null(layer, "main.tscn must contain a CoopPlayerLayer node")
	assert_true(layer is CoopPlayerLayer,
		"CoopPlayerLayer node must be bound to the CoopPlayerLayer script")
	inst.free()


# --- Slice 3 of PRD #328 (issue #331): equipped weapon visual fan-out --------

func test_spawn_seeds_equipped_weapon_id_from_lobby_player():
	# Late-joiner case: a remote player is already in the lobby with an
	# equipped weapon when the layer reconciles for the first time. The
	# spawned RemoteKitten must show that weapon, not the class-default,
	# without waiting for a follow-up PLAYER_INFO rebroadcast.
	var gs := get_node("/root/GameState")
	var nl := NakamaLobby.new()
	nl.local_player_id = "me"
	var ls := LobbyState.new("ABCDE")
	var alice := LobbyPlayer.make("alice", "k_alice", "Battle Kitten")
	alice.character_class_int = CharacterData.CharacterClass.BATTLE_KITTEN
	alice.equipped_weapon_id = "iron_sword"
	ls.add_player(LobbyPlayer.make("me", "k_me", "Battle Kitten"))
	ls.add_player(alice)
	nl.lobby_state = ls
	gs.set_lobby(nl)
	gs.coop_session = _make_session_with_party(["alice"])
	var layer := CoopPlayerLayer.new()
	add_child_autofree(layer)
	var rk: RemoteKitten = layer.remote_kitten_for("alice")
	assert_not_null(rk)
	var ws := rk.weapon_pivot.get_node_or_null("Sprite2D") as Sprite2D
	assert_not_null(ws)
	assert_true(ws.visible,
		"late-joiner spawn must seed the weapon visual immediately — "
		+ "without this the kitten renders unarmed until the next "
		+ "PLAYER_INFO rebroadcast")
	assert_eq(ws.texture.resource_path,
		"res://assets/sprites/weapon_slippery_mackerel.png")


func test_attack_received_forwards_to_matching_kitten_play_attack():
	# Slice 4 of PRD #328 (issue #332). CoopPlayerLayer subscribes to
	# lobby.attack_received and routes the inbound direction to the
	# matching RemoteKitten via play_attack, which drives the existing
	# AttackChoreographer path. Observable: the choreographer's phase
	# flips off IDLE once start_attack runs.
	var gs := get_node("/root/GameState")
	var lobby := _make_lobby_with_players("me", ["me", "alice"])
	gs.set_lobby(lobby)
	gs.coop_session = _make_session_with_party(["alice"])
	var layer := CoopPlayerLayer.new()
	add_child_autofree(layer)
	var alice: RemoteKitten = layer.remote_kitten_for("alice")
	assert_not_null(alice.attack_choreographer,
		"precondition: battle-class default for fixture has a choreographer")
	assert_eq(alice.attack_choreographer.phase, AttackChoreographer.Phase.IDLE,
		"precondition: kitten starts idle")
	lobby.attack_received.emit("alice", Vector2.RIGHT, NakamaLobby.ATTACK_KIND_WEAPON_SWING, "")
	assert_ne(alice.attack_choreographer.phase, AttackChoreographer.Phase.IDLE,
		"attack_received must drive the matching kitten's choreographer "
		+ "off IDLE via play_attack — same path the local Player walks")


func test_attack_received_ignores_unknown_player_id():
	# A packet for an id with no spawned kitten (stale packet from a
	# departed peer / mid-roster-update) is a silent no-op rather than a
	# crash. Mirrors the position_received unknown-id guard.
	var gs := get_node("/root/GameState")
	var lobby := _make_lobby_with_players("me", ["me", "alice"])
	gs.set_lobby(lobby)
	gs.coop_session = _make_session_with_party(["alice"])
	var layer := CoopPlayerLayer.new()
	add_child_autofree(layer)
	lobby.attack_received.emit("ghost", Vector2.RIGHT, NakamaLobby.ATTACK_KIND_WEAPON_SWING, "")
	assert_true(true)


# ---- Slice 5 of PRD #328 (issue #333): spell-cast / quickbar-cast fan-out. ----

func test_attack_received_spell_cast_drives_kittens_play_spell_cast():
	# A spell_cast packet (wizard primary, empty spell_id) must still
	# drive the matching kitten's choreographer off IDLE — the cast pose
	# IS the visual today. Routes via RemoteKitten.play_spell_cast.
	var gs := get_node("/root/GameState")
	var lobby := _make_lobby_with_players("me", ["me", "alice"])
	gs.set_lobby(lobby)
	gs.coop_session = _make_session_with_party(["alice"])
	var layer := CoopPlayerLayer.new()
	add_child_autofree(layer)
	var alice: RemoteKitten = layer.remote_kitten_for("alice")
	assert_eq(alice.attack_choreographer.phase, AttackChoreographer.Phase.IDLE)
	lobby.attack_received.emit("alice", Vector2.RIGHT, NakamaLobby.ATTACK_KIND_SPELL_CAST, "")
	assert_ne(alice.attack_choreographer.phase, AttackChoreographer.Phase.IDLE,
		"spell_cast must drive play_spell_cast → choreographer off IDLE")


func test_attack_received_quickbar_cast_drives_kittens_play_spell_cast():
	# A quickbar_cast packet (with spell_id) routes through the same
	# play_spell_cast hook. spell_id is reserved for future per-spell
	# visual differentiation; today the cast pose suffices.
	var gs := get_node("/root/GameState")
	var lobby := _make_lobby_with_players("me", ["me", "alice"])
	gs.set_lobby(lobby)
	gs.coop_session = _make_session_with_party(["alice"])
	var layer := CoopPlayerLayer.new()
	add_child_autofree(layer)
	var alice: RemoteKitten = layer.remote_kitten_for("alice")
	assert_eq(alice.attack_choreographer.phase, AttackChoreographer.Phase.IDLE)
	lobby.attack_received.emit("alice", Vector2.RIGHT,
		NakamaLobby.ATTACK_KIND_QUICKBAR_CAST, "fireball")
	assert_ne(alice.attack_choreographer.phase, AttackChoreographer.Phase.IDLE)


func test_attack_received_unknown_kind_silent_no_op():
	# Protocol drift defense: an unknown `kind` from a newer client
	# must NOT crash the render loop — drop silently.
	var gs := get_node("/root/GameState")
	var lobby := _make_lobby_with_players("me", ["me", "alice"])
	gs.set_lobby(lobby)
	gs.coop_session = _make_session_with_party(["alice"])
	var layer := CoopPlayerLayer.new()
	add_child_autofree(layer)
	var alice: RemoteKitten = layer.remote_kitten_for("alice")
	lobby.attack_received.emit("alice", Vector2.RIGHT, "future_kind_xyz", "")
	assert_eq(alice.attack_choreographer.phase, AttackChoreographer.Phase.IDLE,
		"unknown kind leaves the choreographer untouched")


func test_reconcile_updates_equipped_weapon_id_on_existing_kitten():
	# Equip-swap case: a peer changes their weapon mid-session. The
	# PLAYER_INFO rebroadcast lands → apply_state updates the LobbyPlayer
	# → lobby_updated fires → reconcile must fan the new id to the
	# already-spawned RemoteKitten without respawning the node.
	var gs := get_node("/root/GameState")
	var nl := NakamaLobby.new()
	nl.local_player_id = "me"
	var ls := LobbyState.new("ABCDE")
	var alice := LobbyPlayer.make("alice", "k_alice", "Battle Kitten")
	alice.character_class_int = CharacterData.CharacterClass.BATTLE_KITTEN
	ls.add_player(LobbyPlayer.make("me", "k_me", "Battle Kitten"))
	ls.add_player(alice)
	nl.lobby_state = ls
	gs.set_lobby(nl)
	gs.coop_session = _make_session_with_party(["alice"])
	var layer := CoopPlayerLayer.new()
	add_child_autofree(layer)
	var rk: RemoteKitten = layer.remote_kitten_for("alice")
	var ws := rk.weapon_pivot.get_node_or_null("Sprite2D") as Sprite2D
	assert_false(ws.visible, "precondition: alice starts unarmed")
	# Equip-swap rebroadcast lands.
	alice.equipped_weapon_id = "iron_sword"
	layer.reconcile()
	assert_eq(layer.remote_kitten_for("alice"), rk,
		"reconcile reuses the existing node, no respawn on equip-swap")
	assert_true(ws.visible,
		"equip-swap rebroadcast must update the existing kitten's weapon")


# ---- Slice 7 of PRD #328 (issue #335): player_hit_received fan-out. ----

func test_player_hit_received_drives_matching_kitten_apply_hit_reaction():
	# CoopPlayerLayer subscribes to lobby.player_hit_received and routes
	# the inbound (damage, source_position) to the matching RemoteKitten's
	# apply_hit_reaction — same shape as the position/attack fan-outs.
	# Observable: the kitten's sprite flashes to HIT_FLASH_COLOR.
	var gs := get_node("/root/GameState")
	var lobby := _make_lobby_with_players("me", ["me", "alice"])
	gs.set_lobby(lobby)
	gs.coop_session = _make_session_with_party(["alice"])
	var layer := CoopPlayerLayer.new()
	add_child_autofree(layer)
	var alice: RemoteKitten = layer.remote_kitten_for("alice")
	alice.global_position = Vector2(100.0, 0.0)
	var sprite: Sprite2D = alice.get_node("Sprite2D")
	var pre_modulate := sprite.modulate
	lobby.player_hit_received.emit("alice", 7, Vector2.ZERO)
	assert_ne(sprite.modulate, pre_modulate,
		"player_hit_received must drive the matching kitten's hit-flash")
	assert_gt(sprite.position.x, 0.0,
		"knockback offset pushes away from the source at (0,0)")


func test_player_hit_received_ignores_unknown_player_id():
	# A packet for an id with no spawned kitten (stale packet from a
	# departed peer / mid-roster-update) is a silent no-op rather than a
	# crash. Mirrors the position/attack unknown-id guards.
	var gs := get_node("/root/GameState")
	var lobby := _make_lobby_with_players("me", ["me", "alice"])
	gs.set_lobby(lobby)
	gs.coop_session = _make_session_with_party(["alice"])
	var layer := CoopPlayerLayer.new()
	add_child_autofree(layer)
	lobby.player_hit_received.emit("ghost", 7, Vector2.ZERO)
	assert_true(true)


func test_player_hit_received_spawns_damage_number_on_matching_kitten():
	# Slice of PRD #341 (issue #344). In addition to the existing flash/
	# knockback reaction, _on_player_hit_received calls the matching
	# kitten's spawn_damage_number so a red number pops over the
	# teammate's avatar — parity with the local player's own hit numbers.
	var gs := get_node("/root/GameState")
	var lobby := _make_lobby_with_players("me", ["me", "alice"])
	gs.set_lobby(lobby)
	gs.coop_session = _make_session_with_party(["alice"])
	var layer := CoopPlayerLayer.new()
	add_child_autofree(layer)
	var alice: RemoteKitten = layer.remote_kitten_for("alice")
	var parent := alice.get_parent()
	lobby.player_hit_received.emit("alice", 7, Vector2.ZERO)
	var found := false
	for child in parent.get_children():
		if child is FloatingText:
			var label := (child as FloatingText).get_node_or_null("Label") as Label
			if label != null and label.text == "7":
				found = true
				assert_eq(label.modulate,
					DamageKind.color_for(DamageKind.Kind.PHYSICAL),
					"teammate damage number renders in PHYSICAL red")
				break
	assert_true(found,
		"player_hit_received must spawn a red damage number over the kitten")


# ---- Slice 8 of PRD #328 (issue #336): player_died_received fan-out. ----

func test_player_died_received_drives_matching_kitten_apply_death():
	# CoopPlayerLayer subscribes to lobby.player_died_received and fans
	# the target_id to the matching RemoteKitten's apply_death so the
	# dead teammate's sprite shifts to DEAD_TINT and stops sampling
	# network_sync.
	var gs := get_node("/root/GameState")
	var lobby := _make_lobby_with_players("me", ["me", "alice"])
	gs.set_lobby(lobby)
	gs.coop_session = _make_session_with_party(["alice"])
	var layer := CoopPlayerLayer.new()
	add_child_autofree(layer)
	var alice: RemoteKitten = layer.remote_kitten_for("alice")
	assert_false(alice.is_dead(), "precondition: alice alive")
	lobby.player_died_received.emit("alice")
	assert_true(alice.is_dead(),
		"player_died_received must drive the matching kitten's apply_death")


func test_player_died_received_ignores_unknown_player_id():
	# Stale packet from a departed peer / mid-roster-update — silent
	# no-op rather than a crash. Same shape as the position/attack/hit
	# unknown-id guards.
	var gs := get_node("/root/GameState")
	var lobby := _make_lobby_with_players("me", ["me", "alice"])
	gs.set_lobby(lobby)
	gs.coop_session = _make_session_with_party(["alice"])
	var layer := CoopPlayerLayer.new()
	add_child_autofree(layer)
	lobby.player_died_received.emit("ghost")
	assert_true(true, "unknown id is a silent no-op")


func test_position_received_revives_dead_kitten():
	# Revive path: after apply_death, the next OP_POSITION packet from
	# the same peer drives apply_revive so position updates resume on
	# the remote view. The local CoopRouter.revive flow brings the dead
	# player back to life on the sender side; this layer's job is just
	# to clear the freeze on the next position broadcast.
	var gs := get_node("/root/GameState")
	var lobby := _make_lobby_with_players("me", ["me", "alice"])
	gs.set_lobby(lobby)
	gs.coop_session = _make_session_with_party(["alice"])
	var layer := CoopPlayerLayer.new()
	add_child_autofree(layer)
	var alice: RemoteKitten = layer.remote_kitten_for("alice")
	lobby.player_died_received.emit("alice")
	assert_true(alice.is_dead(), "precondition: alice marked dead")
	lobby.position_received.emit("alice", Vector2(10.0, 20.0), 0.5, 0)
	assert_false(alice.is_dead(),
		"position packet for a dead kitten must drive apply_revive")
